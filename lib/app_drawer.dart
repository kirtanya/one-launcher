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
  });

  final List<AppEntry> apps;
  final Prefs prefs;
  final ScrollController scroll;
  final ValueListenable<double> expanded; // 0 = half screen, 1 = full screen
  final bool searching;
  final String query;
  final ValueChanged<AppEntry> onLaunch;
  final ValueChanged<bool> onCompact; // list scrolled up (true) or back down (false)

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

  List<AppEntry> _mostUsed(List<AppEntry> apps) {
    final byPkg = {for (final a in apps) a.package: a};
    final used = widget.prefs.launchCounts.entries.where((e) => byPkg.containsKey(e.key)).toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in used.take(_mostUsedCount)) byPkg[e.key]!];
  }

  // ---- Actions -------------------------------------------------------------

  void _longPress(AppEntry app) {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    showAppSheet(context, prefs: widget.prefs, app: app);
  }

  /// Accordion: opening one folder closes the other.
  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() => _openId = _openId == id ? null : id);
  }

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final d = n.scrollDelta ?? 0;
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
    final used = _mostUsed(apps);

    // The green hero card IS the Most used folder: always first, always open.
    final hero = _HeroCard(
      name: prefs.folderName(mostUsed),
      used: used,
      pinned: _pinned(apps),
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
            key: ValueKey('folder-${folder.id}'),
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
                  // Grab handle. As the sheet reaches full screen it also makes room for the status bar.
                  return ValueListenableBuilder<double>(
                    valueListenable: widget.expanded,
                    builder: (context, e, _) => Padding(
                      padding: EdgeInsets.only(top: DS.s12 + statusBar * e, bottom: DS.s12),
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(color: DS.onCanvasLine, borderRadius: BorderRadius.circular(3)),
                        ),
                      ),
                    ),
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
                builder: (context, e, _) => ColoredBox(color: DS.canvas.withValues(alpha: e)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Cards ------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.name, required this.used, required this.pinned, required this.onCustomise, required this.onLaunch, required this.onLongPress});

  final String name;
  final List<AppEntry> used, pinned;
  final VoidCallback onCustomise;
  final ValueChanged<AppEntry> onLaunch, onLongPress;

  @override
  Widget build(BuildContext context) {
    final tag = DS.meta.copyWith(color: DS.heroMuted, fontSize: 15);
    return OneCard(
      tone: CardTone.hero,
      padding: const EdgeInsets.fromLTRB(DS.s12, DS.s8, DS.s8, DS.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: DS.s8),
              MetaRow(icon: mostUsed.icon, text: name, color: DS.heroMuted),
              const Spacer(),
              CircleButton(icon: Icons.more_horiz_rounded, tone: CircleTone.soft, tooltip: 'Customise $name', onTap: onCustomise),
            ],
          ),
          if (used.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s8, DS.s8, DS.s12, DS.s16),
              child: Text('Apps you open most will gather here', style: DS.display),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth / 4;
                return Wrap(
                  children: [
                    for (final (i, a) in used.indexed)
                      SizedBox(
                        width: w,
                        child: PopIn(
                          delay: (i ~/ 4) * 0.06 + (i % 4) * 0.02,
                          child: _GridApp(app: a, labelColor: DS.heroInk, onTap: () => onLaunch(a), onLongPress: () => onLongPress(a)),
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: DS.s8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: DS.s8),
            child: CardDivider(color: DS.heroDivider),
          ),
          // Pinned apps as tags. Tap to open.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DS.s8),
            child: Wrap(
              spacing: DS.s16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: DS.tap),
                  child: const Icon(Icons.push_pin_outlined, size: 18, color: DS.heroMuted),
                ),
                if (pinned.isEmpty)
                  Text('Long-press any app to pin it here', style: tag)
                else
                  for (final a in pinned)
                    Pressable(
                      scale: 0.92,
                      child: InkWell(
                        onTap: () => onLaunch(a),
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: DS.tap),
                          child: Align(widthFactor: 1, child: Text('#${a.label.toLowerCase().replaceAll(' ', '')}', style: tag)),
                        ),
                      ),
                    ),
              ],
            ),
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
  const _GridApp({required this.app, required this.onTap, required this.onLongPress, this.labelColor = DS.ink});
  final AppEntry app;
  final Color labelColor;
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
              AppIcon(app, size: DS.appIcon),
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
                          Text(prefs.folderName(folderFor(a, prefs.folderOverrides)), style: DS.rowSub),
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
