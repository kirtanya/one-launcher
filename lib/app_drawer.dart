import 'package:flutter/foundation.dart';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'folders.dart';
import 'one_stream_widgets.dart';
import 'prefs.dart';
import 'ui/perf.dart';
import 'ui/glass.dart';
import 'search.dart';
import 'search_dock.dart';
import 'search_history.dart';
import 'system_settings.dart';
import 'quick_chips.dart';
import 'quick_actions.dart';
import 'sheets.dart';
import 'ui/components.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'widgets.dart';

/// The bottom sheet of the one-screen launcher: pastel hero card, then "Most used",
/// then one card per folder of similar apps. Only one folder is open at a time.
/// While searching it shows results instead (search lives in the bottom dock, or at the top of
/// this list — Settings → Search bar).
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.apps,
    required this.prefs,
    required this.scroll,
    required this.expanded,
    required this.searching,
    required this.query,
    required this.onLaunch,
    required this.onCompact,
    required this.onWantFull,
    required this.onDismissSearch,
    this.searchBar,
    required this.pull,
    required this.onPull,
    required this.onPullEnd,
    required this.onWebSearch,
    required this.onRun,
    required this.pullOpening,
    required this.onPickRecent,
    required this.onFillRecent,
  });

  /// Recent searches (shown while search is open and empty): tap → typed in and searched;
  /// the row's arrow → just filled in.
  final ValueChanged<String> onPickRecent, onFillRecent;

  /// The search bar when it lives inside the drawer (Settings → Search bar: Top); null when it
  /// floats at the bottom of the screen.
  final Widget? searchBar;

  /// Pull-to-search: how far (px) the user has pulled the drawer down past its top, and the
  /// callbacks that feed it. The home screen decides whether a pull counts.
  final ValueListenable<double> pull;
  final ValueChanged<double> onPull;
  final VoidCallback onPullEnd;

  /// Search results' web rows: search Google (or the Play Store) for the query.
  final void Function(String query, {bool play}) onWebSearch;

  /// Runs a search result's action (an app shortcut, a settings page), then search closes.
  final void Function(Future<void> Function() action) onRun;

  /// A pull went past the line and was let go: search is opening (the pill stays "ready").
  final ValueListenable<bool> pullOpening;

  final List<AppEntry> apps;
  final Prefs prefs;
  final ScrollController scroll;
  final ValueListenable<double> expanded; // 0 = half screen, 1 = full screen
  final bool searching;
  final String query;
  final ValueChanged<AppEntry> onLaunch;
  final ValueChanged<bool> onCompact; // list scrolled up (true) or back down (false)
  final VoidCallback onWantFull; // expand the sheet to full screen
  final VoidCallback onDismissSearch; // user pulled down while searching

  @override
  State<AppDrawer> createState() => AppDrawerState();
}

class AppDrawerState extends State<AppDrawer> with SingleTickerProviderStateMixin {
  static const _mostUsedCount = 16; // green card: 2 pages × 8
  String? _openId; // the one open folder (Most used is the hero card, always open)

  /// Scroll the list to its very top (where the in-list search bar sits).
  void toTop() {
    if (widget.scroll.hasClients) widget.scroll.jumpTo(0);
  }

  /// Back to the resting state (Home pressed / after launching an app).
  void reset() {
    _shortcuts = null; // re-read app shortcuts next search (apps may have changed)
    if (_openId != null) setState(() => _openId = null);
  }

  /// App shortcuts for search, loaded once per search session.
  List<AppShortcut>? _shortcuts;
  bool _loadingShortcuts = false;
  void _loadShortcuts() {
    if (_shortcuts != null || _loadingShortcuts) return;
    _loadingShortcuts = true;
    Apps.instance.shortcuts().then((list) {
      _loadingShortcuts = false;
      if (mounted) setState(() => _shortcuts = list ?? const []);
    });
  }

  // ---- Data ----------------------------------------------------------------

  // Folders, visible apps and the green card's apps only change when the app list or a
  // setting changes — not on every rebuild (search typing, scroll, theme…).
  List<AppEntry>? _derivedFor;
  int _derivedVersion = -1;
  late (List<AppEntry>, List<(Folder, List<AppEntry>)>, List<AppEntry>) _derivedCache;

  (List<AppEntry>, List<(Folder, List<AppEntry>)>, List<AppEntry>) _derived() {
    final prefs = widget.prefs;
    if (!identical(_derivedFor, widget.apps) || _derivedVersion != prefs.version) {
      final apps = _visible;
      _derivedCache = (apps, groupApps(apps, prefs.folderOverrides, order: prefs.folderOrder), _pinnedAndMostUsed(apps));
      _derivedFor = widget.apps;
      _derivedVersion = prefs.version;
    }
    return _derivedCache;
  }

  List<AppEntry> get _visible {
    final hidden = widget.prefs.hidden.toSet();
    return widget.apps.where((a) => !hidden.contains(a.package)).toList();
  }

  List<AppEntry> _pinned(List<AppEntry> apps) {
    final byPkg = {for (final a in apps) a.package: a};
    return [for (final p in widget.prefs.favourites) ?byPkg[p]];
  }

  /// Pinned apps first (in pin order), then the most-opened ones, up to 8.
  List<AppEntry> _pinnedAndMostUsed(List<AppEntry> apps) {
    final byPkg = {for (final a in apps) a.package: a};
    final list = _pinned(apps);
    final used = widget.prefs.launchCounts.entries.where((e) => byPkg.containsKey(e.key)).toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in used) {
      if (list.length >= _mostUsedCount) break;
      if (!list.contains(byPkg[e.key])) list.add(byPkg[e.key]!);
    }
    return list;
  }

  // ---- Actions -------------------------------------------------------------

  void _longPress(AppEntry app) {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    showAppSheet(context, prefs: widget.prefs, app: app);
  }

  // Each folder has a zero-height marker just above it (to find where it starts) and a key on
  // its app grid (to know how tall it currently is).
  final _markerKeys = <String, GlobalKey>{};
  final _bodyKeys = <String, GlobalKey>{};
  GlobalKey _marker(String id) => _markerKeys.putIfAbsent(id, GlobalKey.new);
  GlobalKey _body(String id) => _bodyKeys.putIfAbsent(id, GlobalKey.new);
  final _headerKeys = <String, GlobalKey>{};
  GlobalKey _header(String id) => _headerKeys.putIfAbsent(id, GlobalKey.new); // keeps header state when it starts/stops pinning

  /// Room the floating search dock takes at the bottom (none when the bar is in the list).
  double get _dockRoom => widget.searchBar == null ? SearchDock.height : 0;

  /// Height of a folder's header row (pill 64 + padding 12 × 2).
  static const _headerExtent = 88.0;

  /// An open folder never fills the screen: a slice of the card above and the folder below
  /// always stays visible (once it's centred). Longer folders scroll their grid inside.
  static const _peek = 56.0;

  double _maxBodyHeight(Size size, EdgeInsets padding) {
    final visible = size.height - (DS.gutter + padding.top) - (padding.bottom + _dockRoom + DS.s24);
    return math.max(160, visible - 2 * (_peek + DS.stack) - _headerExtent);
  }

  /// True while a folder's grid is handing its leftover drag to the main list, so the search
  /// bar treats that movement as the user's own scrolling.
  bool _handoff = false;

  /// Drives the "open folder → centre it" glide, in step with the folder growing.
  late final AnimationController _glide = AnimationController(vsync: this, duration: Motion.snapDuration)..addListener(_glideTick);
  String? _glideId;
  double _glideFrom = 0;

  @override
  void initState() {
    super.initState();
    widget.expanded.addListener(_trackFull);
    _trackFull();
  }

  @override
  void dispose() {
    widget.expanded.removeListener(_trackFull);
    _glide.dispose();
    super.dispose();
  }

  /// Accordion: opening one folder closes the other. The sheet expands, the folder opens and
  /// it glides to the middle — all in one motion. A folder taller than the screen stops with
  /// its header at the top instead.
  void _toggle(String id) {
    HapticFeedback.selectionClick();
    final opening = _openId != id;
    setState(() => _openId = opening ? id : null);
    // A second, firmer tick when the folder settles open / shut.
    Future.delayed(Motion.snapDuration, () {
      if (mounted && (_openId == id) == opening) HapticFeedback.lightImpact();
    });
    if (!opening || !widget.scroll.hasClients) return;
    // An open folder gets the room: the search bar shrinks to its circle until the user
    // scrolls the list themselves.
    widget.onCompact(true);
    widget.onWantFull();
    _glideId = id;
    _glideFrom = widget.scroll.position.pixels;
    _glide.forward(from: 0);
  }

  /// Where the list should be scrolled to frame folder [id], measured on the current layout.
  double? _targetFor(String id) {
    final marker = _markerKeys[id]?.currentContext?.findRenderObject();
    final body = _bodyKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (marker == null || body == null || !marker.attached || !widget.scroll.hasClients) return null;
    final pos = widget.scroll.position;
    final pad = MediaQuery.paddingOf(context);
    // Aim at the layout the sheet is heading to (full screen), not the current one: the sheet
    // expands during the same motion, and a moving target would make the folder overshoot.
    final inset = DS.gutter + pad.top; // pinned top spacer at full screen
    final dock = pad.bottom + _dockRoom + DS.s24; // floating search dock
    final visible = MediaQuery.sizeOf(context).height - inset - dock;
    // The marker is the gap just above the folder, so the folder starts DS.stack below it.
    final top = RenderAbstractViewport.of(marker).getOffsetToReveal(marker, 0).offset + DS.stack;
    final cardH = _headerExtent + body.size.height;
    final centred = top - inset - (visible - cardH) / 2;
    final headerAtTop = top - inset;
    return math.min(centred, headerAtTop).clamp(pos.minScrollExtent, pos.maxScrollExtent);
  }

  void _glideTick() {
    final id = _glideId;
    if (id == null || !widget.scroll.hasClients) return;
    final target = _targetFor(id);
    if (target == null) return;
    final t = Motion.settle.transform(_glide.value);
    widget.scroll.position.jumpTo(_glideFrom + (target - _glideFrom) * t);
  }

  // ---- Scroll-to-open (Settings → Open folders as you scroll) --------------------

  /// Folder ids in list order (from the last build).
  List<String> _folderIds = const [];

  /// The user moved the list since the last time it came to rest.
  bool _userMoved = false;

  /// The scroll began with the sheet already full screen (swiping the sheet itself up doesn't
  /// count: that's opening the drawer, not browsing folders).
  bool _startedFull = false;

  /// When the sheet last reached full screen. A fling that opens the drawer carries on into
  /// the list for a moment — that momentum is still "opening", not browsing.
  Duration? _fullSince; // frame clock
  void _trackFull() {
    final full = widget.expanded.value > .98;
    if (full && _fullSince == null) _fullSince = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (!full) _fullSince = null;
  }

  /// When the user's scroll comes to rest (finger lifted, fling finished), open the folder at
  /// the middle of the list and close the other — the same glide as tapping it. Not mid-drag:
  /// folders resizing under the finger would make the list jump.
  bool _onScrollEnd(ScrollEndNotification n) {
    if (n.depth == 0 && widget.pull.value > 0) widget.onPullEnd(); // finger lifted mid-pull
    if (n.metrics.axis != Axis.vertical || n.depth != 0 || !_userMoved) return false;
    _userMoved = false;
    if (!_startedFull) return false;
    if (!widget.prefs.autoOpenFolders || widget.searching || widget.expanded.value < .98) return false;
    // Measure after this frame's layout; the list is at rest, so ask for that frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_glide.isAnimating) _focusMiddle();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    return false;
  }

  void _focusMiddle() {
    if (!widget.scroll.hasClients || _folderIds.isEmpty) return;
    final pos = widget.scroll.position;
    final pad = MediaQuery.paddingOf(context);
    final inset = DS.gutter + pad.top; // pinned spacer at the top
    final visible = pos.viewportDimension - inset - (pad.bottom + _dockRoom + DS.s24); // above the dock
    // The focus line sits in the middle of what's visible. Near either end the list can't bring
    // a folder to the middle (the last folders never get there), so the line slides toward that
    // end instead: at the very bottom it reaches the last folder, at the very top the green card.
    var line = inset + visible / 2;
    line += math.max(0, visible / 2 - (pos.maxScrollExtent - pos.pixels));
    line -= math.max(0, visible / 2 - (pos.pixels - pos.minScrollExtent));
    final at = pos.pixels + line; // in list coordinates

    String? pick; // null = above the first folder (the green card): close any open one
    for (final id in _folderIds) {
      final marker = _markerKeys[id]?.currentContext?.findRenderObject();
      final body = _bodyKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
      if (marker == null || body == null || !marker.attached) continue;
      final top = RenderAbstractViewport.of(marker).getOffsetToReveal(marker, 0).offset; // gap above the folder
      if (at < top) break;
      pick = id; // at or below this folder's top: it, unless a later folder starts above the line
      if (at < top + DS.stack + _headerExtent + body.size.height) break;
    }
    if (pick == _openId) return;
    if (pick == null) {
      HapticFeedback.selectionClick();
      setState(() => _openId = null);
    } else {
      _toggle(pick); // opens it, closes the other, glides it to the middle
    }
  }

  // ---- Pull-to-search -----------------------------------------------------------

  /// Dragging down when the list can't go further up (and the sheet can't shrink further):
  /// that pull is pull-to-search. The home screen decides whether it counts.
  bool _onOverscroll(OverscrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || n.dragDetails == null) return false;
    if (n.overscroll < 0) widget.onPull(-n.overscroll);
    return false;
  }

  /// A finger on the list takes over from the glide.
  bool _onScrollStart(ScrollStartNotification n) {
    if (n.depth == 0) _userMoved = false; // a new scroll: decide afresh where it started
    if (n.dragDetails != null && _glide.isAnimating) _glide.stop();
    return false;
  }

  bool _onScroll(ScrollUpdateNotification n) {
    // Scrolling up/down (the list, or the results) closes the keyboard; swiping the results'
    // sideways app row doesn't — you're still choosing, keep typing.
    if (n.dragDetails != null && n.metrics.axis == Axis.vertical) FocusManager.instance.primaryFocus?.unfocus();
    if (n.metrics.axis != Axis.vertical || n.depth != 0) return false; // the main list only
    final d = n.scrollDelta ?? 0;
    // Mid-pull, moving the finger back up takes the pull back first.
    if (widget.pull.value > 0 && n.dragDetails != null && d > 0) widget.onPull(-d);
    // Pulling the results down while searching = done searching — with the bar at the top.
    // With the bar at the bottom the results scroll on their own; the bar swipes away instead.
    if (widget.searching && widget.searchBar != null && n.dragDetails != null && d < -2) {
      widget.onDismissSearch();
      return false;
    }
    // Only scrolling the user does (a drag, or the fling after it) moves the search bar.
    // The folder glide and other scrolls the app makes itself must leave it alone.
    final byUser = _handoff || (widget.scroll.hasClients && widget.scroll.position.userScrollDirection != ScrollDirection.idle);
    if (_glide.isAnimating) return false;
    // Scroll-to-open counts every movement but the glide — including a fling handed on from
    // an open folder's grid, which reaches the list as a plain (not user-marked) scroll.
    if (!_userMoved) {
      // First move of this scroll: did it start with the drawer already full screen?
      final since = _fullSince;
      _startedFull = since != null && SchedulerBinding.instance.currentSystemFrameTimeStamp - since > const Duration(milliseconds: 250);
    }
    _userMoved = true;
    if (!byUser) return false;
    if (n.metrics.pixels <= 0) {
      widget.onCompact(false);
    } else if (d > 2) {
      widget.onCompact(true); // finger moving up → content scrolls up → dock shrinks
    } else if (d < -2) {
      widget.onCompact(false);
    }
    return false;
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Granular lookups: the full MediaQuery would rebuild the whole list on every frame of the
    // keyboard sliding in; only the bottom spacer below listens to the keyboard.
    final padding = MediaQuery.paddingOf(context);
    final statusBar = padding.top;
    final prefs = widget.prefs;
    final (apps, folderGroups, top) = _derived();
    // Recently installed sits above the other folders (Settings → Recently installed); it
    // changes with the clock, so it isn't cached with the folders.
    final recent = prefs.recentInstalls ? recentInstalls(apps, prefs) : const <AppEntry>[];
    final groups = [if (recent.isNotEmpty) (recentlyInstalled, recent), ...folderGroups];
    final fresh = {
      for (final a in apps)
        if (isNewApp(a, prefs)) a.package,
    };
    // The dots on their icons: set after this frame (other screens listen too).
    if (!setEquals(fresh, newApps.value)) WidgetsBinding.instance.addPostFrameCallback((_) => newApps.value = fresh);
    _folderIds = [for (final (f, _) in groups) f.id];
    final pinned = prefs.favourites.toSet();

    // The green hero card IS the Most used folder: always first, always open.
    final hero = _HeroCard(
      apps: top,
      pinned: pinned,
      onCustomise: () => showCustomiseFolder(context, prefs: prefs, folder: mostUsed, allApps: widget.apps),
      onLaunch: widget.onLaunch,
      onLongPress: _longPress,
    );

    final gutter = const EdgeInsets.symmetric(horizontal: DS.gutter);
    // Cards in the main list scale 90→100% at its edges (subtle — more read as jumpy); the pinned top strip and the area
    // behind the floating search bar count as out of view.
    Widget edge(Widget child) =>
        EdgeScale(minScale: .9, startInset: DS.gutter + statusBar * widget.expanded.value, endInset: padding.bottom + _dockRoom + DS.s12, child: child);
    Widget box(Widget child) => SliverPadding(
      padding: gutter,
      sliver: SliverToBoxAdapter(child: child),
    );

    // RepaintBoundary: each card repaints on its own (icons popping, chevron turning…).
    Widget folderHeader(int i, Folder folder, List<AppEntry> list) => KeyedSubtree(
      key: _header(folder.id),
      child: RepaintBoundary(
        child: PopIn(
          delay: ((i + 1) * 0.05).clamp(0, .4),
          offset: const Offset(0, 24),
          fromScale: .97,
          child: _FolderHeader(
            folder: folder,
            name: prefs.folderName(folder),
            apps: list,
            open: _openId == folder.id,
            tone: i == groups.length - 1 && groups.length > 1 ? CardTone.muted : CardTone.white,
            onToggle: () => _toggle(folder.id),
            onCustomise: () =>
                showCustomiseFolder(context, prefs: prefs, folder: folder, allApps: widget.apps, visibleOrder: [for (final (f, _) in folderGroups) f.id]),
          ),
        ),
      ),
    );

    // Results only once something is typed; an empty search keeps the usual list in place
    // (so opening search never swaps the screen out from under the motion) — or, with search
    // history, shows the recent searches card.
    final q = widget.query.trim();
    final history = widget.searching && q.isEmpty && RecentSearches.shows(prefs);
    final showResults = (widget.searching && q.isNotEmpty) || history;
    // Bar at the bottom → results grow upward from it (best match nearest the bar).
    final upward = showResults && widget.searchBar == null;
    final List<Widget> content;
    if (showResults) {
      final sources = prefs.searchIn;
      if (sources.contains('shortcuts')) _loadShortcuts();
      final Widget found = history
          ? RecentSearches(prefs: prefs, upward: upward, onPick: widget.onPickRecent, onFill: widget.onFillRecent)
          : _SearchResults(
              query: q,
              apps: sources.contains('apps') ? searchApps(widget.apps, widget.query) : const [],
              shortcuts: [
                for (final sc in sources.contains('shortcuts') ? (_shortcuts ?? const <AppShortcut>[]) : const <AppShortcut>[])
                  if (matchesQuery(q, [sc.label, sc.app])) sc,
              ].take(5).toList(),
              settings: sources.contains('settings')
                  ? [
                      for (final st in systemSettings)
                        if (matchesQuery(q, [st.title, st.keywords])) st,
                    ].take(4).toList()
                  : const [],
              web: sources.contains('google'),
              play: sources.contains('play'),
              oneStream: sources.contains('onestream'),
              upward: upward,
              prefs: prefs,
              google: widget.apps.any((a) => a.package == 'com.google.android.googlequicksearchbox'),
              onTap: widget.onLaunch,
              onLongPress: _longPress,
              onWebSearch: widget.onWebSearch,
              onRun: widget.onRun,
            );
      // Enters rising out of the bar (or dropping from the top bar), fading in — once when the
      // recent searches appear and once when typing turns them into results, not per keystroke.
      final Widget results = SearchEnter(key: ValueKey(history ? 'history' : 'results'), upward: upward, child: found);
      content = [
        if (upward)
          // Their own scroll area, reversed: it starts at the bottom (best match just above the
          // bar and keyboard) and scrolls up for more. Being separate, dragging it never moves
          // or closes the sheet — closing is a swipe down on the search bar.
          SliverFillRemaining(
            hasScrollBody: true,
            child: Builder(
              builder: (context) => SingleChildScrollView(
                reverse: true,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                padding: EdgeInsets.fromLTRB(DS.gutter, 0, DS.gutter, MediaQuery.viewInsetsOf(context).bottom + padding.bottom + _dockRoom + DS.s24),
                child: results,
              ),
            ),
          )
        else
          box(results),
      ];
    } else {
      content = [
        box(edge(PopIn(offset: const Offset(0, 24), fromScale: .97, child: hero))),
        for (final (i, (folder, list)) in groups.indexed) ...[
          // Gap above the folder; its key marks where the folder starts.
          SliverToBoxAdapter(
            child: SizedBox(key: _marker(folder.id), height: DS.stack),
          ),
          SliverPadding(
            padding: gutter,
            // Header + grid as one group: an open folder's header pins to the top while its
            // apps scroll under it, and leaves with the folder's end.
            sliver: SliverMainAxisGroup(
              slivers: [
                // Open folder: header pins to the top while its apps scroll under it.
                if (_openId == folder.id)
                  PinnedHeaderSliver(child: folderHeader(i, folder, list))
                else
                  SliverToBoxAdapter(child: edge(folderHeader(i, folder, list))), // closed folders scale at the edges
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: _FolderBody(
                      key: _body(folder.id),
                      apps: list,
                      open: _openId == folder.id,
                      tone: i == groups.length - 1 && groups.length > 1 ? CardTone.muted : CardTone.white,
                      maxHeight: _maxBodyHeight(MediaQuery.sizeOf(context), padding),
                      outer: widget.scroll,
                      onHandoff: (on) => _handoff = on,
                      onLaunch: widget.onLaunch,
                      onLongPress: _longPress,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ];
    }

    // Glass: the whole drawer is one frosted pane over the wallpaper (cards inside are tints).
    final glass = Glass.classic && Glass.blur > 0 && !Perf.lite.value;
    final drawer = Material(
      color: Glass.classic ? Glass.tinted(DS.canvas) : DS.canvas,
      borderRadius: BorderRadius.vertical(top: Radius.circular(DS.rSheet)),
      clipBehavior: Clip.antiAlias,
      // Pull-to-search: the list slides down with the pull and a search pill grows in the gap.
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.pull, widget.pullOpening]),
        builder: (context, list) {
          final p = widget.pull.value;
          final y = pullOffset(p);
          final t = (p / pullToOpen).clamp(0.0, 1.0);
          return Stack(
            children: [
              Transform.translate(offset: Offset(0, y), child: list),
              if (p > 0)
                Positioned(
                  top: DS.s8 + math.max(0.0, (y - 44) / 2),
                  left: 0,
                  right: 0,
                  // Once released to open, the pill stays "ready" while it fades (no flip back).
                  child: IgnorePointer(
                    child: _PullPill(progress: t, ready: widget.pullOpening.value || t >= 1),
                  ),
                ),
            ],
          );
        },
        child: NotificationListener<OverscrollNotification>(
          onNotification: _onOverscroll,
          child: NotificationListener<ScrollStartNotification>(
            onNotification: _onScrollStart,
            child: NotificationListener<ScrollEndNotification>(
              onNotification: _onScrollEnd,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: _onScroll,
                child: CustomScrollView(
                  controller: widget.scroll,
                  physics: const ClampingScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual, // see _onScroll: only up/down drags close the keyboard
                  slivers: [
                    // Pinned top spacer in the sheet colour: grows to cover the status bar as the sheet
                    // reaches full screen, and pinned folder headers stop just below it. Only this
                    // spacer follows the sheet's drag, so the cards don't rebuild every frame.
                    PinnedHeaderSliver(
                      child: ValueListenableBuilder<double>(
                        valueListenable: widget.expanded,
                        builder: (context, e, _) => SizedBox(
                          height: DS.gutter + statusBar * e,
                          child: ColoredBox(color: DS.canvas),
                        ),
                      ),
                    ),
                    // The search bar, when it lives in the list (Settings → Search bar: Top).
                    if (widget.searchBar != null) SliverToBoxAdapter(child: widget.searchBar!),
                    ...content,
                    // Room for the floating search dock (and the keyboard while searching).
                    if (!upward)
                      SliverToBoxAdapter(
                        child: Builder(builder: (context) => SizedBox(height: MediaQuery.viewInsetsOf(context).bottom + padding.bottom + _dockRoom + DS.s32)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!glass) return drawer;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DS.rSheet)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: Glass.blur, sigmaY: Glass.blur),
        child: drawer,
      ),
    );
  }
}

/// How far a pull of [p] px moves the list: follows the finger, then resists (rubber band).
double pullOffset(double p) => 140 * (1 - math.exp(-p / 140));

/// Pull this far (px of finger travel) and let go to open search.
const pullToOpen = 200.0; // long enough that the nav → search morph visibly scrubs under the finger

/// The pill that grows in the gap while pulling the drawer down: "Pull to search", then
/// "Release to search" (filled) once far enough.
class _PullPill extends StatelessWidget {
  const _PullPill({required this.progress, required this.ready});
  final double progress;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: progress,
        child: Transform.scale(
          scale: .7 + .3 * progress,
          child: AnimatedContainer(
            duration: Motion.pressIn,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: DS.s16),
            decoration: BoxDecoration(color: ready ? DS.hero : DS.card, borderRadius: BorderRadius.circular(22)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, size: 20, color: ready ? DS.heroInk : DS.ink),
                const SizedBox(width: DS.s8),
                Text(ready ? 'Release to search' : 'Pull to search', style: DS.pill.copyWith(color: ready ? DS.heroInk : DS.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Cards ------------------------------------------------------------------

/// The green card: pinned apps first, then the most used. No header; a small menu sits at the bottom.
/// The green card: pinned apps first, then the most used — up to 2 pages of 8 that you swipe
/// left/right. No header; page dots and a small menu sit along the bottom.
class _HeroCard extends StatefulWidget {
  const _HeroCard({required this.apps, required this.pinned, required this.onCustomise, required this.onLaunch, required this.onLongPress});

  final List<AppEntry> apps;
  final Set<String> pinned; // package ids
  final VoidCallback onCustomise;
  final ValueChanged<AppEntry> onLaunch, onLongPress;

  static const perPage = 8;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _grid(List<AppEntry> apps, double cellW, int offset, {bool edge = false}) => Wrap(
    children: [
      for (final (i, a) in apps.indexed)
        SizedBox(
          width: cellW,
          child: edge
              ? EdgeScale(
                  child: PopIn(
                    delay: (i ~/ 4) * 0.06 + (i % 4) * 0.02,
                    child: _GridApp(
                      app: a,
                      labelColor: DS.heroInk,
                      pinned: widget.pinned.contains(a.package),
                      onTap: () => widget.onLaunch(a),
                      onLongPress: () => widget.onLongPress(a),
                    ),
                  ),
                )
              : PopIn(
                  delay: (i ~/ 4) * 0.06 + (i % 4) * 0.02,
                  child: _GridApp(
                    app: a,
                    labelColor: DS.heroInk,
                    pinned: widget.pinned.contains(a.package),
                    onTap: () => widget.onLaunch(a),
                    onLongPress: () => widget.onLongPress(a),
                  ),
                ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final apps = widget.apps;
    const per = _HeroCard.perPage;
    final pages = [for (var p = 0; p < apps.length && p < 2 * per; p += per) apps.sublist(p, (p + per).clamp(0, apps.length))];
    // One grid cell: padding 8+8, icon 48, gap 6, one line of 12pt label.
    final cellH = 16 + DS.appIcon + 6 + MediaQuery.textScalerOf(context).scale(12) * 1.2 + 2;
    final rows = pages.isEmpty ? 0 : (pages.first.length / 4).ceil(); // height follows page 1
    return OneCard(
      tone: CardTone.hero,
      padding: const EdgeInsets.fromLTRB(DS.s12, DS.s16, DS.s12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (apps.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s8, DS.s8, DS.s12, 0),
              child: Text('Pin apps or open a few, they’ll gather here', style: DS.display),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth / 4;
                if (pages.length == 1) return _grid(pages.first, w, 0);
                return SizedBox(
                  height: rows * cellH,
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: pages.length,
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() => _page = i);
                    },
                    itemBuilder: (context, i) => Align(alignment: Alignment.topLeft, child: _grid(pages[i], w, i * per, edge: true)),
                  ),
                );
              },
            ),
          // Bottom row: page dots (when there are 2 pages) and the small menu.
          Row(
            children: [
              const SizedBox(width: DS.s8),
              if (pages.length > 1)
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: Motion.snapDuration,
                    curve: Motion.settle,
                    width: i == _page ? 16 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(color: i == _page ? DS.heroInk : DS.heroDivider, borderRadius: BorderRadius.circular(3)),
                  ),
              const Spacer(),
              CircleButton(icon: Icons.more_horiz_rounded, tone: CircleTone.soft, size: 32, tooltip: 'Customise pinned & most used', onTap: widget.onCustomise),
            ],
          ),
        ],
      ),
    );
  }
}

/// Top of a folder card: count pill, name, preview of app names, ••• (when open) and chevron.
/// Rounded all round when closed; only on top when open (the grid continues below).
class _FolderHeader extends StatelessWidget {
  const _FolderHeader({
    required this.folder,
    required this.name,
    required this.apps,
    required this.open,
    required this.tone,
    required this.onToggle,
    required this.onCustomise,
  });

  final Folder folder;
  final String name;
  final List<AppEntry> apps;
  final bool open;
  final CardTone tone;
  final VoidCallback onToggle, onCustomise;

  @override
  Widget build(BuildContext context) {
    final names = apps.take(3).map((a) => a.label).join(', ') + (apps.length > 3 ? '…' : '');
    final r = Radius.circular(DS.rCard);
    return AnimatedContainer(
      duration: Motion.snapDuration,
      curve: Motion.settle,
      decoration: BoxDecoration(
        color: Glass.on(tone == CardTone.muted ? DS.cardMuted : DS.card),
        borderRadius: BorderRadius.vertical(top: r, bottom: open ? Radius.zero : r),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(DS.s12, DS.s12, DS.s8, DS.s12),
            child: Row(
              children: [
                // The folder's look: its first apps in a little triangle. Opening shrinks them away
                // to the folder's own symbol (its apps are in the grid below then).
                SizedBox.square(
                  dimension: 64,
                  child: AnimatedSwitcher(
                    duration: Motion.snapDuration,
                    switchInCurve: Motion.pop,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: open || apps.isEmpty
                        ? Center(
                            key: const ValueKey('symbol'),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: tone == CardTone.muted ? DS.card : DS.cardMuted, shape: BoxShape.circle),
                              child: Icon(folder.icon, size: 22, color: DS.ink),
                            ),
                          )
                        : Center(
                            key: const ValueKey('trio'),
                            child: _AppTrio(apps: apps),
                          ),
                  ),
                ),
                const SizedBox(width: DS.s16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(name, style: DS.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          Icon(folder.icon, size: 16, color: DS.inkFaint),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(names, style: DS.rowSub, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                // "Customise" appears only on the open folder.
                AnimatedSwitcher(
                  duration: Motion.snapDuration,
                  switchInCurve: Motion.pop,
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: a,
                    child: FadeTransition(opacity: a, child: child),
                  ),
                  child: open
                      ? CircleButton(
                          key: const ValueKey('more'),
                          icon: Icons.more_horiz_rounded,
                          tone: CircleTone.outline,
                          tooltip: 'Customise folder',
                          onTap: onCustomise,
                        )
                      : const SizedBox(key: ValueKey('none')),
                ),
                CircleButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  tone: CircleTone.outline,
                  turns: open ? .5 : 0,
                  tooltip: open ? 'Close folder' : 'Open folder',
                  onTap: onToggle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three app icons in a triangle — the biggest on top, each next one smaller — as a
/// folder's icon.
class _AppTrio extends StatelessWidget {
  const _AppTrio({required this.apps});
  final List<AppEntry> apps;

  /// (left, top, size) inside a 48 × 48 box, for 1, 2 or 3 icons.
  static List<(double, double, double)> _slots(int n) => switch (n) {
    1 => const [(11, 11, 26)],
    2 => const [(12, 2, 25), (5, 27, 19)],
    _ => const [(12, 1, 24), (3, 26, 19), (28, 30, 15)],
  };

  @override
  Widget build(BuildContext context) {
    final slots = _slots(apps.length < 3 ? apps.length : 3);
    return SizedBox.square(
      dimension: 48,
      child: Stack(
        children: [
          for (final (i, (x, y, size)) in slots.indexed)
            Positioned(
              left: x,
              top: y,
              child: AppIcon(apps[i], size: size),
            ),
        ],
      ),
    );
  }
}

/// The app grid under an open folder's header; springs open/closed. Never taller than
/// [maxHeight]: longer folders scroll their grid, and when the grid reaches its end the rest of
/// the drag (or fling) carries on scrolling the main list ([outer]).
class _FolderBody extends StatefulWidget {
  const _FolderBody({
    super.key,
    required this.apps,
    required this.open,
    required this.tone,
    required this.maxHeight,
    required this.outer,
    required this.onHandoff,
    required this.onLaunch,
    required this.onLongPress,
  });

  final List<AppEntry> apps;
  final bool open;
  final CardTone tone;
  final double maxHeight;
  final ScrollController outer;
  final ValueChanged<bool> onHandoff;
  final ValueChanged<AppEntry> onLaunch, onLongPress;

  @override
  State<_FolderBody> createState() => _FolderBodyState();
}

class _FolderBodyState extends State<_FolderBody> {
  final _grid = ScrollController();
  bool _flungOn = false; // a fling already passed on to the main list

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_FolderBody old) {
    super.didUpdateWidget(old);
    if (!widget.open && _grid.hasClients) _grid.jumpTo(0); // reopen at the top
  }

  ScrollPositionWithSingleContext? get _outer =>
      widget.outer.hasClients && widget.outer.position is ScrollPositionWithSingleContext ? widget.outer.position as ScrollPositionWithSingleContext : null;

  /// Nested scrolling: whatever the grid can't use goes to the main list.
  bool _onGridScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final outer = _outer;
    if (outer == null) return false;
    if (n is ScrollStartNotification) _flungOn = false;
    if (n is OverscrollNotification) {
      if (n.dragDetails != null) {
        // Dragging past the grid's end: move the main list by the leftover.
        widget.onHandoff(true);
        outer.jumpTo((outer.pixels + n.overscroll).clamp(outer.minScrollExtent, outer.maxScrollExtent));
        widget.onHandoff(false);
      } else if (!_flungOn && n.velocity != 0) {
        // A fling ran out of grid: let the main list carry the momentum.
        _flungOn = true;
        outer.goBallistic(n.velocity);
      }
    } else if (n is ScrollEndNotification && n.dragDetails != null && !_flungOn) {
      // Flicked while already at the grid's end: the whole fling goes to the main list.
      final v = -(n.dragDetails!.primaryVelocity ?? 0);
      if ((v > 0 && n.metrics.extentAfter == 0) || (v < 0 && n.metrics.extentBefore == 0)) {
        _flungOn = true;
        outer.goBallistic(v);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final apps = widget.apps;
    // Space for the grid: body minus divider + gap (13) and bottom padding (16).
    final gridMax = widget.maxHeight - 29;
    // No overshoot here: the centring glide follows this height every frame.
    return AnimatedSize(
      duration: Motion.snapDuration,
      curve: Motion.settle,
      alignment: Alignment.topCenter,
      child: !widget.open
          ? const SizedBox(width: double.infinity)
          : Container(
              decoration: BoxDecoration(
                color: Glass.on(widget.tone == CardTone.muted ? DS.cardMuted : DS.card),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(DS.rCard)),
              ),
              padding: const EdgeInsets.fromLTRB(DS.s12, 0, DS.s12, DS.s16),
              child: Column(
                children: [
                  const CardDivider(),
                  const SizedBox(height: DS.s12),
                  if (apps.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(DS.s16),
                      child: Text('No apps here yet.', style: DS.rowSub),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: gridMax),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onGridScroll,
                        child: ListenableBuilder(
                          listenable: _grid,
                          // Soft fade at an edge that has more apps beyond it.
                          builder: (context, child) {
                            final p = _grid.hasClients && _grid.position.haveDimensions ? _grid.position : null;
                            final top = p != null && p.extentBefore > 0, bottom = p != null && p.extentAfter > 0;
                            // Always the same widgets (only the gradient changes): swapping the tree
                            // would rebuild the scroller and throw away its scroll position.
                            // Card-coloured gradient strips, not a ShaderMask: a mask is an offscreen
                            // layer redrawn every scroll frame, the strips are two cheap rectangles.
                            final bg = widget.tone == CardTone.muted ? DS.cardMuted : DS.card;
                            Widget strip(bool on, bool atTop) => Positioned(
                              left: 0,
                              right: 0,
                              top: atTop ? 0 : null,
                              bottom: atTop ? null : 0,
                              height: DS.s24,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
                                      end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
                                      colors: [
                                        bg.withValues(alpha: on ? 1 : 0),
                                        bg.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                            return Stack(children: [child!, strip(top, true), strip(bottom, false)]);
                          },
                          child: SingleChildScrollView(
                            controller: _grid,
                            physics: const ClampingScrollPhysics(),
                            child: LayoutBuilder(
                              builder: (context, c) {
                                final w = c.maxWidth / 4;
                                return Wrap(
                                  children: [
                                    for (final (i, a) in apps.indexed)
                                      SizedBox(
                                        width: w,
                                        // Icons pop in row by row, and grow in / shrink out at the scroll edges.
                                        child: EdgeScale(
                                          child: PopIn(
                                            delay: ((i ~/ 4) * 0.06 + (i % 4) * 0.02).clamp(0, .6),
                                            child: _GridApp(app: a, onTap: () => widget.onLaunch(a), onLongPress: () => widget.onLongPress(a)),
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
                    ),
                ],
              ),
            ),
    );
  }
}

class _GridApp extends StatelessWidget {
  const _GridApp({required this.app, required this.onTap, required this.onLongPress, this.labelColor, this.pinned = false});
  final AppEntry app;
  final Color? labelColor; // defaults to DS.ink (themed, so resolved at build time)
  final bool pinned;
  final VoidCallback onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: 0.9,
      child: InkWell(
        onTap: () {
          Apps.instance.markLaunchFrom(context); // app opens growing out of this icon
          onTap();
        },
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(DS.rMedia),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DS.s8, horizontal: DS.s4),
          child: Column(
            children: [
              // No pin badge (pinning stays in the long-press menu); a dot on apps not opened
              // since they were installed.
              ValueListenableBuilder<Set<String>>(
                valueListenable: newApps,
                builder: (context, fresh, icon) => fresh.contains(app.package)
                    ? Stack(
                        clipBehavior: Clip.none,
                        children: [
                          icon!,
                          Positioned(top: -3, right: -3, child: NewDot(semantics: '${app.label}, new')),
                        ],
                      )
                    : icon!,
                child: AppIcon(app, size: DS.appIcon),
              ),
              const SizedBox(height: 6),
              Text(
                app.label,
                style: DS.iconLabel.copyWith(color: labelColor ?? DS.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The classic home's search results for [query], from the sources in Settings → Search →
/// Search in — the Tiles search shows the same. [shortcuts]: the app shortcuts (loaded once).
Widget searchResults({
  required Prefs prefs,
  required String query,
  required List<AppEntry> apps,
  required List<AppShortcut>? shortcuts,
  required ValueChanged<AppEntry> onLaunch,
  required ValueChanged<AppEntry> onLongPress,
  required void Function(String query, {bool play}) onWebSearch,
  required void Function(Future<void> Function() action) onRun,
}) {
  final q = query.trim();
  final sources = prefs.searchIn;
  return _SearchResults(
    query: q,
    apps: sources.contains('apps') ? searchApps(apps, q) : const [],
    shortcuts: [
      for (final sc in sources.contains('shortcuts') ? (shortcuts ?? const <AppShortcut>[]) : const <AppShortcut>[])
        if (matchesQuery(q, [sc.label, sc.app])) sc,
    ].take(5).toList(),
    settings: sources.contains('settings')
        ? [
            for (final st in systemSettings)
              if (matchesQuery(q, [st.title, st.keywords])) st,
          ].take(4).toList()
        : const [],
    web: sources.contains('google'),
    play: sources.contains('play'),
    oneStream: sources.contains('onestream'),
    upward: false,
    prefs: prefs,
    google: apps.any((a) => a.package == 'com.google.android.googlequicksearchbox'),
    onTap: onLaunch,
    onLongPress: onLongPress,
    onWebSearch: onWebSearch,
    onRun: onRun,
  );
}

/// Search results, by source (Settings → Search → Search in): apps (best match big with
/// Open — what Enter does — the other matches in one sideways-scrolling row), app shortcuts, phone settings, then the web
/// (Google / browser) and the Play Store. With the bar at the bottom everything stacks upward
/// from it: the best match sits right above the bar.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.apps,
    required this.shortcuts,
    required this.settings,
    required this.web,
    required this.play,
    this.oneStream = false,
    required this.upward,
    required this.prefs,
    required this.google,
    required this.onTap,
    required this.onLongPress,
    required this.onWebSearch,
    required this.onRun,
  });
  final String query;
  final List<AppEntry> apps;
  final List<AppShortcut> shortcuts;
  final List<SystemSetting> settings;
  final bool web, play, upward;
  final bool oneStream; // movies & shows from One Stream (shows itself once it has results)
  final Prefs prefs;
  final bool google; // the Google app is installed → say "Google"
  final ValueChanged<AppEntry> onTap, onLongPress;
  final void Function(String query, {bool play}) onWebSearch;
  final void Function(Future<void> Function() action) onRun;

  String _where(AppEntry a) => '${a.work ? 'Work · ' : ''}${prefs.folderName(folderFor(a, prefs.folderOverrides))}';

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s16, DS.s4),
    child: Text(text, style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 13)),
  );

  /// Card body rows, flipped when the list grows upward.
  List<Widget> _ordered(List<Widget> rows) => upward ? rows.reversed.toList() : rows;

  Widget _appsCard() {
    final top = apps.first;
    final rest = apps.skip(1).toList();
    final best = Builder(
      builder: (rowContext) => InkWell(
        borderRadius: BorderRadius.circular(DS.rMedia),
        onTap: () {
          Apps.instance.markLaunchFrom(rowContext);
          onTap(top);
        },
        onLongPress: () => onLongPress(top),
        child: Padding(
          padding: const EdgeInsets.all(DS.s8),
          child: Row(
            children: [
              AppIcon(top, size: 52),
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      top.label,
                      style: DS.rowTitle.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(_where(top), style: DS.rowSub),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: DS.ink, borderRadius: BorderRadius.circular(99)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Open', style: DS.pill.copyWith(color: DS.card)),
                    const SizedBox(width: 2),
                    Icon(Icons.north_east_rounded, size: 14, color: DS.card),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return OneCard(
      padding: const EdgeInsets.all(DS.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _ordered([
          best,
          if (rest.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: DS.s8, vertical: DS.s4),
              child: CardDivider(),
            ),
            // The other matches: one row that scrolls sideways (next best first), so the
            // result list stays short and other kinds of results stay in view.
            SizedBox(
              height: 96,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: DS.s4),
                itemCount: rest.length,
                itemBuilder: (context, i) => SizedBox(
                  width: 78,
                  child: _GridApp(app: rest[i], onTap: () => onTap(rest[i]), onLongPress: () => onLongPress(rest[i])),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _rowsCard(String title, List<Widget> rows) => OneCard(
    padding: const EdgeInsets.symmetric(vertical: DS.s4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_title(title), ..._ordered(rows)]), // title stays on top
  );

  @override
  Widget build(BuildContext context) {
    // No "nothing matches" card: the web rows (and Movies & shows) are the way on.
    final sections = <Widget>[
      if (apps.isNotEmpty) _appsCard(),
      if (shortcuts.isNotEmpty)
        _rowsCard('App shortcuts', [
          for (final sc in shortcuts)
            _WebRow(
              leading: ShortcutIcon(id: sc.id, size: 24),
              title: sc.label,
              query: sc.work ? '${sc.app} · Work' : sc.app,
              quoted: false,
              onTap: () => onRun(() => Apps.instance.quickAction(sc.id)),
            ),
        ]),
      if (settings.isNotEmpty)
        _rowsCard('Phone settings', [
          for (final st in settings)
            _WebRow(icon: st.icon, title: st.title, query: 'Settings', quoted: false, onTap: () => onRun(() => Apps.instance.openSetting(st.action))),
        ]),
      // One Stream's movies & shows (when installed): a row of posters, before the web.
      if (oneStream)
        OneStreamSearchRow(
          key: const ValueKey('oneStream'),
          query: query,
          header: _title('Movies & shows'),
          wrap: (child) => OneCard(
            padding: const EdgeInsets.only(top: DS.s4, bottom: DS.s12),
            child: child,
          ),
          gap: const EdgeInsets.only(top: DS.stack), // carries its own gap: nothing shows until it has results
          onOpen: () => prefs.addSearch(query), // a poster opened: the search was used
        ),
      // The web, like the Pixel search bar: hands the query to Google / the Play Store.
      if (web || play)
        OneCard(
          padding: const EdgeInsets.symmetric(vertical: DS.s4),
          child: Column(
            children: _ordered([
              if (web)
                _WebRow(icon: Icons.travel_explore_rounded, title: google ? 'Search Google' : 'Search the web', query: query, onTap: () => onWebSearch(query)),
              if (play) _WebRow(icon: Icons.shop_outlined, title: 'Find apps on Play Store', query: query, onTap: () => onWebSearch(query, play: true)),
            ]),
          ),
        ),
    ];
    final ordered = upward ? sections.reversed.toList() : sections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, w) in ordered.indexed) ...[if (i > 0 && w is! OneStreamSearchRow) const SizedBox(height: DS.stack), w],
      ],
    );
  }
}

class _WebRow extends StatelessWidget {
  const _WebRow({this.icon, this.leading, required this.title, required this.query, this.quoted = true, required this.onTap});
  final IconData? icon;
  final Widget? leading; // e.g. an app shortcut's own icon
  final String title, query;
  final bool quoted; // subtitle is the search text ("…") or a plain label
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: DS.cardMuted, shape: BoxShape.circle),
              child: leading ?? Icon(icon, size: 22, color: DS.ink),
            ),
            const SizedBox(width: DS.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(quoted ? '“$query”' : query, style: DS.rowSub, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.north_east_rounded, size: 18, color: DS.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// The small dot on a newly installed app's icon, until it's opened once.
class NewDot extends StatelessWidget {
  const NewDot({super.key, this.semantics});
  final String? semantics;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics ?? 'New',
    child: Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: DS.ink,
        shape: BoxShape.circle,
        border: Border.all(color: DS.card, width: 2),
      ),
    ),
  );
}

/// Search's card arriving: a fade with a short rise from the search bar (bar at the bottom) or
/// drop from it (bar at the top), settling from 97 %. Plays once per key.
class SearchEnter extends StatelessWidget {
  const SearchEnter({super.key, required this.child, this.upward = true});
  final Widget child;
  final bool upward;

  @override
  Widget build(BuildContext context) {
    if (Perf.lite.value) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.snapDuration,
      curve: Motion.settle,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (upward ? 28 : -16) * (1 - t)),
          child: Transform.scale(scale: .97 + .03 * t, alignment: upward ? Alignment.bottomCenter : Alignment.topCenter, child: child),
        ),
      ),
    );
  }
}
