import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_drawer.dart';
import 'apps.dart';
import 'prefs.dart';
import 'search.dart';
import 'search_dock.dart';
import 'top/top_carousel.dart';
import 'sheets.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';

/// The whole launcher is one screen:
/// top half = big clock over the wallpaper + launcher options,
/// bottom half = the app view as a sheet. Swipe the sheet up and the clock
/// scales down and fades away; swipe down to bring it back.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.prefs});
  final Prefs prefs;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// Sheet height when resting (fraction of the screen).
  /// Where the sheet rests (fraction of the screen). The user picks the split in Settings.
  double get _rest => 1 - prefs.topShare;

  List<AppEntry> _apps = const [];
  final _sheet = DraggableScrollableController();
  final _expanded = ValueNotifier<double>(0); // 0 = resting, 1 = full screen
  final _drawerKey = GlobalKey<AppDrawerState>();

  // Search lives in the bottom dock.
  final _query = TextEditingController();
  final _focus = FocusNode();
  bool _searching = false; // dock is a live text field
  bool _showResults = false; // sheet shows results (only once it's full, so the swap can't fight the snap)
  bool _compact = false; // dock shrunk to a circle while the list is scrolled up

  Prefs get prefs => widget.prefs;

  /// Bumped on every setState so the sheet's contents rebuild without rebuilding the sheet.
  final _rev = ValueNotifier<int>(0);

  /// Pinged when the launcher comes back to the front or a permission changes, so the
  /// top pages (screen time, battery, calendar) reload.
  final _refresh = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rev.value++;
  }

  /// Built once per split ratio. Flutter's DraggableScrollableSheet resets its extent whenever
  /// the widget is rebuilt, which cancels a running snap/animation and drops the scroll
  /// position. Reusing the same instance makes the framework skip it; its contents listen to
  /// [_rev] instead. Only a new split (Settings → Layout) makes a new one.
  Widget? _sheetCache;
  double? _sheetRest;

  Widget get _sheetWidget {
    final rest = _rest;
    if (_sheetCache != null && _sheetRest == rest) return _sheetCache!;
    final hadSheet = _sheetCache != null;
    _sheetRest = rest;
    if (hadSheet) {
      // Glide to the new resting height (unless the sheet is open full screen).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sheet.isAttached && _expanded.value < 1) _sheet.animateTo(rest, duration: Motion.snapDuration, curve: Motion.settle);
      });
    }
    return _sheetCache = _buildSheet(rest);
  }

  Widget _buildSheet(double rest) => DraggableScrollableSheet(
    controller: _sheet,
    initialChildSize: rest,
    minChildSize: rest,
    maxChildSize: 1,
    snap: true,
    builder: (context, scroll) => ValueListenableBuilder<int>(
      valueListenable: _rev,
      builder: (context, _, _) => AppDrawer(
        key: _drawerKey,
        apps: _apps,
        prefs: prefs,
        scroll: scroll,
        expanded: _expanded,
        searching: _showResults,
        query: _query.text,
        onLaunch: _launch,
        onCompact: _setCompact,
        onWantFull: _expand,
        onDismissSearch: _dismissSearch,
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    prefs.addListener(_rebuild);
    Apps.instance.onAppsChanged = _loadApps;
    Apps.instance.onHomePressed = _goHome;
    Apps.instance.onPermissionsChanged = () => _refresh.value++;
    _sheet.addListener(() => _expanded.value = ((_sheet.size - _rest) / (1 - _rest)).clamp(0.0, 1.0));
    _loadApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    prefs.removeListener(_rebuild);
    _sheet.dispose();
    _query.dispose();
    _focus.dispose();
    _expanded.dispose();
    _rev.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadApps();
      _refresh.value++;
    }
  }

  void _rebuild() => setState(() {});

  Future<void> _loadApps() async {
    final apps = await Apps.instance.list();
    if (mounted) setState(() => _apps = apps);
  }

  // ---- Sheet ---------------------------------------------------------------

  void _expand() {
    if (_sheet.isAttached) _sheet.animateTo(1, duration: Motion.snapDuration, curve: Motion.settle);
  }

  void _collapse({bool instant = false}) {
    if (!_sheet.isAttached) return;
    instant ? _sheet.jumpTo(_rest) : _sheet.animateTo(_rest, duration: Motion.snapDuration, curve: Motion.settle);
  }

  // ---- Search --------------------------------------------------------------

  Future<void> _startSearch() async {
    HapticFeedback.selectionClick();
    setState(() {
      _searching = true;
      _compact = false;
    });
    _focus.requestFocus();
    if (_sheet.isAttached) await _sheet.animateTo(1, duration: Motion.snapDuration, curve: Motion.settle);
    if (mounted && _searching) setState(() => _showResults = true);
  }

  void _stopSearch() {
    _focus.unfocus();
    _query.clear();
    if (_searching || _compact || _showResults) {
      setState(() {
        _searching = false;
        _showResults = false;
        _compact = false;
      });
    }
  }

  void _onQuery(String q) {
    setState(() {});
    final r = searchApps(_apps, q);
    if (prefs.autoOpenSingleMatch && q.trim().isNotEmpty && r.length == 1) _launch(r.first);
  }

  void _onSubmit(String q) {
    final r = searchApps(_apps, q);
    if (r.isNotEmpty) _launch(r.first);
  }

  bool _collapseOnRelease = false;

  /// Pulled down while searching: close the keyboard and results now, and drop the
  /// sheet back to the clock once the finger lifts (so we don't fight the drag).
  void _dismissSearch() {
    if (!_searching) return;
    _stopSearch();
    _collapseOnRelease = true;
  }

  void _setCompact(bool v) {
    if (v != _compact && !_searching) setState(() => _compact = v);
  }

  /// Home button while already home: close everything.
  void _goHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _stopSearch();
    _drawerKey.currentState?.reset();
    _collapse();
  }

  Future<void> _launch(AppEntry app) async {
    prefs.recordLaunch(app.package);
    await Apps.instance.launch(app.package);
    // Reset quietly once the other app has covered us.
    Future.delayed(const Duration(milliseconds: 350), () {
      _stopSearch();
      _drawerKey.currentState?.reset();
      _collapse(instant: true);
    });
  }

  AppEntry? _findByName(List<String> names) {
    for (final n in names) {
      final hit = _apps.where((a) => a.label.toLowerCase() == n).firstOrNull;
      if (hit != null) return hit;
    }
    return null;
  }

  void _openNamed(List<String> names) {
    final a = _findByName(names);
    if (a != null) _launch(a);
  }

  void _settings() {
    HapticFeedback.mediumImpact();
    showSettingsSheet(context, prefs: prefs, apps: _apps);
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (_searching) return _stopSearch();
        if (_expanded.value > 0) _collapse();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: LayoutBuilder(
          builder: (context, c) {
            final topHeight = c.maxHeight * (1 - _rest) + DS.rSheet;
            return Stack(
              fit: StackFit.expand,
              children: [
                // ---- Top half: clock + options. Scales down and fades as the sheet rises. ----
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: topHeight,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _expanded,
                    builder: (context, e, child) => IgnorePointer(
                      ignoring: e > 0.3,
                      child: Opacity(
                        opacity: (1 - e * 1.6).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, -topHeight * 0.18 * e),
                          child: Transform.scale(scale: 1 - 0.3 * e, alignment: Alignment.topCenter, child: child),
                        ),
                      ),
                    ),
                    child: _TopArea(
                      carousel: TopCarousel(
                        prefs: prefs,
                        refresh: _refresh,
                        onTapClock: () => _openNamed(['clock']),
                        onTapDate: () => _openNamed(['calendar', 'google calendar']),
                      ),
                      onCustomise: () {
                        HapticFeedback.mediumImpact();
                        showCustomiseTop(context, prefs: prefs);
                      },
                      padding: prefs.topPadding,
                      onSwipeUp: _expand,
                      onSwipeDown: Apps.instance.openNotifications,
                    ),
                  ),
                ),

                // ---- Bottom half: the app view sheet. ----
                NotificationListener<ScrollEndNotification>(
                  onNotification: (_) {
                    if (_collapseOnRelease) {
                      _collapseOnRelease = false;
                      _collapse();
                    }
                    return false;
                  },
                  child: NotificationListener<DraggableScrollableNotification>(
                    // Dragging the whole sheet down while searching also ends the search.
                    onNotification: (n) {
                      if (_showResults && n.extent < 0.97) _dismissSearch();
                      return false;
                    },
                    child: _sheetWidget,
                  ),
                ),

                // ---- Fade under the dock, so it reads as floating above the cards. ----
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: SearchDock.height + MediaQuery.paddingOf(context).bottom + DS.s48,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x001F1F1F), Color(0xE61F1F1F)]),
                      ),
                    ),
                  ),
                ),

                // ---- Search dock (iOS style), floating at the bottom. ----
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SearchDock(
                    compact: _compact,
                    active: _searching,
                    controller: _query,
                    focus: _focus,
                    hint: 'Search ${_apps.length} apps',
                    onActivate: _startSearch,
                    onClose: _stopSearch,
                    onChanged: _onQuery,
                    onSubmitted: _onSubmit,
                    onWallpaper: Apps.instance.openWallpaperPicker,
                    onSettings: _settings,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---- Top area ---------------------------------------------------------------

class _TopArea extends StatelessWidget {
  const _TopArea({required this.carousel, required this.padding, required this.onSwipeUp, required this.onSwipeDown, required this.onCustomise});

  final Widget carousel;
  final double padding; // user-set breathing room (Settings → Top widgets padding)
  final VoidCallback onSwipeUp, onSwipeDown, onCustomise;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) onSwipeUp();
        if (v > 200) onSwipeDown();
      },
      onLongPress: onCustomise, // long-press the top half → choose its pages
      child: DecoratedBox(
        // Gentle dark wash at the top so the status bar reads on bright wallpapers.
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x40000000), Color(0x00000000)], stops: [0, .45]),
        ),
        child: SafeArea(
          bottom: false,
          child: AnimatedPadding(
            duration: Motion.snapDuration,
            curve: Motion.settle,
            padding: EdgeInsets.fromLTRB(DS.s8 + padding, DS.s4 + padding * .5, DS.s8 + padding, DS.rSheet + DS.s4 + padding * .5),
            child: carousel,
          ),
        ),
      ),
    );
  }
}
