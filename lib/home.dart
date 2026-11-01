import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_drawer.dart';
import 'apps.dart';
import 'prefs.dart';
import 'quick_actions.dart';
import 'quick_chips.dart';
import 'remote_sheet.dart';
import 'quick_lights.dart';
import 'smart_home.dart';
import 'smart_home_sheet.dart';
import 'tv_remote.dart';
import 'search.dart';
import 'search_dock.dart';
import 'search_history.dart';
import 'widgets.dart';
import 'top/top_carousel.dart';
import 'top/now_page.dart';
import 'ui/theme.dart';
import 'photo_wallpaper.dart';
import 'sheets.dart';
import 'tiles/landing.dart' show todayLanding;
import 'tiles/today_panel.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'ui/perf.dart';

/// The whole launcher is one screen:
/// top half = big clock over the wallpaper + launcher options,
/// bottom half = the app view as a sheet. Swipe the sheet up and the clock
/// scales down and fades away; swipe down to bring it back.
/// Swipe right (or past the first top page) for the today panel on its left — the same widgets
/// as the Tiles today page, in Classic's look (Settings → Home screen → Today panel).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.prefs, required this.theme, this.preview = false});
  final Prefs prefs;
  final OneTheme theme;

  /// A live miniature for the Home screen editor: draws as normal but doesn't take the home
  /// button, app changes or Back from the real home screen.
  final bool preview;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  /// Quick "landing" when the launcher comes into view (back from an app, after unlocking):
  /// a 220 ms settle from 105% to 100% while fading up. Short on purpose — taps work at once.
  late final AnimationController _land = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();
  bool _wasHidden = false;

  /// Sheet height when resting (fraction of the screen).
  /// Where the sheet rests (fraction of the screen). The user picks the split in Settings.
  double get _rest => 1 - prefs.topShare;

  List<AppEntry> _apps = const [];
  final _sheet = DraggableScrollableController();
  final _expanded = ValueNotifier<double>(0); // 0 = resting, 1 = full screen
  final _drawerKey = GlobalKey<AppDrawerState>();
  String _sheetAt = 'rest'; // rest / moving / full — for the snap haptic

  // Search lives in the bottom dock.
  final _query = TextEditingController();
  final _focus = FocusNode();
  bool _searching = false; // dock is a live text field
  bool _showResults = false; // sheet shows results (only once it's full, so the swap can't fight the snap)
  /// Dock shrunk to a circle while the list is scrolled up. A notifier (not setState) so
  /// scrolling only rebuilds the dock, never the screen or the list.
  final _compact = ValueNotifier<bool>(false);

  /// The bottom nav's tab: Home at rest; Remote / Settings while their page is open. On Remote
  /// the whole launcher goes dark (the remote is always dark), back to your theme off it.
  String get _tab => _tabId;
  set _tab(String tab) {
    _tabId = tab;
    widget.theme.forceDark = tab == 'remote';
  }

  String _tabId = 'home';

  /// Search opening on its own (a tap, or carrying on from a pull): 0 → 1. With [_pull] it
  /// drives the recent searches rising in above the bar.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AppDrawerState.awayDuration,
    reverseDuration: AppDrawerState.backDuration,
  );

  /// The recent-search pills (and quick lights): in while nothing is typed, gone the moment
  /// something is, so the results show at once.
  late final AnimationController _pillsIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 420), value: 1);
  void _syncPills() {
    if (_query.text.trim().isEmpty) {
      _filter = SearchFilter.initial; // the next search starts on Apps again
      _pillsIn.forward();
    } else {
      _pillsIn.value = 0;
    }
  }

  /// Which results show once something is typed (the filter pills take the recent pills' place).
  SearchFilter _filter = SearchFilter.initial;
  void _setFilter(SearchFilter f) => setState(() => _filter = f);

  /// How far search has come in (0–1): the pull while pulling, else [_reveal].
  double get _revealed => _searching || _reveal.isAnimating ? _reveal.value : (_pull.value / pullToOpen).clamp(0.0, 1.0);

  /// Remote / Settings pages, shown in the home under the nav (which stays put). More than one
  /// only for a moment: the one leaving while the next comes in.
  final _pages = <_TabPage>[];
  int _pageSeq = 0;
  double _pageFrom = 1; // the side the next page comes in from (1 = right, 0 = rises from the bottom)
  double _homeSide = 0; // where home's own content went while tab pages are up (-1 left, 1 right, 0 stayed)
  static const _navOrder = ['now', 'settings', 'home', 'smart', 'remote', 'search'];
  bool get _pageOpen => _pages.any((p) => !p.leaving);

  /// Pull-to-search: how far the drawer is pulled down past its top (px of finger travel).
  final _pull = ValueNotifier<double>(0);

  /// Lets go of a pull: eases it back to 0 (the list settles as search opens, or snaps back).
  late final AnimationController _pullBack = AnimationController(vsync: this, duration: Motion.snapDuration)
    ..addListener(() => _pull.value = _pullFrom * (1 - Curves.easeOutCubic.transform(_pullBack.value)));
  double _pullFrom = 0;

  /// Released past the line: search is opening — the pill stays "ready" while the list settles.
  final _pullOpening = ValueNotifier<bool>(false);

  /// Search was opened from the resting sheet: closing it glides the sheet back down.
  bool _searchFromRest = false;

  Prefs get prefs => widget.prefs;

  /// Bumped on every setState so the sheet's contents rebuild without rebuilding the sheet.
  final _rev = ValueNotifier<int>(0);

  /// Pinged when the launcher comes back to the front or a permission changes, so the
  /// top pages (screen time, battery, calendar) reload.
  final _refresh = ValueNotifier<int>(0);

  /// The "Just wallpaper" top page is showing: hide the top tint too.
  final _topBlank = ValueNotifier<bool>(false);

  /// Today panel (0) ← home (1). One horizontal pager: it takes horizontal swipes anywhere the
  /// things inside don't (the top carousel and chip rows keep theirs).
  final _panel = PageController(initialPage: 1);
  bool get _sidePanel => prefs.classicToday && !widget.preview;
  bool get _onPanel => _panel.hasClients && (_panel.page ?? 1) < .5;

  /// The top carousel pulled past its first page: the panel follows the finger from there.
  bool _handing = false;

  void _toPanel(int page) {
    if (_panel.hasClients) _panel.animateToPage(page, duration: Motion.snapDuration, curve: Motion.settle);
  }

  void _openToday() {
    if (!_sidePanel) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _toPanel(0);
  }

  /// Hands a swipe right on the top carousel's first page over to the panel (the carousel
  /// can't go further): the panel slides in under the finger and settles open or back.
  bool _onCarouselScroll(ScrollNotification n) {
    if (!_sidePanel || n.metrics.axis != Axis.horizontal || !_panel.hasClients) return false;
    final p = _panel.position;
    if (n is OverscrollNotification && n.dragDetails != null && (n.overscroll < 0 || _handing)) {
      _handing = true;
      p.jumpTo((p.pixels + n.overscroll).clamp(p.minScrollExtent, p.maxScrollExtent));
    } else if (n is ScrollEndNotification && _handing) {
      _handing = false;
      final v = n.dragDetails?.primaryVelocity ?? 0;
      _toPanel((_panel.page ?? 1) < .88 || v > 300 ? 0 : 1);
    }
    return false;
  }

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
        leaving: _searching,
        query: _query.text,
        onLaunch: _launch,
        onCompact: _setCompact,
        onWantFull: _expand,
        onDismissSearch: _dismissSearch,
        searchBar: prefs.searchPosition == 'top' ? _searchBar(inline: true) : null,
        pull: _pull,
        onPull: _onPull,
        onPullEnd: _onPullEnd,
        onWebSearch: _webSearch,
        onRun: _runFromSearch,
        pullOpening: _pullOpening,
        onPickRecent: _setQuery,
        onFillRecent: _setQuery,
        filter: _filter,
        onFilter: _setFilter,
      ),
    ),
  );

  /// The search bar: floating at the bottom, or inline at the top of the drawer.
  Widget _searchBar({required bool inline, bool compact = false}) => SearchDock(
    inline: inline,
    compact: compact,
    active: _searching,
    controller: _query,
    focus: _focus,
    hint: 'Search ${_apps.length} apps',
    onActivate: _startSearch,
    onClose: _stopSearch,
    onSwipeClose: () {
      _stopSearch();
      _collapse(); // swiped away: back home to the clock
    },
    onChanged: _onQuery,
    onSubmitted: _onSubmit,
    onSettings: _settings,
    // The nav's Smart home tab (it took the remote's place; the remote is its first tile).
    onRemote: prefs.remoteButton ? _openSmart : null,
    onRemoteLongPress: () => offerHideRemote(context, prefs: prefs),
    // At the bottom the dock is the nav (Home · Smart home · Search; Settings = long-press Home); in the drawer, just search.
    tab: _tab,
    onHome: inline ? null : _navHome,
    onNow: inline || !_sidePanel ? null : _openNow,
    pull: _pull, // pull-to-search drives the nav → search morph
    pullFull: pullToOpen,
  );

  /// Swiping between the nav's places, in the nav's order: Today ← Home ↔ Smart home ↔ Search.
  /// Settings (long-press Home) counts as Home; the remote as Smart home.
  static const _swipeOrder = ['today', 'home', 'smart', 'search'];
  String get _here => _searching
      ? 'search'
      : !_pageOpen
      ? (_onPanel ? 'today' : 'home')
      : switch (_tab) {
          'remote' || 'smart' => 'smart',
          _ => 'home',
        };

  /// Goes one place along the nav: [step] 1 = the next (finger moved right-to-left), -1 = back.
  void _swipeNav(int step) {
    var i = _swipeOrder.indexOf(_here);
    // From Settings (it sits under Home), back = Home itself.
    if (_pageOpen && _tab == 'settings' && step < 0) {
      HapticFeedback.selectionClick();
      _navHome();
      return;
    }
    while (true) {
      i += step;
      if (i < 0 || i >= _swipeOrder.length) return;
      final to = _swipeOrder[i];
      if (to == 'smart' && !prefs.remoteButton) continue;
      if (to == 'today' && !_sidePanel) return;
      HapticFeedback.selectionClick();
      switch (to) {
        case 'today':
          _openToday();
        case 'home':
          _navHome();
        case 'smart':
          if (_searching) {
            _stopSearch();
            _openTab('smart', _smartPage, from: 1);
          } else {
            _openSmart();
          }
        case 'search':
          _startSearch();
      }
      return;
    }
  }

  /// A tab page following the finger sideways (px); let go past a quarter of the screen (or
  /// flick) and it carries on to the next place, else springs back.
  final _dragX = ValueNotifier<double>(0);
  late final AnimationController _dragBack = AnimationController(vsync: this, duration: Motion.snapDuration)
    ..addListener(() => _dragX.value = _dragFrom * (1 - Curves.easeOutCubic.transform(_dragBack.value)));
  double _dragFrom = 0;

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_pageOpen && !_searching || _held != null) return _pullNext(-d.delta.dx); // home: pull the next page in
    if (_dragBack.isAnimating) _dragBack.stop();
    final next = _dragX.value + d.delta.dx;
    // Nowhere to go that way: it only gives a little.
    final i = _swipeOrder.indexOf(_here);
    final canNext = i + 1 < _swipeOrder.length, canBack = _tab == 'settings' || i > 0;
    _dragX.value = (next < 0 && !canNext) || (next > 0 && !canBack) ? next.sign * math.sqrt(next.abs()) * 3 : next;
  }

  void _onDragEnd(DragEndDetails d) {
    if (_held != null || _pullBy > 0 || !_pageOpen && !_searching) return _letGo(d.primaryVelocity ?? 0);
    final w = MediaQuery.sizeOf(context).width;
    final v = d.primaryVelocity ?? 0, dx = _dragX.value;
    final go = dx.abs() > w * .22 || (v.abs() > 500 && v.sign == dx.sign && dx.abs() > 12);
    if (go && _pageOpen) {
      final step = dx < 0 ? 1 : -1;
      // Carries on from where the finger left it: the page (and home, if it's coming back) are that far along.
      final at = (1 - dx.abs() / w).clamp(0.0, 1.0);
      for (final p in _pages) {
        if (!p.leaving && !p.rise) p.motion.value = at;
      }
      if (_homeFollows) _backdrop.value = at;
      _dragX.value = 0;
      _swipeNav(step);
    } else if (go) {
      _dragX.value = 0;
      _swipeNav(dx < 0 ? 1 : -1);
    } else {
      _dragFrom = dx;
      _dragBack.forward(from: 0);
    }
  }

  /// Home ↔ the next tab as one pager: pulling right-to-left on home brings Smart home in under the
  /// finger (home's content goes off the other way, the backdrop darkens with it); let go to settle.
  bool _holding = false; // the next page presented is held for the finger
  _TabPage? _held;
  double _pullBy = 0; // px pulled so far

  void _pullNext(double by) {
    final w = MediaQuery.sizeOf(context).width;
    _pullBy = (_pullBy + by).clamp(0.0, w);
    if (_held == null && _pullBy > 0) {
      if (!prefs.remoteButton) {
        _pullBy = 0;
        return;
      }
      _holding = true;
      _openTab('smart', _smartPage, from: 1);
      _holding = false;
    }
    final page = _held;
    if (page == null) return;
    page.motion.value = _pullBy / w;
    _backdrop.value = _pullBy / w;
  }

  void _letGo(double velocity) {
    final page = _held, w = MediaQuery.sizeOf(context).width;
    final at = _pullBy / w;
    _pullBy = 0;
    _held = null;
    if (page == null) return;
    setState(() {}); // the pager lets go of the page's swipes
    if (at > .3 || (velocity < -400 && at > .02)) {
      HapticFeedback.selectionClick();
      page.motion.animateTo(1, curve: Curves.easeOutCubic);
      _backdrop.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      _closePages(toward: 1); // back where it came from
    }
  }

  /// The Today pager at home's edge: the finger carries on into Smart home instead of overscrolling.
  double _takeAtEdge(double delta, ScrollMetrics m) {
    if (_searching || !prefs.remoteButton || (_pageOpen && _held == null)) return delta;
    if (delta < 0 && m.pixels >= m.maxScrollExtent - .5) {
      _pullNext(-delta);
      return 0;
    }
    if (delta > 0 && _pullBy > 0) {
      final used = math.min(delta, _pullBy);
      _pullNext(-used);
      return delta - used;
    }
    return delta;
  }

  /// The Today pager has the finger: on home, or while it's pulling Smart home in.
  bool get _homePager => _sidePanel && !_searching && (!_pageOpen || _held != null);

  /// A page dragged back towards home brings home along (it's right there beside it).
  bool get _homeFollows => _pageOpen && _homeSide != 0 && _dragX.value * _homeSide < 0;

  /// How far home has gone under the tab pages (0 home, 1 a page): the backdrop's darkness too.
  double get _homeAway {
    final w = MediaQuery.sizeOf(context).width;
    return (_backdrop.value - (_homeFollows ? _dragX.value.abs() / w : 0)).clamp(0.0, 1.0);
  }

  /// The tab pages' backdrop: it stays put and fades in / out while only their content slides.
  late final AnimationController _backdrop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 340),
  );

  /// Pages scrolling under the nav: it shrinks once one has left its top, and grows back there.
  /// And on the home itself, a swipe right-to-left past its edge opens the next tab (Smart home),
  /// the way a left-to-right one opens the Today panel.
  bool _onPagesScroll(ScrollNotification n) {
    final m = n.metrics;
    if (m.axis == Axis.vertical && n is ScrollUpdateNotification) {
      final away = m.pixels > m.minScrollExtent + 8;
      if (SearchDock.shrunk.value != away) SearchDock.shrunk.value = away;
    }
    if (n.depth == 0 && m.axis == Axis.horizontal) {
      if (n is ScrollEndNotification && (_held != null || _pullBy > 0)) _letGo(n.dragDetails?.primaryVelocity ?? 0);
    }
    return false;
  }

  Future<void> _smartPage() => showSmartHome(context, onRemote: () => _openTab('remote', () => showTvRemote(context, prefs: prefs)));
  void _openSmart() => _openTab('smart', _smartPage);

  void _openRemote() {
    if (prefs.tvHost == null && !prefs.remoteButton) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _openTab('remote', () => showTvRemote(context, prefs: prefs));
  }

  /// The remote in the notification shade while the TV is connected and on (Settings → TV remote).
  void _syncTvNotification() {
    final tv = TvRemote.instance;
    final on = prefs.remoteNotification && prefs.tvHost != null && tv.status.value == TvStatus.connected && tv.power.value != false;
    tv.setNotification(on ? prefs.tvName : null);
  }

  /// A nav tab whose page opens in the home: its tab lights up while open, then Home again.
  /// With the nav at the bottom it's a page under the nav: the page you're on slides out one way
  /// and fades as the new one slides in from the other, by the tabs' order (Home · Search ·
  /// Remote · Settings).
  Future<void> _openTab(String tab, Future<void> Function() open, {double? from, bool rise = false}) async {
    if (_tab == tab && _pageOpen) return;
    final forward = from != null ? from > 0 : _navOrder.indexOf(tab) > _navOrder.indexOf(_tab);
    // Leaving home itself: its content slides off the other way (a rising page just covers it).
    if (!_pageOpen) _homeSide = rise ? 0 : (forward ? -1 : 1);
    setState(() => _tab = tab);
    SearchDock.shrunk.value = false; // a new page starts at its top
    _closePages(toward: forward ? -1 : 1, replaced: true);
    _pageFrom = rise ? 0 : (forward ? 1 : -1);
    if (prefs.searchPosition != 'top') TabPageHost.arm(TabPageHost(present: _presentPage, navRoom: SearchDock.height + DS.s12 * 2, rise: rise));
    await open();
    if (mounted && _tab == tab && !_pageOpen) setState(() => _tab = _onPanel ? 'now' : 'home');
  }

  Future<Object?> _presentPage(Widget Function(VoidCallback close) build) {
    late final _TabPage page;
    page = _TabPage(
      id: ++_pageSeq,
      side: _pageFrom,
      rise: _pageFrom == 0,
      motion: AnimationController(vsync: this, duration: const Duration(milliseconds: 420), reverseDuration: const Duration(milliseconds: 340)),
    );
    page.body = build(() => _closePages(toward: 1)); // closed from inside (back): towards Home
    setState(() => _pages.add(page));
    if (_holding) {
      _held = page; // a finger is pulling it in: [_pullNext] moves it
    } else {
      _backdrop.animateTo(1, curve: Curves.easeOutCubic);
      page.motion.animateTo(1, curve: Curves.easeOutCubic);
    }
    return page.done.future;
  }

  /// [page] leaves, sliding towards [toward] (-1 left, 1 right) as it fades.
  /// [replaced]: another tab's page is coming in (the backdrop stays for it).
  void _dismissPage(_TabPage page, {required double toward, bool replaced = false}) {
    if (page.leaving) return;
    page
      ..leaving = true
      ..side = toward
      ..replaced = replaced;
    if (!page.done.isCompleted) page.done.complete(null);
    if (_held == page) _held = null;
    page.motion.animateBack(0, curve: Curves.easeOutCubic).whenComplete(() {
      page.motion.dispose();
      if (mounted) setState(() => _pages.remove(page));
    });
    if (mounted) setState(() {});
  }

  void _closePages({required double toward, bool replaced = false}) {
    // Leaving the tabs altogether: the backdrop fades as the content slides out. Another tab's
    // page coming in: it stays put under both.
    if (!replaced && _pages.isNotEmpty) _backdrop.animateBack(0, curve: Curves.easeOutCubic);
    for (final p in [..._pages]) {
      _dismissPage(p, toward: toward, replaced: replaced);
    }
  }

  /// The nav's Home: back to the clock (closes search, the list and the today panel).
  void _navHome() {
    SearchDock.shrunk.value = false;
    _closePages(toward: 1); // Home is the first tab: the page goes off to the right
    _stopSearch();
    _drawerKey.currentState?.reset();
    _collapse();
    _toPanel(1);
    if (_tab != 'home') setState(() => _tab = 'home');
  }

  /// The nav's Now (left of Home): the Today panel.
  void _openNow() {
    HapticFeedback.selectionClick();
    SearchDock.shrunk.value = false;
    _closePages(toward: 1); // Now is left of every page: they go off to the right
    _stopSearch();
    _drawerKey.currentState?.reset();
    _collapse();
    _toPanel(0);
    if (_tab != 'now') setState(() => _tab = 'now');
  }

  /// Home ⇄ Now follows the Today pager (swiping it lights the right tab).
  void _syncNowTab() {
    if (_pageOpen || _searching || (_tab != 'home' && _tab != 'now')) return;
    final want = _onPanel ? 'now' : 'home';
    if (_tab != want) setState(() => _tab = want);
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(_syncPills);
    _panel.addListener(_syncNowTab);
    prefs.addListener(_rebuild);
    if (!widget.preview) {
      openToday.addListener(_openToday);
      WidgetsBinding.instance.addObserver(this);
      Apps.instance.onAppsChanged = _loadApps;
      Apps.instance.onHomePressed = _goHome;
      // The Quick Settings tile / remote notification: straight into the TV remote.
      Apps.instance.onOpenRemote = _openRemote;
      Apps.instance.takeOpenRemote().then((open) {
        if (open && mounted) _openRemote();
      });
      TvRemote.instance.status.addListener(_syncTvNotification);
      TvRemote.instance.power.addListener(_syncTvNotification);
      Apps.instance.onPermissionsChanged = () => _refresh.value++;
    }
    _sheet.addListener(() {
      _expanded.value = ((_sheet.size - _rest) / (1 - _rest)).clamp(0.0, 1.0);
      // A tick when the sheet snaps home: full screen, or back to rest.
      final at = _sheet.size >= .999 ? 'full' : (_sheet.size <= _rest + .002 ? 'rest' : 'moving');
      if (at != _sheetAt) {
        if (at != 'moving' && _sheetAt == 'moving') HapticFeedback.lightImpact();
        _sheetAt = at;
      }
    });
    _loadApps();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstLaunch());
  }

  /// Once: put a "Scan QR" app shortcut first among the quick chips (Paytm preferred, else any
  /// payments/scanner app's). Retries until app shortcuts are available (default home app).
  Future<void> _seedScanChip() async {
    if (prefs.qrSeeded) return;
    final all = await Apps.instance.shortcuts();
    if (all == null) return;
    bool scan(AppShortcut s) => s.label.toLowerCase().contains('scan');
    final pick =
        all.where((s) => scan(s) && s.package.contains('paytm')).firstOrNull ??
        all.where((s) => scan(s) && (s.label.toLowerCase().contains('qr') || s.label.toLowerCase().contains('pay'))).firstOrNull;
    if (pick != null) await prefs.addQuickChip(pick.id, label: pick.label, app: pick.app, first: true);
    await prefs.setQrSeeded();
  }

  /// Once per install: offer to restore a backup, or say Android already restored one.
  /// Also drops widget pages that don't exist on this phone (restored from elsewhere).
  Future<void> _firstLaunch() async {
    final ids = await Apps.instance.boundWidgetIds();
    if (ids != null) await prefs.pruneWidgetPages(ids.toSet());
    Apps.instance.refreshTorch();
    await _seedScanChip();
    if (!await Apps.instance.isFirstRun() || !mounted) return;
    final fresh = prefs.isFresh;
    final restoredByAndroid = !fresh && prefs.installId != null;
    final upgradedFromOld = !fresh && prefs.installId == null; // older version, no prompt
    await prefs.setInstallId();
    if (upgradedFromOld || !mounted) return;
    await showWelcomeRestore(context, prefs: prefs, restoredByAndroid: restoredByAndroid);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    prefs.removeListener(_rebuild);
    TvRemote.instance.status.removeListener(_syncTvNotification);
    TvRemote.instance.power.removeListener(_syncTvNotification);
    openToday.removeListener(_openToday);
    _panel.removeListener(_syncNowTab);
    _panel.dispose();
    _sheet.dispose();
    _land.dispose();
    _pullBack.dispose();
    _reveal.dispose();
    _query.removeListener(_syncPills);
    _pillsIn.dispose();
    _backdrop.dispose();
    _dragBack.dispose();
    _dragX.dispose();
    _pull.dispose();
    _pullOpening.dispose();
    _query.dispose();
    _focus.dispose();
    _expanded.dispose();
    _rev.dispose();
    _compact.dispose();
    _refresh.dispose();
    _topBlank.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) _wasHidden = true;
    if (state == AppLifecycleState.resumed && _wasHidden) {
      _wasHidden = false;
      _land.forward(from: 0);
      if (_onPanel) todayLanding.play(); // back on the panel: its widgets come in again
    }
    if (state == AppLifecycleState.resumed) {
      _loadApps();
      _refresh.value++;
      widget.theme.refreshSystem(); // wallpaper (and so Material You colours) may have changed
      _seedScanChip(); // app shortcuts become available once we're the default home app
    }
  }

  void _rebuild() {
    _syncTvNotification(); // Settings → TV remote → In notifications may have changed
    // Panel switched off while it shows: back home.
    if (!_sidePanel && _panel.hasClients && (_panel.page ?? 1) != 1) _panel.jumpToPage(1);
    setState(() {});
  }

  Future<void> _loadApps() async {
    final apps = await Apps.instance.list();
    if (mounted) setState(() => _apps = apps);
  }

  // ---- Sheet ---------------------------------------------------------------

  void _expand() {
    if (_sheet.isAttached) _sheet.animateTo(1, duration: Motion.snapDuration, curve: Motion.settle);
  }

  void _collapse({bool instant = false, Duration duration = Motion.snapDuration}) {
    if (!_sheet.isAttached) return;
    instant ? _sheet.jumpTo(_rest) : _sheet.animateTo(_rest, duration: duration, curve: Motion.settle);
  }

  // ---- Search --------------------------------------------------------------

  Future<void> _startSearch() async {
    HapticFeedback.selectionClick();
    // Search sits right of Smart home / Remote and left of Settings.
    _closePages(toward: _navOrder.indexOf(_tab) < _navOrder.indexOf('search') ? -1 : 1);
    SearchDock.shrunk.value = false;
    SmartHome.instance.refresh(); // its quick lights, above the recent searches
    _reveal.value = math.max(_reveal.value, (_pull.value / pullToOpen).clamp(0.0, 1.0)); // a pull: on from where it got to
    _reveal.forward();
    _compact.value = false;
    _searchFromRest = _expanded.value < .5;
    setState(() => _searching = true);
    _focus.requestFocus();
    if (prefs.searchPosition == 'top') _drawerKey.currentState?.toTop(); // the bar is at the top of the list
    // Results once the sheet is up and the cards have slid off the sides. Not by awaiting the
    // rise alone: the keyboard arriving resizes the sheet and can cut that animation short, whose
    // future then never completes — the results (recent searches) never showed.
    // A full pull has already slid them out under the finger: then only the rise is left.
    final left = 1 - (_pull.value / pullToOpen).clamp(0.0, 1.0);
    final cleared = Future<void>.delayed(AppDrawerState.awayDuration * left + const Duration(milliseconds: 40));
    const rise = Duration(milliseconds: 368); // the sheet going full screen (a little quicker than a snap)
    if (_sheet.isAttached) {
      await Future.any([_sheet.animateTo(1, duration: rise, curve: Motion.settle), Future<void>.delayed(rise + const Duration(milliseconds: 60))]);
    }
    await cleared;
    if (mounted && _searching) setState(() => _showResults = true);
  }

  void _stopSearch() {
    _reveal.reverse();
    _focus.unfocus();
    _query.clear();
    _compact.value = false;
    if (_searching || _showResults) {
      setState(() {
        _searching = false;
        _showResults = false;
      });
      // The way back: opened from the resting sheet (tap or pull) → glide back down to it.
      if (_searchFromRest) _collapse(duration: AppDrawerState.backDuration);
    }
    _searchFromRest = false;
  }

  // ---- Pull-to-search ------------------------------------------------------

  /// Drawer pulled down past its top. Counts only while the sheet rests (pulling a full-screen
  /// sheet down shrinks it first) and the gesture is on (Settings → Pull down to search).
  void _onPull(double delta) {
    // Taking a pull back always counts (moving up mid-pull also grows the sheet a little).
    if (!prefs.pullToSearch || _searching || (_expanded.value > .01 && delta > 0)) return;
    _pullBack.stop(); // a stopped spring-back never completes, so clear its flag here
    _pullOpening.value = false;
    final before = _pull.value;
    _pull.value = math.max(0, before + delta);
    if ((before < pullToOpen) != (_pull.value < pullToOpen)) HapticFeedback.selectionClick(); // crossed the line
  }

  void _onPullEnd() {
    // Once per release: opening search ends scrolls of its own, which report back here.
    if (_pull.value <= 0 || _pullBack.isAnimating) return;
    final open = _pull.value >= pullToOpen;
    _pullFrom = _pull.value;
    _pullOpening.value = open;
    _pullBack.forward(from: 0).whenComplete(() => _pullOpening.value = false);
    if (open) _startSearch();
  }

  /// A recent search: typed into the bar (cursor at the end), its results show. Never opens the
  /// only match by itself — tapping a recent search means "show me these results".
  void _setQuery(String q) {
    _query.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    _focus.requestFocus();
    setState(() {});
  }

  /// A search result's action (app shortcut, settings page): run it, then tidy up.
  Future<void> _runFromSearch(Future<void> Function() action) async {
    prefs.addSearch(_query.text); // used: into search history
    await action();
    Future.delayed(const Duration(milliseconds: 350), _stopSearch);
  }

  /// Search the web (or the Play Store) for what's typed, then tidy up like after an app launch.
  Future<void> _webSearch(String q, {bool play = false}) async {
    prefs.addSearch(q);
    play ? await Apps.instance.playSearch(q) : await Apps.instance.webSearch(q);
    Future.delayed(const Duration(milliseconds: 350), _stopSearch);
  }

  void _onQuery(String q) {
    setState(() {});
    if (!prefs.searchIn.contains('apps')) return;
    final r = searchApps(_apps, q);
    if (prefs.autoOpenSingleMatch && q.trim().isNotEmpty && r.length == 1) _launch(r.first);
  }

  /// Enter on the keyboard: the top app, or — when no app matches — the web (or Play Store),
  /// whichever search is set to look in.
  void _onSubmit(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    prefs.addSearch(q);
    final sources = prefs.searchIn;
    final r = sources.contains('apps') ? searchApps(_apps, q) : const <AppEntry>[];
    if (r.isNotEmpty) {
      _launch(r.first);
    } else if (sources.contains('google')) {
      _webSearch(q);
    } else if (sources.contains('play')) {
      _webSearch(q, play: true);
    }
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
    if (!_searching) _compact.value = v;
  }

  /// Home button while already home: close everything.
  void _goHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _stopSearch();
    _drawerKey.currentState?.reset();
    _collapse();
    _toPanel(1); // from the today panel too
  }

  Future<void> _launch(AppEntry app) async {
    if (_searching) prefs.addSearch(_query.text); // opened from search: it was used
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
    _openTab('settings', () => showSettingsSheet(context, prefs: prefs, apps: _apps, theme: widget.theme), rise: true);
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.preview,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_pageOpen) return; // a Remote / Settings page handles Back itself
        // On the today panel: Back ends its editing first (the panel does that), then home.
        if (_onPanel) {
          if (!todayEditing.value) _toPanel(1);
          return;
        }
        if (_searching) return _stopSearch();
        if (_expanded.value > 0) _collapse();
      },
      // Status bar icons: dark over a light page or a light sheet at full screen, else white
      // (over the wallpaper and dark surfaces).
      child: ValueListenableBuilder<double>(
        valueListenable: _expanded,
        builder: (context, e, child) {
          final lightPage = _pageOpen && DS.card.computeLuminance() > .5;
          final lightSheet = DS.sheet.computeLuminance() > .5;
          final light = lightPage || (e > .9 && lightSheet);
          final lightBottom = lightPage || lightSheet; // the sheet always reaches the bottom edge
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
              statusBarBrightness: light ? Brightness.light : Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: lightBottom ? Brightness.dark : Brightness.light,
            ),
            child: child!,
          );
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: AnimatedBuilder(
            animation: _land,
            builder: (context, child) {
              // Always the same wrappers (at 100% when idle): swapping the tree would rebuild the
              // sheet and reattach its controller.
              final t = Perf.lite.value ? 1.0 : Curves.easeOutCubic.transform(_land.value); // lighter effects: no landing
              // A dark veil that clears, not a fade of the whole screen: fading everything is an
              // offscreen layer the size of the screen, too heavy for slower phones right at the
              // moment they're busiest (coming back home).
              return Stack(
                fit: StackFit.expand,
                children: [
                  Transform.scale(scale: 1.04 - .04 * t, child: child),
                  if (t < 1)
                    IgnorePointer(
                      child: ColoredBox(color: Colors.black.withValues(alpha: .45 * (1 - t))),
                    ),
                ],
              );
            },
            child: LayoutBuilder(
              builder: (context, c) {
                final topHeight = c.maxHeight * (1 - _rest) + DS.rSheet;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // ---- Own photo instead of the phone wallpaper (Settings → Wallpaper). ----
                    IgnorePointer(child: PhotoWallpaper(prefs: prefs)),
                    // ---- Wallpaper dim (Settings → Wallpaper dim): black over the wallpaper so
                    // everything on it reads better; off on the "Just wallpaper" page. ----
                    IgnorePointer(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _topBlank,
                        builder: (context, blank, _) => AnimatedContainer(
                          duration: Motion.snapDuration,
                          curve: Motion.settle,
                          color: Colors.black.withValues(alpha: blank ? 0 : prefs.wallpaperDim),
                        ),
                      ),
                    ),

                    // ---- The Today panel's backdrop: still, fading in as the panel slides over (its look's
                    // plain / black, else a dim that lets the wallpaper through). ----
                    if (_sidePanel)
                      IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _panel,
                          builder: (context, _) {
                            final page = _panel.hasClients && _panel.position.haveDimensions ? _panel.page ?? 1 : 1.0;
                            final t = Curves.easeOut.transform((1 - page).clamp(0.0, 1.0));
                            if (t == 0) return const SizedBox.shrink();
                            final c = todayBackdrop(prefs);
                            return ColoredBox(color: c.a > 0 ? c.withValues(alpha: c.a * t) : Colors.black.withValues(alpha: .3 * t));
                          },
                        ),
                      ),

                    // ---- Today panel ← home: one pager over the wallpaper (it stays put). No
                    // stretch on the pager itself; the pages keep their own. ----
                    ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onPagesScroll,
                        // Swipes between the nav's places wherever the pager doesn't take them: on a tab
                        // page (it follows the finger), in search, and on home without a Today panel.
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragUpdate: _homePager ? null : _onDragUpdate,
                          onHorizontalDragEnd: _homePager ? null : _onDragEnd,
                          child: PageView(
                        controller: _panel,
                        physics: _homePager
                            ? _HomePagerPhysics(take: _takeAtEdge, holding: () => _held != null || _pullBy > 0)
                            : const NeverScrollableScrollPhysics(), // a tab page / search: swipes go along the nav
                        onPageChanged: (i) {
                          if (i == 0) {
                            HapticFeedback.selectionClick();
                            todayLanding.play();
                          }
                        },
                        children: [
                          ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context),
                            child: _sidePanel
                                ? Builder(
                                    builder: (context) {
                                      // The nav floats over the panel too: its last card scrolls clear of it.
                                      final mq = MediaQuery.of(context);
                                      final nav = prefs.searchPosition != 'top' ? SearchDock.height + DS.s12 * 2 : 0.0;
                                      return MediaQuery(
                                        data: mq.copyWith(padding: mq.padding.copyWith(bottom: mq.padding.bottom + nav)),
                                        child: TodayPanel(prefs: prefs, apps: _apps, onLaunch: _launch, backdrop: false),
                                      );
                                    },
                                  )
                                : const SizedBox.shrink(),
                          ),
                          _KeepAlive(
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // ---- Home's own content: slides off the other way (and dims) while a tab page is up,
                                  // so going to Smart home is a move, not an overlay. A rising page (Settings) just covers it.
                                  Positioned.fill(
                                    child: AnimatedBuilder(
                                      animation: Listenable.merge([_backdrop, _dragX]),
                                      builder: (context, child) {
                                        // Same shape every frame (no state lost); at rest it's a no-op.
                                        final t = _homeSide == 0 ? 0.0 : _homeAway;
                                        return IgnorePointer(
                                          ignoring: t > 0 && _pageOpen,
                                          child: Transform.translate(offset: Offset(_homeSide * MediaQuery.sizeOf(context).width * t, 0), child: child),
                                        );
                                      },
                                      child: Stack(
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
                                              // Lighter effects: no fade (an offscreen layer every frame) — the sheet covers it.
                                              opacity: Perf.lite.value ? (e > .95 ? 0 : 1) : (1 - e * 1.6).clamp(0.0, 1.0),
                                              child: Transform.translate(
                                                offset: Offset(0, -topHeight * 0.18 * e),
                                                child: Transform.scale(scale: 1 - 0.3 * e, alignment: Alignment.topCenter, child: child),
                                              ),
                                            ),
                                          ),
                                          child: RepaintBoundary(
                                            // Cached as a layer: fading/scaling it while the sheet moves just re-composites it.
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                // Page 0 (Now) hides the wallpaper edge to edge.
                                                IgnorePointer(child: NowStage(prefs: prefs)),
                                                _TopArea(
                                                  chipsHeight: QuickChipsRow.heightOf(prefs),
                                                  carousel: NotificationListener<ScrollNotification>(
                                                    onNotification: _onCarouselScroll, // past its first page → the today panel
                                                    child: TopCarousel(
                                                      prefs: prefs,
                                                      refresh: _refresh,
                                                      onTapClock: () => _openNamed(['clock']),
                                                      onTapDate: () => _openNamed(['calendar', 'google calendar']),
                                                      onBlank: (b) => _topBlank.value = b,
                                                    ),
                                                  ),
                                                  blank: _topBlank,
                                                  onCustomise: () {
                                                    HapticFeedback.mediumImpact();
                                                    showCustomiseTop(context, prefs: prefs);
                                                  },
                                                  padding: prefs.topPadding,
                                                  onSwipeUp: _expand,
                                                  onSwipeDown: Apps.instance.openNotifications,
                                                ),
                                              ],
                                            ),
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

                                      // ---- Quick action chips: on the wallpaper, just above the sheet's top edge. ----
                                      // They ride along with the sheet and fade out as it expands.
                                      ValueListenableBuilder<double>(
                                        valueListenable: _expanded,
                                        builder: (context, e, child) {
                                          final sheetTop = c.maxHeight * (1 - (_rest + e * (1 - _rest)));
                                          return Positioned(
                                            left: 0,
                                            right: 0,
                                            top: sheetTop - QuickChipsRow.heightOf(prefs) - QuickChipsRow.gap,
                                            height: QuickChipsRow.heightOf(prefs),
                                            child: IgnorePointer(
                                              ignoring: e > .2,
                                              child: Opacity(opacity: (1 - e * 3).clamp(0.0, 1.0), child: child),
                                            ),
                                          );
                                        },
                                        // Not on the Now page: the player takes their room ([_TopArea]).
                                        child: ValueListenableBuilder<double>(
                                          valueListenable: nowAway,
                                          builder: (context, a, child) => IgnorePointer(
                                            ignoring: a < .5,
                                            child: Opacity(opacity: a.clamp(0.0, 1.0), child: child),
                                          ),
                                          child: RepaintBoundary(child: QuickChipsRow(prefs: prefs)),
                                        ),
                                      ),

                                      // ---- Fade under the dock, so it reads as floating above the cards. ----
                                      if (prefs.searchPosition != 'top')
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          height: SearchDock.height + MediaQuery.paddingOf(context).bottom + DS.s48,
                                          child: IgnorePointer(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                // Sheet colour (follows the theme), fading in under the dock.
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [DS.sheet.withValues(alpha: 0), DS.sheet.withValues(alpha: .9)],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                      // ---- Recent searches: pills just above the bar, popping in one after another as
                                      // search opens (with the pull, or on their own after a tap); typing or closing
                                      // search takes them back out. ----
                                      // Quick lights sit just above them (when Google Home has lights).
                                      if (prefs.searchPosition != 'top')
                                        AnimatedBuilder(
                                          animation: Listenable.merge([_reveal, _pull, _pillsIn, SmartHome.instance.state]),
                                          builder: (context, _) {
                                            final t = _revealed * _pillsIn.value;
                                            final lights = SmartHome.instance.state.value.lights.isNotEmpty;
                                            final pills = RecentSearches.shows(prefs);
                                            if (t == 0 || !(lights || pills)) return const SizedBox.shrink();
                                            final mq = MediaQuery.of(context);
                                            return Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: math.max(mq.viewInsets.bottom, mq.padding.bottom) + DS.s12 + SearchDock.height + DS.s12,
                                              child: IgnorePointer(
                                                ignoring: !_searching || t < 1,
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                                  children: [
                                                    if (lights)
                                                      Opacity(
                                                        opacity: Curves.easeOut.transform(t),
                                                        child: Transform.translate(
                                                          offset: Offset(0, 16 * (1 - t)),
                                                          child: Padding(
                                                            padding: EdgeInsets.fromLTRB(DS.s16, 0, DS.s16, pills ? DS.s12 : 0),
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(vertical: DS.s8),
                                                              decoration: ShapeDecoration(
                                                                color: DS.card,
                                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: DS.hairline)),
                                                              ),
                                                              child: QuickLights(ink: DS.ink, soft: DS.inkMuted, full: false, onOpen: () {
                                                                _stopSearch();
                                                                _openSmart();
                                                              }),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    if (pills) RecentSearchPills(prefs: prefs, progress: t, onPick: _setQuery),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                      // ---- Filter pills: once something is typed they take the recent pills' place
                                      // (single-select; Apps each time a new search starts). With the bar at the top
                                      // the drawer draws them under it. ----
                                      if (prefs.searchPosition != 'top' && _searching && _query.text.trim().isNotEmpty)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: math.max(MediaQuery.viewInsetsOf(context).bottom, MediaQuery.paddingOf(context).bottom) + DS.s12 + SearchDock.height + DS.s12,
                                          child: SearchFilterPills(
                                            selected: _filter,
                                            onSelect: _setFilter,
                                            google: _apps.any((a) => a.package == 'com.google.android.googlequicksearchbox'),
                                          ),
                                        ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // ---- Remote / Settings: pages under the nav. ----
                                  // Their backdrop stays put and fades; only the content slides.
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: AnimatedBuilder(
                                        animation: Listenable.merge([_backdrop, _dragX]),
                                        builder: (context, child) => Opacity(opacity: _homeAway, child: child),
                                        child: ColoredBox(color: DS.base),
                                      ),
                                    ),
                                  ),
                                  for (final p in _pages)
                                    Positioned.fill(
                                      key: ValueKey(p.id),
                                      child: IgnorePointer(
                                        ignoring: p.leaving,
                                        child: _TabPageMotion(page: p, drag: _dragX),
                                      ),
                                    ),

                                ],
                              ),
                            ),
                          ),
                        ],
                      ))),
                    ),

                    // ---- Search dock (iOS style), floating at the bottom (unless it's in the drawer). Above the
                    // pager, so it stays on the Today panel too. ----
                    if (prefs.searchPosition != 'top')
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: RepaintBoundary(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _compact,
                            builder: (context, compact, _) => _searchBar(inline: false, compact: compact),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Nav tab pages ----------------------------------------------------------

class _TabPage {
  _TabPage({required this.id, required this.side, required this.motion, this.rise = false});
  final bool rise; // comes up from the bottom and goes back down (Settings)
  final int id;
  final AnimationController motion; // 0 → 1 coming in; back to 0 leaving
  double side; // where it slides from (coming in) or to (leaving): -1 left, 1 right
  bool leaving = false;
  bool replaced = false; // leaving for the next tab's page
  late final Widget body;
  final done = Completer<Object?>();
}

/// A tab page's content coming in or leaving: it slides from (or to) its side while it
/// dissolves, and follows the finger ([drag]) while swiped. Its backdrop is drawn apart, still.
class _TabPageMotion extends StatelessWidget {
  const _TabPageMotion({required this.page, required this.drag});
  final _TabPage page;
  final ValueListenable<double> drag;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    return AnimatedBuilder(
      animation: Listenable.merge([page.motion, drag]),
      child: RepaintBoundary(child: page.body),
      builder: (context, child) {
        final t = page.motion.value; // a position: the controller eases, or a finger sets it
        if (page.rise) {
          // Up from the bottom like a sheet, back down when it closes.
          return Transform.translate(offset: Offset(0, size.height * (1 - t)), child: child);
        }
        // Pager-like: a full width beside home / the next page, sliding with it.
        final dx = page.leaving ? 0.0 : drag.value;
        return Transform.translate(offset: Offset(dx + page.side * w * (1 - t), 0), child: child);
      },
    );
  }
}

// ---- Top area ---------------------------------------------------------------

class _TopArea extends StatelessWidget {
  const _TopArea({
    required this.chipsHeight,
    required this.carousel,
    required this.blank,
    required this.padding,
    required this.onSwipeUp,
    required this.onSwipeDown,
    required this.onCustomise,
  });

  final double chipsHeight; // the quick chips row, which grows with Chip look → Size
  final Widget carousel;
  final ValueListenable<bool> blank;
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
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: AnimatedPadding(
              duration: Motion.snapDuration,
              curve: Motion.settle,
              padding: EdgeInsets.fromLTRB(
                DS.s8 + padding,
                DS.s4 + padding * .5,
                DS.s8 + padding,
                // room for the sheet's rounded top + the quick chips row above it (below)
                DS.rSheet + DS.s4 + padding * .5,
              ),
              // The chips hide on the Now page, so it grows into their room as you swipe to it.
              child: ValueListenableBuilder<double>(
                valueListenable: nowAway,
                builder: (context, a, child) => Padding(
                  padding: EdgeInsets.only(bottom: (chipsHeight + QuickChipsRow.gap) * a.clamp(0.0, 1.0)),
                  child: child,
                ),
                child: carousel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the home page (its sheet, scroll positions, search) alive while the today panel shows.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// The Today pager's physics, letting home take the finger past its last page ([take]: the part of
/// a drag it uses goes to the Smart home pull) and not flinging back while it [holding] one.
class _HomePagerPhysics extends PageScrollPhysics {
  const _HomePagerPhysics({super.parent, required this.take, required this.holding});
  final double Function(double delta, ScrollMetrics m) take;
  final bool Function() holding;

  @override
  _HomePagerPhysics applyTo(ScrollPhysics? ancestor) => _HomePagerPhysics(parent: buildParent(ancestor), take: take, holding: holding);

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) => super.applyPhysicsToUserOffset(position, take(offset, position));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) =>
      super.createBallisticSimulation(position, holding() ? 0 : velocity);
}
