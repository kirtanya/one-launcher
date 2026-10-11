import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_drawer.dart';
import 'apps.dart';
import 'prefs.dart';
import 'sheets.dart';
import 'tokens.dart';
import 'widgets.dart';

/// The home screen: clock, date, favourite apps.
/// Swipe up → all apps. Swipe down → notifications. Long-press empty space → settings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.prefs});
  final Prefs prefs;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  List<AppEntry> _apps = const [];
  late final AnimationController _drawer = AnimationController(vsync: this, duration: T.medium);
  final _drawerKey = GlobalKey<AppDrawerState>();

  Prefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    prefs.addListener(_rebuild);
    Apps.instance.onAppsChanged = _loadApps;
    Apps.instance.onHomePressed = _goHome;
    _drawer.addStatusListener((s) {
      if (s == AnimationStatus.completed) _drawerKey.currentState?.opened();
      if (s == AnimationStatus.dismissed) _drawerKey.currentState?.closed();
    });
    _loadApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    prefs.removeListener(_rebuild);
    _drawer.dispose();
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

  /// Home button while already home: close everything.
  void _goHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _closeDrawer();
  }

  void _openDrawer() {
    HapticFeedback.selectionClick();
    _drawer.animateTo(1, curve: Curves.easeOutCubic);
  }

  void _closeDrawer({bool instant = false}) {
    if (instant) {
      _drawer.value = 0;
    } else {
      _drawer.animateBack(0, curve: Curves.easeOutCubic);
    }
  }

  Future<void> _launch(AppEntry app) async {
    prefs.recordLaunch(app.package);
    await Apps.instance.launch(app.package);
    // Reset quietly once the other app has covered us.
    Future.delayed(const Duration(milliseconds: 350), () => _closeDrawer(instant: true));
  }

  AppEntry? _find(String pkg) => _apps.where((a) => a.package == pkg).firstOrNull;

  AppEntry? _findByName(List<String> names) {
    for (final n in names) {
      final hit = _apps.where((a) => a.label.toLowerCase() == n).firstOrNull;
      if (hit != null) return hit;
    }
    return null;
  }

  // ---- Home gestures -------------------------------------------------------

  // Swipe left → app view slides in from the right (like the iOS App Library).
  // Swipe right on the app view → back home. Swipe down → notifications.

  /// Finger moved sideways by dx (negative = left = towards the app view).
  void _dragPages(double dx) => _drawer.value -= dx / MediaQuery.sizeOf(context).width;

  void _onDownEnd(DragEndDetails d) {
    if ((d.primaryVelocity ?? 0) > 100) Apps.instance.openNotifications();
  }

  /// Snap open or shut after a drag, based on speed then position.
  void settleDrawer(double velocity) {
    if (velocity < -300) return _openDrawer();
    if (velocity > 300) return _closeDrawer();
    _drawer.value > 0.4 ? _openDrawer() : _closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final favourites = prefs.favourites.map(_find).whereType<AppEntry>().toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (_drawer.value > 0) _closeDrawer();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ---- Home layer ----
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => _dragPages(d.delta.dx),
                onHorizontalDragEnd: (d) => settleDrawer(d.primaryVelocity ?? 0),
                onVerticalDragEnd: _onDownEnd,
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  showSettingsSheet(context, prefs: prefs, apps: _apps);
                },
                child: AnimatedBuilder(
                  animation: _drawer,
                  // Home slides out to the left as the app view comes in.
                  builder: (context, child) => Transform.translate(offset: Offset(-_drawer.value * MediaQuery.sizeOf(context).width, 0), child: child),
                  child: ColoredBox(
                    color: T.scrim,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: T.s24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: T.s48),
                            _Clock(
                              onTapTime: () {
                                final a = _findByName(['clock']);
                                if (a != null) _launch(a);
                              },
                              onTapDate: () {
                                final a = _findByName(['calendar', 'google calendar']);
                                if (a != null) _launch(a);
                              },
                            ),
                            const Spacer(),
                            if (favourites.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(bottom: T.s16),
                                child: Text('Swipe left, then long-press an app\nto pin it here.', style: T.body),
                              )
                            else
                              for (final app in favourites)
                                _FavouriteRow(
                                  app: app,
                                  showIcon: prefs.showHomeIcons,
                                  onTap: () => _launch(app),
                                  onLongPress: () {
                                    HapticFeedback.mediumImpact();
                                    showFavouriteSheet(context, prefs: prefs, app: app);
                                  },
                                ),
                            const SizedBox(height: T.s24),
                            _SwipeHint(onTap: _openDrawer),
                            const SizedBox(height: T.s8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ---- App drawer layer ----
            AnimatedBuilder(
              animation: _drawer,
              builder: (context, child) {
                final v = _drawer.value;
                if (v == 0) return const SizedBox.shrink();
                return Transform.translate(offset: Offset((1 - v) * MediaQuery.sizeOf(context).width, 0), child: child);
              },
              child: AppDrawer(key: _drawerKey, apps: _apps, prefs: prefs, onLaunch: _launch, onDragClose: _dragPages, onDragEnd: settleDrawer),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Pieces ---------------------------------------------------------------

class _Clock extends StatefulWidget {
  const _Clock({required this.onTapTime, required this.onTapDate});
  final VoidCallback onTapTime;
  final VoidCallback onTapDate;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = DateTime.now();
      if (n.minute != _now.minute) setState(() => _now = n);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  Widget build(BuildContext context) {
    final is24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final h = is24 ? _now.hour : (_now.hour % 12 == 0 ? 12 : _now.hour % 12);
    final time = '${is24 ? h.toString().padLeft(2, '0') : h}:${_now.minute.toString().padLeft(2, '0')}';
    final date = '${_days[_now.weekday - 1]}, ${_now.day} ${_months[_now.month - 1]}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: widget.onTapTime,
          child: Text(time, style: T.clock),
        ),
        const SizedBox(height: T.s8),
        GestureDetector(
          onTap: widget.onTapDate,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: T.s4),
            child: Text(date, style: T.date),
          ),
        ),
      ],
    );
  }
}

class _FavouriteRow extends StatelessWidget {
  const _FavouriteRow({required this.app, required this.showIcon, required this.onTap, required this.onLongPress});
  final AppEntry app;
  final bool showIcon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    // Hug the label so empty space beside it still opens settings / swipes.
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIcon) ...[AppIcon(app, size: 32), const SizedBox(width: T.s16)],
              Text(app.label, style: T.favourite),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS-style page dots: home (active) and the app view. Tap to go to the apps.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget dot(bool on) => Container(
      width: on ? 18 : 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: on ? T.ink : T.inkFaint,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
      ),
    );
    return Center(
      child: Semantics(
        button: true,
        label: 'All apps',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 96,
            height: T.tapMin,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [dot(true), dot(false)]),
          ),
        ),
      ),
    );
  }
}
