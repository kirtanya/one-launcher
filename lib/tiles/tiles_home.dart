import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../quick_actions.dart';
import '../quick_chips.dart' show ShortcutIcon;
import '../photo_wallpaper.dart';
import '../prefs.dart';
import '../remote_sheet.dart';
import '../sheets.dart';
import '../top/header_fonts.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../widgets.dart';
import 'landing.dart';

/// The "Tiles" home view (Settings → Look → Home view): a Start screen of live tiles, and — one
/// swipe to the left — every app A–Z. The layout and navigation follow the Lumia launcher; the
/// colours are the theme's (Material).
class TilesHome extends StatefulWidget {
  const TilesHome({super.key, required this.prefs, required this.theme});
  final Prefs prefs;
  final OneTheme theme;

  @override
  State<TilesHome> createState() => _TilesHomeState();
}

/// One tile on Start: an app or a live tile ('clock'), small 1×1 / medium 2×2 / wide 4×2.
class TileSpec {
  const TileSpec(this.id, this.size, [this.colour]);
  final String id, size;

  /// Its own colour: null = the Start default, 'accent', 'app' (the icon's colour) or an ARGB hex.
  final String? colour;

  bool get isApp => id.startsWith('app:');
  String get package => id.substring(4);

  /// A quick action ('qa:' + a built-in "b:…" or app shortcut `s:<package>|<id>|<profile>`).
  bool get isAction => id.startsWith('qa:');
  String get action => id.substring(3);

  /// Whose icon colour "app colour" uses: the app, or the app behind a shortcut.
  String? get colourPackage => isApp ? package : (isAction && action.startsWith('s:') ? action.substring(2).split('|').first : null);
  (int, int) get span => switch (size) {
    's' => (1, 1),
    'w' => (4, 2),
    'l' => (4, 4),
    _ => (2, 2),
  };

  Map<String, dynamic> toJson() => {'id': id, 'size': size, 'colour': ?colour};
  static TileSpec fromJson(Map<String, dynamic> m) => TileSpec(m['id'] as String, m['size'] as String? ?? 'm', m['colour'] as String?);
  TileSpec resized(String s) => TileSpec(id, s, colour);
  TileSpec recoloured(String? c) => TileSpec(id, size, c);
}

/// Colours a tile can take (edit mode → palette), besides the accent and the app's own.
const tileSwatches = <Color>[
  Color(0xFF1565C0), Color(0xFF0097A7), Color(0xFF2E7D32), Color(0xFF689F38), Color(0xFFF9A825), Color(0xFFEF6C00), //
  Color(0xFFD84315), Color(0xFFC62828), Color(0xFFAD1457), Color(0xFF6A1B9A), Color(0xFF4527A0), Color(0xFF37474F),
];

/// A tile's colour (with the Start screen's transparency): its own, else the Start default.
Future<Color> tileColour(TileSpec t, Prefs prefs) async {
  final mode = t.colour ?? (prefs.tileColours == 'colourful' ? 'app' : 'accent');
  final Color c = switch (mode) {
    'accent' => tileAccent(),
    'app' => t.colourPackage != null ? await iconColour(t.colourPackage!) : tileAccent(),
    _ => Color(int.tryParse(mode, radix: 16) ?? tileAccent().toARGB32()),
  };
  return c.withValues(alpha: prefs.tileOpacity);
}

/// Places tiles on a 4-column grid in order, each at the first free spot it fits — small tiles
/// fill the gaps next to bigger ones, like the Lumia Start screen. → (tile, column, row).
List<(TileSpec, int, int)> packTiles(List<TileSpec> tiles, {int cols = 4}) {
  final used = <(int, int)>{};
  final out = <(TileSpec, int, int)>[];
  for (final t in tiles) {
    final (w, h) = t.span;
    var placed = false;
    for (var row = 0; !placed; row++) {
      for (var col = 0; col + w <= cols && !placed; col++) {
        var free = true;
        for (var x = col; x < col + w && free; x++) {
          for (var y = row; y < row + h && free; y++) {
            if (used.contains((x, y))) free = false;
          }
        }
        if (!free) continue;
        for (var x = col; x < col + w; x++) {
          for (var y = row; y < row + h; y++) {
            used.add((x, y));
          }
        }
        out.add((t, col, row));
        placed = true;
      }
    }
  }
  return out;
}

/// The tiles' accent: the theme's accent made deep and saturated enough to carry white glyphs.
Color tileAccent() {
  final h = HSLColor.fromColor(DS.hero);
  return h.withSaturation(math.max(h.saturation, .5)).withLightness(.38).toColor();
}

/// Ping to bring Start into view (top, not editing) — Settings → Home view previews on it.
final showTilesStart = _Signal();

class _Signal extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _TilesHomeState extends State<TilesHome> with WidgetsBindingObserver {
  Prefs get prefs => widget.prefs;
  final _pages = PageController();
  final _start = ScrollController();
  List<AppEntry> _apps = const [];
  bool _editing = false;
  final _searchFocus = FocusNode();
  double _pull = 0; // pull-down on Start past the top, in px
  String? _selected; // the tile showing its edit controls

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    prefs.addListener(_rebuild);
    showTilesStart.addListener(_showStart);
    Apps.instance.onAppsChanged = _load;
    Apps.instance.onHomePressed = _home;
    _load();
    startLanding.play();
  }

  /// Plays the landing animation of whichever page shows.
  void _land() => ((_pages.hasClients && (_pages.page ?? 0) > .5) ? listLanding : startLanding).play();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    prefs.removeListener(_rebuild);
    showTilesStart.removeListener(_showStart);
    _pages.dispose();
    _searchFocus.dispose();
    _start.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _land(); // back on home: the tiles / rows come in again
      _load();
      widget.theme.refreshSystem();
    }
  }

  void _rebuild() {
    // "Reset Start" in Settings clears the tiles: lay the starting ones out again right away.
    if (prefs.tiles == null && _apps.isNotEmpty) {
      prefs.setTiles([for (final t in _defaults()) t.toJson()]);
      return;
    }
    setState(() {});
  }

  Future<void> _load() async {
    final apps = await Apps.instance.list();
    if (!mounted) return;
    setState(() => _apps = apps);
    if (prefs.tiles == null && apps.isNotEmpty) await prefs.setTiles([for (final t in _defaults()) t.toJson()]);
  }

  /// First time on Tiles: a clock, then pinned + most-used apps in a mix of sizes.
  List<TileSpec> _defaults() {
    final byPkg = {for (final a in _apps) a.package: a};
    final picks = <String>[
      for (final p in prefs.favourites)
        if (byPkg.containsKey(p)) p,
    ];
    final used = prefs.launchCounts.entries.where((e) => byPkg.containsKey(e.key)).toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in used) {
      if (!picks.contains(e.key)) picks.add(e.key);
    }
    for (final a in _apps) {
      if (picks.length >= 10) break;
      if (!picks.contains(a.package)) picks.add(a.package);
    }
    const sizes = ['m', 's', 's', 's', 's', 'm', 's', 's', 's', 's'];
    return [const TileSpec('clock', 'w'), for (final (i, p) in picks.take(10).indexed) TileSpec('app:$p', sizes[i])];
  }

  List<TileSpec> get _tiles {
    final known = {for (final a in _apps) a.package};
    return [
      for (final m in prefs.tiles ?? const <Map<String, dynamic>>[])
        if (TileSpec.fromJson(m) case final t when !t.isApp || known.contains(t.package)) t,
    ];
  }

  Future<void> _save(List<TileSpec> tiles) => prefs.setTiles([for (final t in tiles) t.toJson()]);

  bool isPinned(String package) => _tiles.any((t) => t.isApp && t.package == package);

  Future<void> _pin(AppEntry a) async {
    HapticFeedback.mediumImpact();
    await _save([..._tiles, TileSpec('app:${a.package}', 'm')]);
  }

  Future<void> _unpin(String id) async {
    HapticFeedback.selectionClick();
    await _save([
      for (final t in _tiles)
        if (t.id != id) t,
    ]);
    if (_selected == id) _selected = null;
  }

  Future<void> _resize(TileSpec t) async {
    HapticFeedback.selectionClick();
    // small → medium → wide → large → small (the clock has no small).
    final next = switch (t.size) {
      's' => 'm',
      'm' => 'w',
      'w' => 'l',
      _ => t.id == 'clock' ? 'm' : 's',
    };
    await _save([for (final x in _tiles) x.id == t.id ? x.resized(next) : x]);
  }

  Future<void> _recolour(TileSpec t) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DS.card,
      showDragHandle: true,
      builder: (ctx) => _Palette(current: t.colour, app: t.colourPackage),
    );
    if (picked == null) return;
    await _save([for (final x in _tiles) x.id == t.id ? x.recoloured(picked == 'default' ? null : picked) : x]);
  }

  /// Puts [dragged] where [target] is (moving forward lands after it, back before it); '' = the end.
  Future<void> _move(String dragged, String target) async {
    final list = [..._tiles];
    final from = list.indexWhere((t) => t.id == dragged);
    final to = target.isEmpty ? list.length - 1 : list.indexWhere((t) => t.id == target);
    if (from < 0 || to < 0 || from == to) return;
    list.insert(to, list.removeAt(from));
    HapticFeedback.selectionClick();
    await _save(list);
  }

  void _launch(AppEntry a) {
    prefs.recordLaunch(a.package);
    Apps.instance.launch(a.package);
  }

  void _home() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() {
      _editing = false;
      _selected = null;
    });
    if (_pages.hasClients) _pages.animateToPage(0, duration: Motion.snapDuration, curve: Motion.settle);
    if (_start.hasClients) _start.animateTo(0, duration: Motion.snapDuration, curve: Motion.settle);
  }

  /// Pull down on Start (Settings → pull to search): all apps with the search box focused.
  bool _onStartScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || _editing || !prefs.pullToSearch) return false;
    if (n is OverscrollNotification && n.overscroll < 0 && n.dragDetails != null) {
      final was = _pull;
      _pull -= n.overscroll;
      if (was < _pullAt && _pull >= _pullAt) HapticFeedback.selectionClick(); // far enough
    } else if (n is ScrollEndNotification || (n is ScrollUpdateNotification && n.metrics.pixels > 0)) {
      if (_pull >= _pullAt) _openSearch();
      _pull = 0;
    }
    return false;
  }

  static const _pullAt = 72.0;

  Future<void> _openSearch() async {
    await _pages.animateToPage(1, duration: Motion.snapDuration, curve: Motion.settle);
    if (mounted) _searchFocus.requestFocus();
  }

  void _showStart() {
    setState(() {
      _editing = false;
      _selected = null;
    });
    if (_pages.hasClients) _pages.animateToPage(0, duration: Motion.snapDuration, curve: Motion.settle);
    if (_start.hasClients) _start.animateTo(0, duration: Motion.snapDuration, curve: Motion.settle);
  }

  void _settings() {
    HapticFeedback.mediumImpact();
    showSettingsSheet(context, prefs: prefs, apps: _apps, theme: widget.theme);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (_editing) {
          return setState(() {
            _editing = false;
            _selected = null;
          });
        }
        if (_pages.hasClients && (_pages.page ?? 0) > .5) _pages.animateToPage(0, duration: Motion.snapDuration, curve: Motion.settle);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(child: PhotoWallpaper(prefs: prefs, fullScreen: true)), // Start shows the whole screen
            // Tiles want calm behind them: the wallpaper dims more than on the classic view.
            IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: (prefs.wallpaperDim + .35).clamp(0.0, .85))),
            ),
            PageView(
              controller: _pages,
              onPageChanged: (i) => (i == 0 ? startLanding : listLanding).play(),
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _onStartScroll,
                  child: _StartPage(
                    tiles: _tiles,
                    apps: {for (final a in _apps) a.package: a},
                    scroll: _start,
                    editing: _editing,
                    selected: _selected,
                    prefs: prefs,
                    onLaunch: _launch,
                    onOpenClock: () {
                      final clock = _apps.where((a) => a.label.toLowerCase() == 'clock').firstOrNull;
                      if (clock != null) _launch(clock);
                    },
                    onEdit: (id) => setState(() {
                      if (!_editing) HapticFeedback.mediumImpact();
                      _editing = true;
                      _selected = id;
                    }),
                    onDone: () => setState(() {
                      _editing = false;
                      _selected = null;
                    }),
                    onUnpin: _unpin,
                    onResize: _resize,
                    onRecolour: _recolour,
                    onMove: _move,
                    onAllApps: () => _pages.animateToPage(1, duration: Motion.snapDuration, curve: Motion.settle),
                    onSettings: _settings,
                  ),
                ),
                _AppListPage(
                  focus: _searchFocus,
                  apps: _apps,
                  prefs: prefs,
                  isPinned: isPinned,
                  onLaunch: _launch,
                  onPin: _pin,
                  onUnpin: (a) => _unpin('app:${a.package}'),
                  onSettings: _settings,
                  onRemote: prefs.remoteButton ? () => showTvRemote(context, prefs: prefs) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Start ----------------------------------------------------------------------------------

class _StartPage extends StatelessWidget {
  const _StartPage({
    required this.tiles,
    required this.apps,
    required this.scroll,
    required this.editing,
    required this.selected,
    required this.prefs,
    required this.onLaunch,
    required this.onOpenClock,
    required this.onEdit,
    required this.onDone,
    required this.onUnpin,
    required this.onResize,
    required this.onRecolour,
    required this.onMove,
    required this.onAllApps,
    required this.onSettings,
  });

  final List<TileSpec> tiles;
  final Map<String, AppEntry> apps;
  final ScrollController scroll;
  final bool editing;
  final Prefs prefs;
  final String? selected;
  final ValueChanged<AppEntry> onLaunch;
  final VoidCallback onOpenClock, onDone, onAllApps, onSettings;
  final ValueChanged<String> onEdit, onUnpin;
  final ValueChanged<TileSpec> onResize, onRecolour;
  final Future<void> Function(String dragged, String target) onMove;

  static const gap = 6.0, side = 12.0;
  static final _grid = GlobalKey();
  static var _lastMove = DateTime(0);

  /// While a tile is dragged: the cell under its centre decides where it goes — onto a tile
  /// takes that tile's place (the rest reflow), empty space after the last tile = the end.
  void _hover(DragTargetDetails<String> d, List<(TileSpec, int, int)> placed, double unit, int cols) {
    final box = _grid.currentContext?.findRenderObject() as RenderBox?;
    final dragged = placed.where((p) => p.$1.id == d.data).firstOrNull;
    if (box == null || dragged == null) return;
    final (w, h) = (dragged.$1.span.$1 * (unit + gap), dragged.$1.span.$2 * (unit + gap));
    final p = box.globalToLocal(d.offset + Offset(w / 2, h / 2));
    if (p.dy < 0 || p.dx < 0) return;
    final col = (p.dx / (unit + gap)).floor().clamp(0, cols - 1), row = (p.dy / (unit + gap)).floor();
    String? target;
    for (final (t, c, r) in placed) {
      if (col >= c && col < c + t.span.$1 && row >= r && row < r + t.span.$2) target = t.id;
    }
    if (target == null) {
      final (last, lc, lr) = placed.last;
      final pastEnd = row >= lr + last.span.$2 || (row >= lr && col >= lc + last.span.$1);
      if (!pastEnd || last.id == d.data) return;
      target = '';
    }
    if (target == d.data) return;
    final now = DateTime.now();
    if (now.difference(_lastMove) < const Duration(milliseconds: 220)) return; // let the reflow settle
    _lastMove = now;
    onMove(d.data, target);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final cols = prefs.tileColumns;
        final unit = (c.maxWidth - 2 * side - (cols - 1) * gap) / cols;
        final placed = packTiles(tiles, cols: cols);
        final rows = placed.fold<int>(0, (m, p) => math.max(m, p.$3 + p.$1.span.$2));
        final height = rows == 0 ? 0.0 : rows * unit + (rows - 1) * gap;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: editing ? onDone : null,
          onLongPress: editing ? null : onSettings, // long-press empty space: settings, like the classic view
          child: SingleChildScrollView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(), // pull down to search even when Start fits
            padding: EdgeInsets.fromLTRB(side, pad.top + DS.s24, side, pad.bottom + DS.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DragTarget<String>(
                  onWillAcceptWithDetails: (_) => true,
                  onMove: (d) => _hover(d, placed, unit, cols),
                  builder: (context, _, _) => SizedBox(
                    key: _grid,
                    height: height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final (t, col, row) in placed)
                          AnimatedPositioned(
                            key: ValueKey(t.id),
                            duration: Motion.snapDuration,
                            curve: Motion.settle,
                            left: col * (unit + gap),
                            top: row * (unit + gap),
                            width: t.span.$1 * unit + (t.span.$1 - 1) * gap,
                            height: t.span.$2 * unit + (t.span.$2 - 1) * gap,
                            child: Landed(
                              landing: startLanding,
                              style: prefs.tileAnim,
                              // Lumia's sweep: column by column, a little later each row.
                              delay: Duration(milliseconds: 40 * col + 22 * row),
                              // Long Start: tiles below the fold come in as you scroll to them.
                              scroll: scroll,
                              top: pad.top + DS.s24 + row * (unit + gap),
                              bottom: pad.top + DS.s24 + (row + t.span.$2) * (unit + gap),
                              child: _EditableTile(
                                tile: t,
                                editing: editing,
                                selected: selected == t.id,
                                onEdit: () => onEdit(t.id),
                                onUnpin: () => onUnpin(t.id),
                                onResize: () => onResize(t),
                                onRecolour: () => onRecolour(t),
                                child: t.isApp
                                    ? _AppTile(
                                        app: apps[t.package]!,
                                        tile: t,
                                        prefs: prefs,
                                        onTap: editing ? () => onEdit(t.id) : () => onLaunch(apps[t.package]!),
                                      )
                                    : t.isAction
                                    ? _ActionTile(tile: t, prefs: prefs, onTap: editing ? () => onEdit(t.id) : null)
                                    : _ClockTile(tile: t, prefs: prefs, onTap: editing ? () => onEdit(t.id) : onOpenClock),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: DS.s16),
                Row(
                  children: [
                    if (editing) ...[
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: tileAccent(), foregroundColor: Colors.white, shape: const StadiumBorder()),
                        onPressed: onDone,
                        child: const Text('Done'),
                      ),
                      const SizedBox(width: DS.s8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DS.onWallpaper,
                          side: const BorderSide(color: DS.onWallpaper, width: 1.5),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () => addActionTile(context, prefs),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add tile'),
                      ),
                    ],
                    const Spacer(),
                    // The Lumia arrow: all apps (or swipe left).
                    Tooltip(
                      message: 'All apps',
                      child: Pressable(
                        scale: .9,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onAllApps,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: DS.onWallpaper, width: 2),
                            ),
                            child: const Icon(Icons.arrow_forward_rounded, color: DS.onWallpaper),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Edit mode around a tile: others shrink a little; the selected one shows unpin (top-right)
/// and resize (bottom-right); drag a tile onto another to put it there.
class _EditableTile extends StatelessWidget {
  const _EditableTile({
    required this.tile,
    required this.editing,
    required this.selected,
    required this.onEdit,
    required this.onUnpin,
    required this.onResize,
    required this.onRecolour,
    required this.child,
  });

  final TileSpec tile;
  final bool editing, selected;
  final VoidCallback onEdit, onUnpin, onResize, onRecolour;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedScale(
      duration: Motion.snapDuration,
      curve: Motion.settle,
      scale: editing && !selected ? .9 : 1,
      child: AnimatedOpacity(duration: Motion.snapDuration, opacity: editing && !selected ? .75 : 1, child: child),
    );
    // One tree in both modes: entering edit mode mid long-press must not rebuild the tile away
    // under the finger.
    // Long-press picks the tile up straight away (and enters edit mode); in edit mode a short
    // hold is enough. The grid reflows live under the finger (see _StartPage).
    return LayoutBuilder(
      builder: (context, box) => Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          LongPressDraggable<String>(
            data: tile.id,
            delay: editing ? const Duration(milliseconds: 150) : kLongPressTimeout,
            feedback: SizedBox(
              width: box.maxWidth,
              height: box.maxHeight,
              child: Opacity(opacity: .85, child: child),
            ),
            childWhenDragging: Opacity(opacity: .3, child: body),
            onDragStarted: () {
              HapticFeedback.mediumImpact();
              if (!editing) onEdit();
            },
            child: body,
          ),
          if (editing && selected) ...[
            Positioned(
              right: -8,
              top: -8,
              child: _EditButton(icon: Icons.push_pin_outlined, tooltip: 'Unpin', onTap: onUnpin),
            ),
            Positioned(
              right: -8,
              bottom: -8,
              child: _EditButton(icon: Icons.open_in_full_rounded, tooltip: 'Resize', onTap: onResize),
            ),
            Positioned(
              left: -8,
              bottom: -8,
              child: _EditButton(icon: Icons.palette_outlined, tooltip: 'Tile colour', onTap: onRecolour),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: DS.onWallpaper,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(dimension: 32, child: Icon(icon, size: 18, color: Colors.black)),
      ),
    ),
  );
}

/// An app tile: its themed glyph (white) — or its full icon (setting, or no glyph) — on the
/// tile colour; bigger tiles carry the name (setting).
class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.tile, required this.prefs, required this.onTap});
  final AppEntry app;
  final TileSpec tile;
  final Prefs prefs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final glyph = switch (tile.size) {
      's' => 30.0,
      'w' => 44.0,
      'l' => 72.0,
      _ => 48.0,
    };
    return Builder(
      builder: (tileContext) => _TileFace(
        tile: tile,
        prefs: prefs,
        onTap: () {
          Apps.instance.markLaunchFrom(tileContext);
          onTap();
        },
        child: Stack(
          children: [
            Center(
              child: prefs.tileIcons == 'icon' ? AppIcon(app, size: glyph) : TileGlyph(app: app, size: glyph),
            ),
            if (tile.size != 's' && prefs.tileLabels)
              Positioned(
                left: 8,
                bottom: 6,
                right: 8,
                child: Text(
                  app.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The tile's square in its colour (resolved async for "the app's own colour").
class _TileFace extends StatelessWidget {
  const _TileFace({required this.tile, required this.prefs, required this.onTap, required this.child});
  final TileSpec tile;
  final Prefs prefs;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Pressable(
    scale: .95,
    child: FutureBuilder<Color>(
      future: tileColour(tile, prefs),
      builder: (context, snap) => Material(
        color: snap.data ?? tileAccent().withValues(alpha: prefs.tileOpacity),
        borderRadius: BorderRadius.circular(prefs.tileRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, splashColor: Colors.white24, child: child),
      ),
    ),
  );
}

/// Edit mode → palette: the Start default, accent, the app's own colour, or a Material colour.
class _Palette extends StatelessWidget {
  const _Palette({required this.current, required this.app});
  final String? current;
  final String? app; // null for live tiles (no "app colour")

  @override
  Widget build(BuildContext context) {
    Widget swatch(String value, Color colour, {String? label, IconData? icon}) {
      final on = (current ?? 'default') == value;
      return Tooltip(
        message: label ?? 'Colour',
        child: InkWell(
          onTap: () => Navigator.pop(context, value),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colour,
              border: on ? Border.all(color: DS.ink, width: 3) : null,
            ),
            child: icon == null ? null : Icon(icon, color: Colors.white),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeader(title: 'Tile colour'),
            const SizedBox(height: DS.s16),
            Wrap(
              spacing: DS.s8,
              runSpacing: DS.s8,
              children: [
                swatch('default', DS.cardMuted, label: 'Start default', icon: Icons.auto_awesome_rounded),
                swatch('accent', tileAccent(), label: 'Accent'),
                if (app != null) swatch('app', DS.inkMuted, label: 'App colour', icon: Icons.colorize_rounded),
                for (final c in tileSwatches) swatch(c.toARGB32().toRadixString(16), c),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick-action tile: the action's icon and name; tap runs it. Flashlight shows when it's on.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.tile, required this.prefs, required this.onTap});
  final TileSpec tile;
  final Prefs prefs;
  final VoidCallback? onTap; // null: run the action

  @override
  Widget build(BuildContext context) {
    final id = tile.action;
    final builtIn = builtInActions[id];
    final label = builtIn?.$1 ?? (prefs.quickLabels[id]?.split('|').first ?? 'Shortcut');
    final size = switch (tile.size) {
      's' => 30.0,
      'w' => 44.0,
      'l' => 72.0,
      _ => 48.0,
    };
    Widget face(bool on) => _TileFace(
      tile: tile,
      prefs: prefs,
      onTap:
          onTap ??
          () async {
            HapticFeedback.selectionClick();
            if (id == 'b:remote') return showTvRemote(context, prefs: prefs); // ours, not the phone's
            final ok = await Apps.instance.quickAction(id);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn’t open “$label” on this phone'), behavior: SnackBarBehavior.floating));
            }
          },
      child: Stack(
        children: [
          Center(
            child: builtIn != null
                ? Icon(on ? Icons.flashlight_on_rounded : builtIn.$2, size: size, color: Colors.white)
                : ShortcutIcon(id: id, size: size, color: Colors.white),
          ),
          if (on) // lit: a white ring inside the tile
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(prefs.tileRadius),
                ),
              ),
            ),
          if (tile.size != 's' && prefs.tileLabels)
            Positioned(
              left: 8,
              bottom: 6,
              right: 8,
              child: Text(
                on ? '$label · on' : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
    if (id != 'b:torch') return face(false);
    return ValueListenableBuilder<bool>(valueListenable: Apps.instance.torchOn, builder: (context, on, _) => face(on));
  }
}

/// Pick a quick action (built-in or an app's shortcut) and put it on Start as a small tile.
Future<void> addActionTile(BuildContext context, Prefs prefs) async {
  final onStart = {for (final m in prefs.tiles ?? const <Map<String, dynamic>>[]) m['id'] as String};
  final picked = await showOneSheetWith(context, builder: (ctx) => _ActionPicker(onStart: onStart));
  if (picked is! (String, String, String)) return;
  final (id, label, app) = picked;
  if (id.startsWith('s:')) await prefs.nameQuickAction(id, label, app);
  HapticFeedback.mediumImpact();
  await prefs.setTiles([...?prefs.tiles, TileSpec('qa:$id', 's').toJson()]);
}

class _ActionPicker extends StatefulWidget {
  const _ActionPicker({required this.onStart});
  final Set<String> onStart;

  @override
  State<_ActionPicker> createState() => _ActionPickerState();
}

class _ActionPickerState extends State<_ActionPicker> {
  final _shortcuts = Apps.instance.shortcuts();
  var _query = '';

  @override
  Widget build(BuildContext context) {
    Widget row(String id, Widget icon, String title, String sub, String app) {
      final added = widget.onStart.contains('qa:$id');
      return InkWell(
        onTap: added ? null : () => Navigator.pop(context, (id, title, app)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: DS.s12),
          child: Row(
            children: [
              SizedBox.square(dimension: 28, child: Center(child: icon)),
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
                    Text(added ? 'On Start' : sub, style: DS.rowSub.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              Icon(added ? Icons.check_rounded : Icons.add_rounded, color: added ? DS.inkMuted : DS.ink),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s12),
          child: SheetHeader(title: 'Add a tile', subtitle: 'Quick actions and app shortcuts'),
        ),
        SheetSearchField(hint: 'Search actions & app shortcuts', onChanged: (q) => setState(() => _query = q)),
        for (final MapEntry(key: id, value: (name, icon)) in builtInActions.entries)
          if (matchesQuery(_query, [name])) row(id, Icon(icon, color: DS.ink), name, 'Quick action', ''),
        FutureBuilder<List<AppShortcut>?>(
          future: _shortcuts,
          builder: (context, snap) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final sc in snap.data ?? const <AppShortcut>[])
                if (matchesQuery(_query, [sc.label, sc.app]))
                  row(sc.id, ShortcutIcon(id: sc.id, size: 26, color: DS.ink), sc.label, sc.work ? '${sc.app} · Work' : sc.app, sc.app),
            ],
          ),
        ),
        const SizedBox(height: DS.s16),
      ],
    );
  }
}

/// The app's white themed glyph, else its normal icon.
class TileGlyph extends StatelessWidget {
  const TileGlyph({super.key, required this.app, required this.size});
  final AppEntry app;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: FutureBuilder<Uint8List?>(
      future: Apps.instance.monoIcon(app.package),
      builder: (context, snap) => snap.connectionState != ConnectionState.done
          ? const SizedBox.shrink()
          : snap.data != null
          ? withWorkBadge(app, size, Image.memory(snap.data!, gaplessPlayback: true, filterQuality: FilterQuality.medium))
          : AppIcon(app, size: size),
    ),
  );
}

/// An app icon's main colour, deepened for white text — for colourful tiles. Cached.
final _colours = <String, Future<Color>>{};
Future<Color> iconColour(String package) => _colours.putIfAbsent(package, () async {
  final bytes = await Apps.instance.icon(package);
  if (bytes == null) return tileAccent();
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24, targetHeight: 24);
  final img = (await codec.getNextFrame()).image;
  final data = await img.toByteData();
  img.dispose();
  if (data == null) return tileAccent();
  // Average the colourful, opaque pixels (ignore white/black/grey backgrounds).
  var r = 0.0, g = 0.0, b = 0.0, n = 0;
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    final a = data.getUint8(i + 3);
    if (a < 200) continue;
    final c = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    final hsl = HSLColor.fromColor(c);
    if (hsl.saturation < .25 || hsl.lightness < .12 || hsl.lightness > .92) continue;
    r += c.r;
    g += c.g;
    b += c.b;
    n++;
  }
  if (n < 8) return tileAccent();
  final avg = HSLColor.fromColor(Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n));
  return avg.withSaturation(math.max(avg.saturation, .45)).withLightness(.4).toColor();
});

/// Live clock tile: big time, the day and date; updates every minute. Tap opens Clock.
class _ClockTile extends StatefulWidget {
  const _ClockTile({required this.tile, required this.prefs, required this.onTap});
  final TileSpec tile;
  final Prefs prefs;
  final VoidCallback onTap;

  @override
  State<_ClockTile> createState() => _ClockTileState();
}

class _ClockTileState extends State<_ClockTile> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    _timer = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0'), m = now.minute.toString().padLeft(2, '0');
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final p = widget.prefs;
    final style = clockStyle(
      weight: p.tileClockWeight,
      width: p.tileClockWidth,
      slant: p.tileClockSlant,
      round: p.tileClockRound,
    ).copyWith(color: Colors.white, shadows: const []);
    return _TileFace(
      tile: widget.tile,
      prefs: widget.prefs,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text('$h:$m', style: style),
              ),
            ),
            if (widget.tile.size != 'm') ...[
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    days[now.weekday - 1],
                    style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '${now.day} ${months[now.month - 1]}',
                    style: const TextStyle(fontFamily: DS.font, color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- All apps -------------------------------------------------------------------------------

class _AppListPage extends StatefulWidget {
  const _AppListPage({
    required this.apps,
    required this.prefs,
    required this.isPinned,
    required this.onLaunch,
    required this.onPin,
    required this.onUnpin,
    required this.onSettings,
    required this.onRemote,
    required this.focus,
  });

  final List<AppEntry> apps;
  final FocusNode focus;
  final Prefs prefs;
  final bool Function(String package) isPinned;
  final ValueChanged<AppEntry> onLaunch, onPin, onUnpin;
  final VoidCallback onSettings;
  final VoidCallback? onRemote;

  @override
  State<_AppListPage> createState() => _AppListPageState();
}

class _AppListPageState extends State<_AppListPage> {
  static const rowH = 60.0;
  final _list = ScrollController();
  String _query = '';
  bool _jump = false; // the A–Z jump grid is up

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  static String _letter(AppEntry a) {
    final c = a.label.isEmpty ? '#' : a.label[0].toUpperCase();
    return RegExp('[A-Z]').hasMatch(c) ? c : '#';
  }

  /// Rows: letter headers ('#', 'A'…) and apps, in order.
  List<Object> _rows() {
    final q = _query.trim();
    final apps = q.isEmpty
        ? widget.apps
        : [
            for (final a in widget.apps)
              if (matchesQuery(q, [a.label])) a,
          ];
    if (q.isNotEmpty) return apps;
    final sorted = [...apps]
      ..sort((a, b) {
        final la = _letter(a), lb = _letter(b);
        if (la != lb) return la == '#' ? -1 : (lb == '#' ? 1 : la.compareTo(lb));
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    final out = <Object>[];
    String? last;
    for (final a in sorted) {
      final l = _letter(a);
      if (l != last) out.add(l);
      out.add(a);
      last = l;
    }
    return out;
  }

  void _menu(AppEntry a) {
    HapticFeedback.mediumImpact();
    final pinned = widget.isPinned(a.package);
    showOneSheet(
      context,
      header: SheetHeader(title: a.label, leading: AppIcon(a, size: 40)),
      actions: [
        SheetAction(pinned ? Icons.push_pin : Icons.push_pin_outlined, pinned ? 'Unpin from Start' : 'Pin to Start', () {
          Navigator.pop(context);
          pinned ? widget.onUnpin(a) : widget.onPin(a);
        }),
        SheetAction(Icons.info_outline_rounded, 'App info', () {
          Navigator.pop(context);
          Apps.instance.appInfo(a.package);
        }),
        SheetAction(Icons.delete_outline_rounded, 'Uninstall', () {
          Navigator.pop(context);
          Apps.instance.uninstall(a.package);
        }, danger: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final rows = _rows();
    final accent = tileAccent();
    final small = widget.prefs.tileRadius * .5; // list squares are smaller than tiles
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(DS.s16, pad.top + DS.s12, DS.s8, DS.s8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: widget.focus,
                      onChanged: (v) => setState(() => _query = v),
                      cursorColor: DS.onWallpaper,
                      style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Search ${widget.apps.length} apps',
                        hintStyle: const TextStyle(fontFamily: DS.font, color: Colors.white60, fontSize: 16),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white12,
                        contentPadding: const EdgeInsets.symmetric(vertical: DS.s12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(DS.s24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  if (widget.onRemote != null)
                    GestureDetector(
                      onLongPress: () => offerHideRemote(context, prefs: widget.prefs),
                      child: IconButton(
                        tooltip: 'TV remote',
                        onPressed: widget.onRemote,
                        icon: const Icon(Icons.settings_remote_rounded, color: Colors.white),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Launcher settings',
                    onPressed: widget.onSettings,
                    icon: const Icon(Icons.tune_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _list,
                padding: EdgeInsets.fromLTRB(DS.s16, 0, DS.s16, pad.bottom + DS.s24),
                itemExtent: rowH,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0), // build rows as they scroll in, so they animate in view
                itemCount: rows.length,
                // Landing: rows on screen come in one after another; rows scrolled to later don't.
                itemBuilder: (context, i) => Landed(
                  landing: listLanding,
                  style: widget.prefs.listAnim,
                  reveal: true, // rows scrolled to come in as they appear
                  delay: Duration(milliseconds: 24 * (i - (_list.hasClients ? _list.offset ~/ rowH : 0)).clamp(0, 16)),
                  child: Builder(
                    builder: (context) {
                      final r = rows[i];
                      if (r is String) {
                        // Letter tile: tap for the A–Z jump grid.
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Tooltip(
                            message: 'Jump to a letter',
                            child: InkWell(
                              onTap: () => setState(() => _jump = true),
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.bottomLeft,
                                padding: const EdgeInsets.fromLTRB(6, 0, 0, 2),
                                decoration: BoxDecoration(
                                  border: Border.all(color: accent, width: 2),
                                  borderRadius: BorderRadius.circular(small),
                                ),
                                child: Text(
                                  r.toLowerCase(),
                                  style: TextStyle(fontFamily: DS.font, color: accent, fontSize: 24, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      final a = r as AppEntry;
                      return Builder(
                        builder: (rowContext) => InkWell(
                          onTap: () {
                            Apps.instance.markLaunchFrom(rowContext);
                            widget.onLaunch(a);
                          },
                          onLongPress: () => _menu(a),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(small)),
                                alignment: Alignment.center,
                                child: TileGlyph(app: a, size: 28),
                              ),
                              const SizedBox(width: DS.s16),
                              Expanded(
                                child: Text(
                                  a.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_jump) _JumpGrid(rows: rows, accent: accent, onPick: _jumpTo, onClose: () => setState(() => _jump = false)),
      ],
    );
  }

  void _jumpTo(String letter) {
    final rows = _rows();
    final i = rows.indexOf(letter);
    setState(() => _jump = false);
    if (i >= 0 && _list.hasClients) {
      HapticFeedback.selectionClick();
      _list.jumpTo((i * rowH).clamp(0, _list.position.maxScrollExtent));
    }
  }
}

/// The A–Z grid over the list (Lumia's letter jump): letters with apps are lit.
class _JumpGrid extends StatelessWidget {
  const _JumpGrid({required this.rows, required this.accent, required this.onPick, required this.onClose});
  final List<Object> rows;
  final Color accent;
  final ValueChanged<String> onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final have = rows.whereType<String>().toSet();
    final letters = ['#', for (var c = 65; c <= 90; c++) String.fromCharCode(c)];
    final pad = MediaQuery.paddingOf(context);
    return GestureDetector(
      onTap: onClose,
      child: ColoredBox(
        color: const Color(0xE6000000),
        child: Padding(
          padding: EdgeInsets.fromLTRB(DS.s16, pad.top + DS.s24, DS.s16, pad.bottom + DS.s24),
          child: Center(
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final l in letters)
                  Material(
                    color: have.contains(l) ? accent : Colors.white10,
                    child: InkWell(
                      onTap: have.contains(l) ? () => onPick(l) : null,
                      child: Container(
                        alignment: Alignment.bottomLeft,
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          l.toLowerCase(),
                          style: TextStyle(
                            fontFamily: DS.font,
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            color: have.contains(l) ? Colors.white : Colors.white30,
                          ),
                        ),
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
