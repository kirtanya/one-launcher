import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'folders.dart';
import 'prefs.dart';
import 'sheets.dart';
import 'ui/components.dart';
import 'ui/ds.dart';
import 'widgets.dart';

/// The app view: greeting, a pastel hero card, then one card per folder of similar apps.
/// Search swaps the folders for a single results card.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key, required this.apps, required this.prefs, required this.onLaunch, required this.onDragClose, required this.onDragEnd});

  final List<AppEntry> apps;
  final Prefs prefs;
  final ValueChanged<AppEntry> onLaunch;
  final ValueChanged<double> onDragClose; // finger moved right by dx
  final ValueChanged<double> onDragEnd; // release velocity

  @override
  State<AppDrawer> createState() => AppDrawerState();
}

class AppDrawerState extends State<AppDrawer> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _open = <String>{}; // expanded folder ids
  bool _searching = false;

  /// Drawer finished opening.
  void opened() {}

  /// Drawer finished closing: start fresh next time.
  void closed() {
    _focus.unfocus();
    _query.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (_searching) setState(() => _searching = false);
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
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

  /// Most-opened apps; falls back to pinned, then alphabetical.
  List<AppEntry> _topApps(List<AppEntry> apps, int n) {
    final counts = widget.prefs.launchCounts;
    final byPkg = {for (final a in apps) a.package: a};
    final used = counts.entries.where((e) => byPkg.containsKey(e.key)).toList()..sort((a, b) => b.value.compareTo(a.value));
    final picked = <AppEntry>[for (final e in used) byPkg[e.key]!];
    for (final p in widget.prefs.favourites) {
      if (byPkg[p] != null && !picked.contains(byPkg[p])) picked.add(byPkg[p]!);
    }
    for (final a in apps) {
      if (!picked.contains(a)) picked.add(a);
    }
    return picked.take(n).toList();
  }

  // ---- Actions -------------------------------------------------------------

  void _startSearch() {
    HapticFeedback.selectionClick();
    setState(() => _searching = true);
    _focus.requestFocus();
  }

  void _stopSearch() {
    _focus.unfocus();
    _query.clear();
    setState(() => _searching = false);
  }

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
    final showResults = _searching && _q.isNotEmpty;
    final apps = _visible;
    final groups = groupApps(apps, widget.prefs.folderOverrides);

    final cards = <Widget>[
      if (showResults)
        _ResultsCard(query: _query.text.trim(), results: _results, overrides: widget.prefs.folderOverrides, onTap: widget.onLaunch, onLongPress: _longPress)
      else ...[
        _HeroCard(
          appCount: apps.length,
          folderCount: groups.length,
          newCount: apps.where((a) => a.installed > DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch).length,
          top: _topApps(apps, 3),
          onSearch: _startSearch,
          onSettings: () => showSettingsSheet(context, prefs: widget.prefs, apps: widget.apps),
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

    return GestureDetector(
      onHorizontalDragUpdate: (d) => widget.onDragClose(d.delta.dx),
      onHorizontalDragEnd: (d) => widget.onDragEnd(d.primaryVelocity ?? 0),
      child: Material(
        color: DS.canvas,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s24, DS.s16, DS.s16),
                child: AnimatedSwitcher(duration: DS.fast, child: _searching ? _searchBar() : _greeting()),
              ),
              Expanded(
                child: ListView.separated(
                  controller: _scroll,
                  physics: const ClampingScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(DS.gutter, 0, DS.gutter, bottom),
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(height: DS.stack),
                  itemBuilder: (_, i) => cards[i],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _greeting() {
    final h = DateTime.now().hour;
    final part = h < 5
        ? 'Hi night owl'
        : h < 12
        ? 'Good morning'
        : h < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Row(
      key: const ValueKey('greeting'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text('$part 👋\nWelcome back', style: DS.greeting)),
        const _BrandMark(),
      ],
    );
  }

  Widget _searchBar() {
    return Row(
      key: const ValueKey('search'),
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
    required this.onSettings,
    required this.onLaunch,
  });

  final int appCount, folderCount, newCount;
  final List<AppEntry> top;
  final VoidCallback onSearch, onSettings;
  final ValueChanged<AppEntry> onLaunch;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return OneCard(
      tone: CardTone.hero,
      padding: const EdgeInsets.fromLTRB(DS.pad, DS.s12, DS.s12, DS.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MetaRow(icon: Icons.calendar_today_outlined, text: '${now.day} ${_days[now.weekday - 1]}', color: DS.heroMuted),
              const Spacer(),
              CircleButton(icon: Icons.tune_rounded, tone: CircleTone.soft, tooltip: 'Settings', onTap: onSettings),
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
          Wrap(
            spacing: DS.s16,
            children: [
              for (final a in top)
                InkWell(
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
            duration: DS.medium,
            curve: DS.ease,
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
                                for (final a in apps)
                                  SizedBox(
                                    width: w,
                                    child: _GridApp(app: a, onTap: () => onLaunch(a), onLongPress: () => onLongPress(a)),
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
    return InkWell(
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

/// White circle with "1" and a pink dot, matching the app icon.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 56,
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(color: DS.hero, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              '1',
              style: DS.title.copyWith(color: DS.heroInk, fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: DS.dot,
                shape: BoxShape.circle,
                border: Border.all(color: DS.canvas, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
