import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../folders.dart';
import '../prefs.dart';
import '../top/header_fonts.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';

/// One row of tiles: Favourites first, then one per smart folder (Watch & Listen, Games…).
class TvRow {
  const TvRow(this.id, this.title, this.apps);
  final String id;
  final String title;
  final List<AppEntry> apps;
}

/// The TV home screen: clock + buttons on top, rows of 16:9 app tiles below.
/// Driven by the remote: arrows move tile by tile; up/down jump rows and land on the tile
/// you last used in that row (like Google TV). The focused row slides to a fixed spot.
class TvHome extends StatefulWidget {
  const TvHome({super.key, required this.prefs});
  final Prefs prefs;

  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  List<AppEntry> _apps = const [];
  List<TvRow> _rows = const [];
  bool _loaded = false;

  final _v = ScrollController();
  final _h = <String, ScrollController>{}; // per row id
  final _nodes = <String, FocusNode>{};
  final _col = <String, int>{}; // last focused tile per row id
  int _row = 0; // focused row (-1 = the top buttons)

  static const _header = ['search', 'inputs', 'settings', 'customise'];

  Prefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    TvApps.instance.onAppsChanged = _load;
    TvApps.instance.onHomePressed = _home;
    prefs.addListener(_regroup);
    _load();
  }

  @override
  void dispose() {
    prefs.removeListener(_regroup);
    _v.dispose();
    for (final c in _h.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final apps = await TvApps.instance.list();
    if (!mounted) return;
    _apps = apps;
    _regroup();
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus(_rows.isEmpty ? -1 : 0, 0));
    }
  }

  void _regroup() {
    final hidden = prefs.hidden.toSet();
    final visible = [
      for (final a in _apps)
        if (!hidden.contains(a.package)) a,
    ];
    final byPkg = {for (final a in visible) a.package: a};
    // Favourites = the user's picks; until there are any, the Watch & Listen apps.
    var fav = [for (final p in prefs.favourites) ?byPkg[p]];
    final groups = groupApps(visible, prefs.folderOverrides, order: prefs.folderOrder);
    if (fav.isEmpty) {
      fav = [
        for (final (f, list) in groups)
          if (f.id == 'media') ...list,
      ].take(8).toList();
    }
    setState(() {
      _rows = [if (fav.isNotEmpty) TvRow('fav', 'Favourites', fav), for (final (f, list) in groups) TvRow(f.id, prefs.folderNames[f.id] ?? f.name, list)];
    });
  }

  /// Home on the remote: back to the first tile, close anything open.
  void _home() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _focus(_rows.isEmpty ? -1 : 0, 0);
  }

  // ---- Focus ---------------------------------------------------------------

  String _rowId(int r) => r < 0 ? 'header' : _rows[r].id;
  int _len(int r) => r < 0 ? _header.length : _rows[r].apps.length;
  String _key(int r, int i) => r < 0 ? 'h:${_header[i]}' : '${_rows[r].id}:${_rows[r].apps[i].package}';
  FocusNode _node(int r, int i) => _nodes.putIfAbsent(_key(r, i), () => FocusNode(debugLabel: _key(r, i)));

  void _focus(int r, int i) {
    if (r >= _rows.length || _len(r) == 0) return;
    _node(r, i.clamp(0, _len(r) - 1)).requestFocus();
  }

  bool _move(int r, int i, AxisDirection d) {
    switch (d) {
      case AxisDirection.left when i > 0:
        _focus(r, i - 1);
      case AxisDirection.right when i < _len(r) - 1:
        _focus(r, i + 1);
      case AxisDirection.up when r > -1:
        _focus(r - 1, _col[_rowId(r - 1)] ?? (r - 1 < 0 ? 0 : i));
      case AxisDirection.down when r < _rows.length - 1:
        _focus(r + 1, _col[_rowId(r + 1)] ?? (r < 0 ? 0 : i));
      default:
        return false;
    }
    return true;
  }

  void _onFocus(int r, int i) {
    _col[_rowId(r)] = i;
    if (_row != r) setState(() => _row = r);
    const dur = Duration(milliseconds: 320);
    const curve = Curves.easeOutCubic;
    // Vertical: the focused row slides up to where the first row sits; the top bar scrolls away.
    if (_v.hasClients) {
      final y = (r <= 0 ? 0.0 : r * TvDS.rowH).clamp(0.0, _v.position.maxScrollExtent);
      _v.animateTo(y, duration: dur, curve: curve);
    }
    // Horizontal: keep one tile peeking on the left so you can see there's more.
    final h = r < 0 ? null : _h[_rowId(r)];
    if (h != null && h.hasClients) {
      final x = ((i - 1) * (TvDS.tileW + TvDS.gap)).clamp(0.0, h.position.maxScrollExtent);
      h.animateTo(x, duration: dur, curve: curve);
    }
  }

  // ---- Actions -------------------------------------------------------------

  void _launch(AppEntry a) {
    HapticFeedback.selectionClick();
    TvApps.instance.launch(a.package);
  }

  void _appOptions(TvRow row, int i) {
    final a = row.apps[i];
    final fav = prefs.favourites.contains(a.package);
    void move(int by) {
      final list = [...prefs.favourites];
      final from = list.indexOf(a.package);
      final to = (from + by).clamp(0, list.length - 1);
      if (from < 0 || to == from) return;
      list.insert(to, list.removeAt(from));
      prefs.setFavourites(list);
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus(0, to));
    }

    showTvPanel(
      context,
      title: a.label,
      leading: _Art(app: a, width: 128),
      actions: [
        if (fav) ...[
          if (row.id == 'fav' && i > 0) TvAction(Icons.arrow_back_rounded, 'Move left', () => move(-1)),
          if (row.id == 'fav' && i < row.apps.length - 1) TvAction(Icons.arrow_forward_rounded, 'Move right', () => move(1)),
          TvAction(Icons.star_outline_rounded, 'Remove from Favourites', () => prefs.toggleFavourite(a.package)),
        ] else if (!prefs.favouritesFull)
          TvAction(Icons.star_rounded, 'Add to Favourites', () async {
            // The default Favourites (Watch & Listen) become real picks the first time you edit.
            if (prefs.favourites.isEmpty && row.id != 'fav' && _rows.firstOrNull?.id == 'fav') {
              await prefs.setFavourites([for (final x in _rows.first.apps) x.package]);
            }
            await prefs.toggleFavourite(a.package);
          }),
        TvAction(Icons.visibility_off_outlined, 'Hide', () => prefs.toggleHidden(a.package)),
        TvAction(Icons.info_outline_rounded, 'App info', () => TvApps.instance.appInfo(a.package)),
        if (!a.system) TvAction(Icons.delete_outline_rounded, 'Uninstall', () => TvApps.instance.uninstall(a.package), danger: true),
      ],
    );
  }

  void _headerAction(String id) => switch (id) {
    'search' => Navigator.of(context).push(_fade(TvSearch(apps: _rows.expand((r) => r.apps).toSet().toList(), onLaunch: _launch))),
    'inputs' => TvApps.instance.openInputs(),
    'settings' => TvApps.instance.openSettings(),
    _ => _customise(),
  };

  void _customise() {
    final hidden = [
      for (final a in _apps)
        if (prefs.hidden.contains(a.package)) a,
    ];
    showTvPanel(
      context,
      title: 'One Launcher TV',
      actions: [
        for (final (name, w, wd, sl) in clockPresets)
          TvAction(Icons.schedule_rounded, 'Clock: $name', () => prefs.setClockStyle(weight: w, width: wd, slant: sl), keepOpen: true),
        for (final a in hidden) TvAction(Icons.visibility_outlined, 'Show ${a.label}', () => prefs.toggleHidden(a.package)),
        TvAction(Icons.home_outlined, 'Make this the home screen', TvApps.instance.openHomeSettings),
      ],
    );
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // it's the home screen: Back jumps to the first tile instead
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _focus(_rows.isEmpty ? -1 : 0, 0);
      },
      child: Scaffold(
        backgroundColor: TvDS.canvas,
        body: DecoratedBox(
          // A soft glow of the theme colour from the top-left, so the canvas isn't flat.
          decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(-1, -1.2), radius: 1.4, colors: [DS.hero.withValues(alpha: .16), TvDS.canvas]),
          ),
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              controller: _v,
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    prefs: prefs,
                    buttons: [
                      for (final (i, id) in _header.indexed)
                        _CircleButton(
                          icon: switch (id) {
                            'search' => Icons.search_rounded,
                            'inputs' => Icons.input_rounded,
                            'settings' => Icons.settings_outlined,
                            _ => Icons.tune_rounded,
                          },
                          tooltip: switch (id) {
                            'search' => 'Search apps',
                            'inputs' => 'Inputs',
                            'settings' => 'TV settings',
                            _ => 'Customise',
                          },
                          focusNode: _node(-1, i),
                          onSelect: () => _headerAction(id),
                          onMove: (d) => _move(-1, i, d),
                          onFocus: () => _onFocus(-1, i),
                        ),
                    ],
                  ),
                  if (!_loaded) const SizedBox(height: TvDS.rowH),
                  for (final (r, row) in _rows.indexed) _buildRow(r, row),
                  // Room for the last row to slide up to the focus spot.
                  SizedBox(height: (c.maxHeight - TvDS.headerH - TvDS.rowH).clamp(0, double.infinity)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(int r, TvRow row) {
    final h = _h.putIfAbsent(row.id, ScrollController.new);
    return SizedBox(
      height: TvDS.rowH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(left: TvDS.safe.left),
            child: SizedBox(
              height: TvDS.rowTitleH,
              child: AnimatedDefaultTextStyle(
                duration: Motion.snapDuration,
                curve: Motion.settle,
                style: _row == r ? TvDS.rowTitleFocused : TvDS.rowTitle,
                child: Text(row.title),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: h,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none, // a focused tile grows past the row's box
              padding: EdgeInsets.symmetric(horizontal: TvDS.safe.left),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, a) in row.apps.indexed) ...[
                    if (i > 0) const SizedBox(width: TvDS.gap),
                    _Tile(
                      key: ValueKey(_key(r, i)),
                      app: a,
                      focusNode: _node(r, i),
                      onSelect: () => _launch(a),
                      onOptions: () => _appOptions(row, i),
                      onMove: (d) => _move(r, i, d),
                      onFocus: () => _onFocus(r, i),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

PageRoute<void> _fade(Widget page) => PageRouteBuilder(
  pageBuilder: (_, _, _) => page,
  transitionDuration: const Duration(milliseconds: 220),
  reverseTransitionDuration: const Duration(milliseconds: 160),
  transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
);

// ---- Header ------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.prefs, required this.buttons});
  final Prefs prefs;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TvDS.headerH,
      child: Padding(
        padding: EdgeInsets.fromLTRB(TvDS.safe.left, TvDS.safe.top, TvDS.safe.right, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Clock(prefs: prefs)),
            for (final (i, b) in buttons.indexed) ...[if (i > 0) const SizedBox(width: DS.s4), b],
          ],
        ),
      ),
    );
  }
}

/// Big time (the phone's variable clock font + the user's style) and the date.
class _Clock extends StatefulWidget {
  const _Clock({required this.prefs});
  final Prefs prefs;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _t;
  DateTime _now = DateTime.now();

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  void initState() {
    super.initState();
    _tick();
  }

  // Wake exactly on the next minute (no per-second rebuilds).
  void _tick() {
    final now = DateTime.now();
    _t = Timer(Duration(seconds: 60 - now.second, milliseconds: -now.millisecond + 20), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _tick();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.alwaysUse24HourFormatOf(context) ? _now.hour : (_now.hour % 12 == 0 ? 12 : _now.hour % 12);
    final time = '${h.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return ListenableBuilder(
      listenable: widget.prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: clockStyleOf(widget.prefs).copyWith(fontSize: TvDS.clockSize, height: 1, color: TvDS.ink, letterSpacing: -1),
          ),
          const SizedBox(height: DS.s4),
          Text('${_days[_now.weekday - 1]}, ${_now.day} ${_months[_now.month - 1]}', style: TvDS.date),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.tooltip, required this.focusNode, required this.onSelect, this.onMove, this.onFocus});
  final IconData icon;
  final String tooltip;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onMove: onMove,
        onFocus: onFocus,
        // Icons alone are hard to read from the sofa: the focused one says what it does.
        builder: (context, f) => SizedBox(
          width: 72,
          child: Column(
            children: [
              AnimatedScale(
                scale: f ? TvDS.focusScale : 1,
                duration: Motion.popDuration,
                curve: Motion.pop,
                child: AnimatedContainer(
                  duration: Motion.pressIn * 2,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: f ? TvDS.surfaceFocused : TvDS.surface, shape: BoxShape.circle),
                  child: Icon(icon, size: 26, color: f ? DS.ink : TvDS.ink),
                ),
              ),
              const SizedBox(height: DS.s8),
              AnimatedOpacity(
                opacity: f ? 1 : 0,
                duration: Motion.pressIn * 2,
                child: Text(tooltip, style: TvDS.hint, maxLines: 1, softWrap: false, overflow: TextOverflow.visible),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Tiles -------------------------------------------------------------------

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.app, required this.focusNode, required this.onSelect, required this.onOptions, this.onMove, this.onFocus});
  final AppEntry app;
  final FocusNode? focusNode;
  final VoidCallback onSelect, onOptions;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: app.label,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onLongSelect: onOptions,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => SizedBox(
          width: TvDS.tileW,
          child: Column(
            children: [
              const SizedBox(height: TvDS.rowPadTop),
              AnimatedScale(
                scale: f ? TvDS.focusScale : 1,
                duration: Motion.popDuration,
                curve: Motion.pop,
                child: AnimatedContainer(
                  duration: Motion.pressIn * 2,
                  width: TvDS.tileW,
                  height: TvDS.tileH,
                  // Ring + glow only on the focused tile (one blur on screen at a time).
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    border: Border.all(color: f ? TvDS.surfaceFocused : Colors.transparent, width: TvDS.focusRing),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    boxShadow: f ? const [BoxShadow(color: TvDS.glow, blurRadius: 18)] : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    child: _Art(app: app, width: TvDS.tileW),
                  ),
                ),
              ),
              const SizedBox(height: DS.s12),
              // Name under the focused tile — banners are just artwork; icon tiles already show it.
              AnimatedOpacity(
                opacity: f && (TvApps.instance.artNow(app.package)?.banner ?? false) ? 1 : 0,
                duration: Motion.pressIn * 2,
                child: Text(app.label, style: TvDS.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app's banner, or (no banner) its icon + name on a soft tile.
class _Art extends StatelessWidget {
  const _Art({required this.app, required this.width});
  final AppEntry app;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ready = TvApps.instance.artNow(app.package);
    return SizedBox(
      width: width,
      height: width * 9 / 16,
      child: ready != null
          ? _view(ready)
          : FutureBuilder<TvArt?>(future: TvApps.instance.art(app.package), builder: (context, s) => s.data != null ? _view(s.data!) : _fallback(null)),
    );
  }

  Widget _view(TvArt art) =>
      art.banner ? Image(image: art.image, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium) : _fallback(art.image);

  Widget _fallback(ImageProvider? icon) {
    final s = width / TvDS.tileW;
    return ColoredBox(
      color: TvDS.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 44 * s,
            child: icon != null
                ? Image(image: icon, gaplessPlayback: true, filterQuality: FilterQuality.medium)
                : DecoratedBox(
                    decoration: BoxDecoration(color: DS.hero, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        app.label.isEmpty ? '?' : app.label[0].toUpperCase(),
                        style: TvDS.tileName.copyWith(color: DS.heroInk, fontSize: 20 * s),
                      ),
                    ),
                  ),
          ),
          SizedBox(height: DS.s8 * s),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: DS.s8 * s),
            child: Text(
              app.label,
              style: TvDS.tileName.copyWith(fontSize: 13 * s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Side panel (options) ------------------------------------------------------

class TvAction {
  const TvAction(this.icon, this.label, this.onSelect, {this.danger = false, this.keepOpen = false});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool danger;
  final bool keepOpen; // e.g. clock presets: try several without reopening
}

/// Options slide in from the right, like the TV's own menus. Back closes.
Future<void> showTvPanel(BuildContext context, {required String title, Widget? leading, required List<TvAction> actions}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: const Color(0xFF1C1C1C),
        child: SizedBox(
          width: 380,
          height: double.infinity,
          child: FocusTraversalGroup(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(DS.s32, 40, DS.s32, 40),
              children: [
                if (leading != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(borderRadius: BorderRadius.circular(TvDS.rTile), child: leading),
                  ),
                  const SizedBox(height: DS.s16),
                ],
                Text(title, style: TvDS.panelTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: DS.s24),
                for (final (i, a) in actions.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DS.s8),
                    child: TvFocusable(
                      autofocus: i == 0,
                      onSelect: () {
                        if (!a.keepOpen) Navigator.pop(ctx);
                        a.onSelect();
                      },
                      builder: (context, f) => AnimatedContainer(
                        duration: Motion.pressIn * 2,
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                        decoration: BoxDecoration(color: f ? TvDS.surfaceFocused : Colors.transparent, borderRadius: BorderRadius.circular(26)),
                        child: Row(
                          children: [
                            Icon(a.icon, size: 22, color: f ? (a.danger ? DS.alert : DS.ink) : (a.danger ? DS.alert : TvDS.inkMuted)),
                            const SizedBox(width: DS.s16),
                            Expanded(
                              child: Text(
                                a.label,
                                style: TvDS.panelRow.copyWith(color: f ? DS.ink : TvDS.ink),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(.3, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: a, child: child),
    ),
  );
}

// ---- Search --------------------------------------------------------------------

/// Type with the TV keyboard (or voice), results fill in as tiles; ↓ moves into them.
class TvSearch extends StatefulWidget {
  const TvSearch({super.key, required this.apps, required this.onLaunch});
  final List<AppEntry> apps;
  final void Function(AppEntry) onLaunch;

  @override
  State<TvSearch> createState() => _TvSearchState();
}

class _TvSearchState extends State<TvSearch> {
  final _q = TextEditingController();
  final _first = FocusNode();

  @override
  void dispose() {
    _q.dispose();
    _first.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final results = q.isEmpty
        ? (widget.apps.toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())))
        : (widget.apps.where((a) => a.label.toLowerCase().contains(q)).toList()
            ..sort((a, b) => (a.label.toLowerCase().startsWith(q) ? 0 : 1).compareTo(b.label.toLowerCase().startsWith(q) ? 0 : 1)));
    return Scaffold(
      backgroundColor: TvDS.canvas,
      body: Padding(
        padding: TvDS.safe,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              // The field keeps ↓ for itself; send it to the results instead.
              onKeyEvent: (_, e) {
                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown && results.isNotEmpty) {
                  _first.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (results.isNotEmpty) _first.requestFocus();
                },
                style: TvDS.panelTitle,
                cursorColor: TvDS.ink,
                decoration: InputDecoration(
                  hintText: 'Search apps',
                  hintStyle: TvDS.panelTitle.copyWith(color: TvDS.inkMuted),
                  prefixIcon: const Icon(Icons.search_rounded, color: TvDS.inkMuted, size: 28),
                  filled: true,
                  fillColor: TvDS.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: DS.s16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(32), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(32),
                    borderSide: const BorderSide(color: TvDS.ink, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: DS.s16),
            Text(q.isEmpty ? 'All apps' : '${results.length} ${results.length == 1 ? 'app' : 'apps'}', style: TvDS.rowTitle),
            Expanded(
              child: SingleChildScrollView(
                clipBehavior: Clip.none,
                child: Wrap(
                  spacing: TvDS.gap,
                  children: [
                    for (final (i, a) in results.indexed)
                      _Tile(
                        key: ValueKey(a.package),
                        app: a,
                        focusNode: i == 0 ? _first : null,
                        onSelect: () {
                          Navigator.pop(context);
                          widget.onLaunch(a);
                        },
                        onOptions: () {},
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
