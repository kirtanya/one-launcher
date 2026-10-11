import 'package:flutter/foundation.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'folders.dart';
import 'prefs.dart';
import 'search.dart';
import 'search_dock.dart';
import 'sheets.dart';
import 'ui/components.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'widgets.dart';

/// The bottom sheet of the one-screen launcher: pastel hero card, then "Most used",
/// then one card per folder of similar apps. Only one folder is open at a time.
/// While searching it shows results instead (search itself lives in the bottom dock).
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
  });

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

  /// Back to the resting state (Home pressed / after launching an app).
  void reset() {
    if (_openId != null) setState(() => _openId = null);
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

  /// Height of a folder's header row (pill 64 + padding 12 × 2).
  static const _headerExtent = 88.0;

  /// Drives the "open folder → centre it" glide, in step with the folder growing.
  late final AnimationController _glide = AnimationController(vsync: this, duration: Motion.snapDuration)..addListener(_glideTick);
  String? _glideId;
  double _glideFrom = 0;

  @override
  void dispose() {
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
    if (!opening || !widget.scroll.hasClients) return;
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
    final mq = MediaQuery.of(context);
    // Aim at the layout the sheet is heading to (full screen), not the current one: the sheet
    // expands during the same motion, and a moving target would make the folder overshoot.
    final inset = DS.gutter + mq.padding.top; // pinned top spacer at full screen
    final dock = mq.padding.bottom + SearchDock.height + DS.s24; // floating search dock
    final visible = mq.size.height - inset - dock;
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

  /// A finger on the list takes over from the glide.
  bool _onScrollStart(ScrollStartNotification n) {
    if (n.dragDetails != null && _glide.isAnimating) _glide.stop();
    return false;
  }

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final d = n.scrollDelta ?? 0;
    // Pulling the results down while searching = done searching.
    if (widget.searching && n.dragDetails != null && d < -2) {
      widget.onDismissSearch();
      return false;
    }
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
    final mq = MediaQuery.of(context);
    // Room for the floating search dock (and the keyboard while searching).
    final bottom = mq.viewInsets.bottom + mq.padding.bottom + SearchDock.height + DS.s32;
    final statusBar = mq.padding.top;
    final prefs = widget.prefs;
    final (apps, groups, top) = _derived();
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
                showCustomiseFolder(context, prefs: prefs, folder: folder, allApps: widget.apps, visibleOrder: [for (final (f, _) in groups) f.id]),
          ),
        ),
      ),
    );

    final List<Widget> content;
    if (widget.searching) {
      content = [
        box(
          widget.query.trim().isEmpty
              ? hero // suggestions while the field is empty
              : _ResultsCard(
                  query: widget.query.trim(),
                  results: searchApps(widget.apps, widget.query),
                  prefs: prefs,
                  onTap: widget.onLaunch,
                  onLongPress: _longPress,
                ),
        ),
      ];
    } else {
      content = [
        box(PopIn(offset: const Offset(0, 24), fromScale: .97, child: hero)),
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
                  SliverToBoxAdapter(child: folderHeader(i, folder, list)),
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: _FolderBody(
                      key: _body(folder.id),
                      apps: list,
                      open: _openId == folder.id,
                      tone: i == groups.length - 1 && groups.length > 1 ? CardTone.muted : CardTone.white,
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

    return Material(
      color: DS.canvas,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(DS.rSheet)),
      clipBehavior: Clip.antiAlias,
      child: NotificationListener<ScrollStartNotification>(
        onNotification: _onScrollStart,
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            controller: widget.scroll,
            physics: const ClampingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              ...content,
              SliverToBoxAdapter(child: SizedBox(height: bottom)),
            ],
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

  Widget _grid(List<AppEntry> apps, double cellW, int offset) => Wrap(
    children: [
      for (final (i, a) in apps.indexed)
        SizedBox(
          width: cellW,
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
                    itemBuilder: (context, i) => Align(alignment: Alignment.topLeft, child: _grid(pages[i], w, i * per)),
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
    const r = Radius.circular(DS.rCard);
    return AnimatedContainer(
      duration: Motion.snapDuration,
      curve: Motion.settle,
      decoration: BoxDecoration(
        color: tone == CardTone.muted ? DS.cardMuted : DS.card,
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
                DatePill(big: '${apps.length}', small: apps.length == 1 ? 'app' : 'apps'),
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

/// The app grid under an open folder's header; springs open/closed.
class _FolderBody extends StatelessWidget {
  const _FolderBody({super.key, required this.apps, required this.open, required this.tone, required this.onLaunch, required this.onLongPress});

  final List<AppEntry> apps;
  final bool open;
  final CardTone tone;
  final ValueChanged<AppEntry> onLaunch, onLongPress;

  @override
  Widget build(BuildContext context) {
    // No overshoot here: the centring glide follows this height every frame.
    return AnimatedSize(
      duration: Motion.snapDuration,
      curve: Motion.settle,
      alignment: Alignment.topCenter,
      child: !open
          ? const SizedBox(width: double.infinity)
          : Container(
              decoration: BoxDecoration(
                color: tone == CardTone.muted ? DS.cardMuted : DS.card,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(DS.rCard)),
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
                    LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth / 4;
                        return Wrap(
                          children: [
                            for (final (i, a) in apps.indexed)
                              SizedBox(
                                width: w,
                                // Icons pop in row by row.
                                child: PopIn(
                                  delay: (i ~/ 4) * 0.06 + (i % 4) * 0.02,
                                  child: _GridApp(app: a, onTap: () => onLaunch(a), onLongPress: () => onLongPress(a)),
                                ),
                              ),
                          ],
                        );
                      },
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
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(DS.rMedia),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DS.s8, horizontal: DS.s4),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppIcon(app, size: DS.appIcon),
                  // Small ink pin badge on pinned apps.
                  if (pinned)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: DS.ink,
                          shape: BoxShape.circle,
                          border: Border.all(color: DS.hero, width: 2),
                        ),
                        child: Icon(Icons.push_pin, size: 11, color: DS.card),
                      ),
                    ),
                ],
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

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.query, required this.results, required this.prefs, required this.onTap, required this.onLongPress});
  final String query;
  final List<AppEntry> results;
  final Prefs prefs;
  final ValueChanged<AppEntry> onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return OneCard(
        tone: CardTone.muted,
        child: Text('No app called “$query”', style: DS.rowSub),
      );
    }
    return OneCard(
      padding: const EdgeInsets.symmetric(vertical: DS.s8),
      child: Column(
        children: [
          for (final (i, a) in results.indexed)
            InkWell(
              onTap: () => onTap(a),
              onLongPress: () => onLongPress(a),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s8),
                child: Row(
                  children: [
                    AppIcon(a, size: 40),
                    const SizedBox(width: DS.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.label, style: DS.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${a.work ? 'Work · ' : ''}${prefs.folderName(folderFor(a, prefs.folderOverrides))}', style: DS.rowSub),
                        ],
                      ),
                    ),
                    if (i == 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        ],
      ),
    );
  }
}
