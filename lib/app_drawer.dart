import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

class AppDrawerState extends State<AppDrawer> {
  static const _mostUsedCount = 8;
  String? _openId; // the one open folder (Most used is the hero card, always open)

  /// Back to the resting state (Home pressed / after launching an app).
  void reset() {
    if (_openId != null) setState(() => _openId = null);
  }

  // ---- Data ----------------------------------------------------------------

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

  final _folderKeys = <String, GlobalKey>{};
  GlobalKey _keyFor(String id) => _folderKeys.putIfAbsent(id, GlobalKey.new);

  /// Accordion: opening one folder closes the other, then the opened folder glides to the
  /// middle of the screen (expanding the sheet first if it's at half height).
  void _toggle(String id) {
    HapticFeedback.selectionClick();
    final opening = _openId != id;
    setState(() => _openId = opening ? id : null);
    if (!opening) return;
    widget.onWantFull();
    // Wait for the open/close sizes to settle so the centre is measured on the final layout.
    Future.delayed(Motion.snapDuration, () {
      final ctx = _folderKeys[id]?.currentContext;
      if (!mounted || ctx == null || !ctx.mounted || _openId != id) return;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Motion.snapDuration, curve: Motion.settle);
    });
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
    final apps = _visible;
    final groups = groupApps(apps, prefs.folderOverrides, order: prefs.folderOrder);
    final top = _pinnedAndMostUsed(apps);
    final pinned = prefs.favourites.toSet();

    // The green hero card IS the Most used folder: always first, always open.
    final hero = _HeroCard(
      apps: top,
      pinned: pinned,
      onCustomise: () => showCustomiseFolder(context, prefs: prefs, folder: mostUsed, allApps: widget.apps),
      onLaunch: widget.onLaunch,
      onLongPress: _longPress,
    );

    final cards = <Widget>[
      if (widget.searching)
        widget.query.trim().isEmpty
            ? hero // suggestions while the field is empty
            : _ResultsCard(
                query: widget.query.trim(),
                results: searchApps(widget.apps, widget.query),
                prefs: prefs,
                onTap: widget.onLaunch,
                onLongPress: _longPress,
              )
      else ...[
        hero,
        for (final (i, (folder, list)) in groups.indexed)
          _FolderCard(
            key: _keyFor(folder.id),
            folder: folder,
            name: prefs.folderName(folder),
            apps: list,
            open: _openId == folder.id,
            tone: i == groups.length - 1 && groups.length > 1 ? CardTone.muted : CardTone.white,
            onToggle: () => _toggle(folder.id),
            onCustomise: () =>
                showCustomiseFolder(context, prefs: prefs, folder: folder, allApps: widget.apps, visibleOrder: [for (final (f, _) in groups) f.id]),
            onLaunch: widget.onLaunch,
            onLongPress: _longPress,
          ),
      ],
    ];

    return Material(
      color: DS.canvas,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(DS.rSheet)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          NotificationListener<ScrollUpdateNotification>(
            onNotification: _onScroll,
            child: ListView.separated(
              controller: widget.scroll,
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(DS.gutter, 0, DS.gutter, bottom),
              itemCount: cards.length + 1,
              separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 0 : DS.stack),
              itemBuilder: (context, i) {
                if (i == 0) {
                  // Top spacing (no handle). As the sheet reaches full screen it also makes room for the status bar.
                  return ValueListenableBuilder<double>(
                    valueListenable: widget.expanded,
                    builder: (context, e, _) => SizedBox(height: DS.gutter + statusBar * e),
                  );
                }
                // Cards pop in one after another the first time they appear.
                return PopIn(delay: ((i - 1) * 0.05).clamp(0, .4), offset: const Offset(0, 24), fromScale: .97, child: cards[i - 1]);
              },
            ),
          ),
          // Solid strip behind the status bar once the sheet is full, so cards don't scroll under the clock/battery icons.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: statusBar,
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: widget.expanded,
                // Only once the sheet is fully open; mid-drag it would darken the top cards.
                builder: (context, e, _) => ColoredBox(color: DS.canvas.withValues(alpha: ((e - .97) / .03).clamp(0.0, 1.0))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Cards ------------------------------------------------------------------

/// The green card: pinned apps first, then the most used. No header; a small menu sits at the bottom.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.apps, required this.pinned, required this.onCustomise, required this.onLaunch, required this.onLongPress});

  final List<AppEntry> apps;
  final Set<String> pinned; // package ids
  final VoidCallback onCustomise;
  final ValueChanged<AppEntry> onLaunch, onLongPress;

  @override
  Widget build(BuildContext context) {
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
                return Wrap(
                  children: [
                    for (final (i, a) in apps.indexed)
                      SizedBox(
                        width: w,
                        child: PopIn(
                          delay: (i ~/ 4) * 0.06 + (i % 4) * 0.02,
                          child: _GridApp(
                            app: a,
                            labelColor: DS.heroInk,
                            pinned: pinned.contains(a.package),
                            onTap: () => onLaunch(a),
                            onLongPress: () => onLongPress(a),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          // Small menu, bottom-right.
          Align(
            alignment: Alignment.centerRight,
            child: CircleButton(icon: Icons.more_horiz_rounded, tone: CircleTone.soft, size: 32, tooltip: 'Customise pinned & most used', onTap: onCustomise),
          ),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    super.key,
    required this.folder,
    required this.name,
    required this.apps,
    required this.open,
    required this.tone,
    required this.onToggle,
    required this.onCustomise,
    required this.onLaunch,
    required this.onLongPress,
  });

  final Folder folder;
  final String name;
  final List<AppEntry> apps;
  final bool open;
  final CardTone tone;
  final VoidCallback onToggle, onCustomise;
  final ValueChanged<AppEntry> onLaunch, onLongPress;

  @override
  Widget build(BuildContext context) {
    final names = apps.take(3).map((a) => a.label).join(', ') + (apps.length > 3 ? '…' : '');
    return OneCard(
      tone: tone,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Row header — tap anywhere to open/close.
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(DS.s12, DS.s12, DS.s8, DS.s12),
              child: Row(
                children: [
                  DatePill(big: '${apps.length}', small: apps.length == 1 ? 'app' : 'apps'),
                  const SizedBox(width: DS.s16),
                  Expanded(
                    child: Column(
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
          // Apps grid.
          AnimatedSize(
            duration: Motion.snapDuration,
            curve: Motion.snap,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
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
          ),
        ],
      ),
    );
  }
}

class _GridApp extends StatelessWidget {
  const _GridApp({required this.app, required this.onTap, required this.onLongPress, this.labelColor = DS.ink, this.pinned = false});
  final AppEntry app;
  final Color labelColor;
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
                        child: const Icon(Icons.push_pin, size: 11, color: DS.card),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                app.label,
                style: DS.iconLabel.copyWith(color: labelColor),
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
                            const Icon(Icons.north_east_rounded, size: 14, color: DS.card),
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
