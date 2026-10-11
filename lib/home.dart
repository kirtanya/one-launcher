import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_drawer.dart';
import 'apps.dart';
import 'prefs.dart';
import 'sheets.dart';
import 'ui/components.dart';
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
  static const _rest = 0.52;

  List<AppEntry> _apps = const [];
  final _sheet = DraggableScrollableController();
  final _expanded = ValueNotifier<double>(0); // 0 = resting, 1 = full screen
  final _drawerKey = GlobalKey<AppDrawerState>();

  Prefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    prefs.addListener(_rebuild);
    Apps.instance.onAppsChanged = _loadApps;
    Apps.instance.onHomePressed = _goHome;
    _sheet.addListener(() => _expanded.value = ((_sheet.size - _rest) / (1 - _rest)).clamp(0.0, 1.0));
    _loadApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    prefs.removeListener(_rebuild);
    _sheet.dispose();
    _expanded.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadApps();
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

  /// Home button while already home: close everything.
  void _goHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _drawerKey.currentState?.reset();
    _collapse();
  }

  Future<void> _launch(AppEntry app) async {
    prefs.recordLaunch(app.package);
    await Apps.instance.launch(app.package);
    // Reset quietly once the other app has covered us.
    Future.delayed(const Duration(milliseconds: 350), () {
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
        if (_drawerKey.currentState?.searching ?? false) return _drawerKey.currentState!.reset();
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
                      onSwipeUp: _expand,
                      onSwipeDown: Apps.instance.openNotifications,
                      onTapClock: () => _openNamed(['clock']),
                      onTapDate: () => _openNamed(['calendar', 'google calendar']),
                      onWallpaper: Apps.instance.openWallpaperPicker,
                      onSettings: _settings,
                    ),
                  ),
                ),

                // ---- Bottom half: the app view sheet. ----
                DraggableScrollableSheet(
                  controller: _sheet,
                  initialChildSize: _rest,
                  minChildSize: _rest,
                  maxChildSize: 1,
                  snap: true,
                  builder: (context, scroll) =>
                      AppDrawer(key: _drawerKey, apps: _apps, prefs: prefs, scroll: scroll, expanded: _expanded, onLaunch: _launch, onWantFull: _expand),
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
  const _TopArea({
    required this.onSwipeUp,
    required this.onSwipeDown,
    required this.onTapClock,
    required this.onTapDate,
    required this.onWallpaper,
    required this.onSettings,
  });

  final VoidCallback onSwipeUp, onSwipeDown, onTapClock, onTapDate, onWallpaper, onSettings;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) onSwipeUp();
        if (v > 200) onSwipeDown();
      },
      onLongPress: onSettings,
      child: DecoratedBox(
        // Gentle dark wash at the top so the status bar and buttons read on bright wallpapers.
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x40000000), Color(0x00000000)], stops: [0, .45]),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s8, DS.rSheet + DS.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: onTapDate,
                          child: Padding(padding: const EdgeInsets.all(DS.s8), child: _Date()),
                        ),
                      ),
                    ),
                    CircleButton(icon: Icons.wallpaper_rounded, tone: CircleTone.glass, tooltip: 'Wallpaper', onTap: onWallpaper),
                    CircleButton(icon: Icons.tune_rounded, tone: CircleTone.glass, tooltip: 'Launcher settings', onTap: onSettings),
                  ],
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: onTapClock,
                    child: Padding(
                      padding: const EdgeInsets.only(right: DS.s8),
                      child: _Clock(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ticks once a minute (checks every second so it flips on time).
mixin _Ticking<W extends StatefulWidget> on State<W> {
  DateTime now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = DateTime.now();
      if (n.minute != now.minute) setState(() => now = n);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _Clock extends StatefulWidget {
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> with _Ticking {
  @override
  Widget build(BuildContext context) {
    final is24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final h = is24 ? now.hour : (now.hour % 12 == 0 ? 12 : now.hour % 12);
    final time = '${h.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Semantics(
      label: 'Time $time. Opens Clock',
      button: true,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Text(time, style: DS.clock),
      ),
    );
  }
}

class _Date extends StatefulWidget {
  @override
  State<_Date> createState() => _DateState();
}

class _DateState extends State<_Date> with _Ticking {
  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) => Text('${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}', style: DS.wallpaperDate);
}
