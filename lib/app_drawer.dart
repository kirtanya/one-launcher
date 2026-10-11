import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'folders.dart';
import 'prefs.dart';
import 'sheets.dart';
import 'ui/components.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'widgets.dart';

/// The bottom sheet of the one-screen launcher: a pastel hero card, then one card per
/// folder of similar apps. Search swaps the folders for a single results card.
/// Scrolling is driven by the sheet's [scroll] controller, so the first drag expands the
/// sheet and only then scrolls the cards.
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.apps,
    required this.prefs,
    required this.scroll,
    required this.expanded,
    required this.onLaunch,
    required this.onWantFull,
  });

  final List<AppEntry> apps;
  final Prefs prefs;
  final ScrollController scroll;
  final ValueListenable<double> expanded; // 0 = half screen, 1 = full screen
  final ValueChanged<AppEntry> onLaunch;
  final VoidCallback onWantFull; // ask the sheet to expand (search)

  @override
  State<AppDrawer> createState() => AppDrawerState();
}

class AppDrawerState extends State<AppDrawer> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _open = <String>{}; // expanded folder ids
  bool _searching = false;

  bool get searching => _searching;

  /// Back to the resting state (after launching an app, Home, or collapsing).
  void reset() {
    _focus.unfocus();
    _query.clear();
    if (_searching) setState(() => _searching = false);
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---- Data ----------------------------------------------------------------

  List<AppEntry> get _visible {
    final hidden = widget.prefs.hidden.toSet();
    return widget.apps.where((a) => !hidden.contains(a.package)).toList();
  }

  String get _q => _query.text.trim().toLowerCase();

  List<AppEntry> get _results {
    final q = _q;
    // Hidden apps are still findable by search.
    int rank(AppEntry a) {
      final l = a.label.toLowerCase();
      if (l.startsWith(q)) return 0;
      if (l.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) return 1;
      if (l.contains(q)) return 2;
      return 3;
    }

    return widget.apps.where((a) => rank(a) < 3).toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  /// Pinned apps first, then the most-opened ones.
  List<AppEntry> _topApps(List<AppEntry> apps, int n) {
    final byPkg = {for (final a in apps) a.package: a};
    final picked = <AppEntry>[for (final p in widget.prefs.favourites) ?byPkg[p]];
    final used = widget.prefs.launchCounts.entries.where((e) => byPkg.containsKey(e.key)).toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in used) {
      if (!picked.contains(byPkg[e.key])) picked.add(byPkg[e.key]!);
    }
    return picked.take(n).toList();
  }

  // ---- Actions -------------------------------------------------------------

  void startSearch() {
    HapticFeedback.selectionClick();
    widget.onWantFull();
    setState(() => _searching = true);
    _focus.requestFocus();
  }

  void _stopSearch() => reset();

  void _onChanged(String _) {
    setState(() {});
    final r = _results;
    if (widget.prefs.autoOpenSingleMatch && _q.isNotEmpty && r.length == 1) widget.onLaunch(r.first);
  }

  void _onSubmit(String _) {
    final r = _results;
    if (_q.isNotEmpty && r.isNotEmpty) widget.onLaunch(r.first);
  }

  void _longPress(AppEntry app) {
    HapticFeedback.mediumImpact();
    _focus.unfocus();
    showAppSheet(context, prefs: widget.prefs, app: app);
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id));
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom + DS.s16;
    final statusBar = MediaQuery.paddingOf(context).top;
    final showResults = _searching && _q.isNotEmpty;
    final apps = _visible;
    final groups = groupApps(apps, widget.prefs.folderOverrides);

    final cards = <Widget>[
      if (_searching) _searchBar(),
      if (showResults)
        _ResultsCard(query: _query.text.trim(), results: _results, overrides: widget.prefs.folderOverrides, onTap: widget.onLaunch, onLongPress: _longPress)
      else if (!_searching) ...[
        _HeroCard(
          appCount: apps.length,
          folderCount: groups.length,
          newCount: apps.where((a) => a.installed > DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch).length,
          top: _topApps(apps, 4),
          onSearch: startSearch,
          onLaunch: widget.onLaunch,
        ),
        for (final (i, (folder, list)) in groups.indexed)
          _FolderCard(
            folder: folder,
            apps: list,
            open: _open.contains(folder.id),
            tone: i == groups.length - 1 && groups.length > 1 ? CardTone.muted : CardTone.white,
            onToggle: () => _toggle(folder.id),
            onLaunch: widget.onLaunch,
            onLongPress: _longPress,
          ),
      ],
    ];

    return Material(
      color: DS.canvas,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(DS.rSheet)),
      clipBehavior: Clip.antiAlias,
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
    );
  }

  Widget _searchBar() {
    return Padding(
      key: const ValueKey('search'),
      padding: const EdgeInsets.only(bottom: DS.s4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _query,
              focusNode: _focus,
              onChanged: _onChanged,
              onSubmitted: _onSubmit,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              cursorColor: DS.ink,
              style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Search ${widget.apps.length} apps',
                hintStyle: DS.rowSub,
                prefixIcon: const Icon(Icons.search_rounded, color: DS.ink),
                filled: true,
                fillColor: DS.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: DS.s4),
          CircleButton(icon: Icons.close_rounded, tone: CircleTone.onCanvas, tooltip: 'Close search', onTap: _stopSearch),
        ],
      ),
    );
  }
}

// ---- Cards ------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.appCount,
    required this.folderCount,
    required this.newCount,
    required this.top,
    required this.onSearch,
    required this.onLaunch,
  });

  final int appCount, folderCount, newCount;
  final List<AppEntry> top;
  final VoidCallback onSearch;
  final ValueChanged<AppEntry> onLaunch;

  @override
  Widget build(BuildContext context) {
    return OneCard(
      tone: CardTone.hero,
      padding: const EdgeInsets.fromLTRB(DS.pad, DS.s12, DS.s12, DS.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MetaRow(icon: Icons.push_pin_outlined, text: 'Pinned & most used', color: DS.heroMuted),
              const Spacer(),
              CircleButton(icon: Icons.search_rounded, tooltip: 'Search apps', onTap: onSearch),
            ],
          ),
          const SizedBox(height: DS.s12),
          Text('Your apps', style: DS.eyebrow.copyWith(color: DS.heroInk)),
          const SizedBox(height: DS.s8),
          Padding(
            padding: const EdgeInsets.only(right: DS.s8),
            child: Text.rich(
              TextSpan(
                style: DS.display,
                children: [
                  TextSpan(text: 'You have $appCount apps '),
                  if (newCount > 0) ...[
                    const WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox.shrink()),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: InlinePill('$newCount new', icon: Icons.trending_up_rounded),
                    ),
                    const TextSpan(text: ' '),
                  ],
                  TextSpan(text: 'in $folderCount folders'),
                ],
              ),
            ),
          ),
          const SizedBox(height: DS.s20),
          const CardDivider(color: DS.heroDivider),
          const SizedBox(height: DS.s4),
          // Most-used apps as tags. Tap to open.
          if (top.isEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: DS.tap),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Pin apps or open a few, they show up here', style: DS.meta.copyWith(color: DS.heroMuted, fontSize: 15)),
              ),
            )
          else
            Wrap(
              spacing: DS.s16,
              children: [
                for (final a in top)
                  Pressable(
                    scale: 0.92,
                    child: InkWell(
                      onTap: () => onLaunch(a),
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: DS.tap),
                        child: Align(
                          widthFactor: 1,
                          child: Text('#${a.label.toLowerCase().replaceAll(' ', '')}', style: DS.meta.copyWith(color: DS.heroMuted, fontSize: 15)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folder,
    required this.apps,
    required this.open,
    required this.tone,
    required this.onToggle,
    required this.onLaunch,
    required this.onLongPress,
  });

  final Folder folder;
  final List<AppEntry> apps;
  final bool open;
  final CardTone tone;
  final VoidCallback onToggle;
  final ValueChanged<AppEntry> onLaunch;
  final ValueChanged<AppEntry> onLongPress;

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
                              child: Text(folder.name, style: DS.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                        CardDivider(color: tone == CardTone.muted ? DS.hairline : DS.hairline),
                        const SizedBox(height: DS.s12),
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
  const _GridApp({required this.app, required this.onTap, required this.onLongPress});
  final AppEntry app;
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
              Text(app.label, style: DS.iconLabel, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.query, required this.results, required this.overrides, required this.onTap, required this.onLongPress});
  final String query;
  final List<AppEntry> results;
  final Map<String, String> overrides;
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
                          Text(folderFor(a, overrides).name, style: DS.rowSub),
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
