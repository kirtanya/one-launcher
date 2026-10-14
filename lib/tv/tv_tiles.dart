import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../apps.dart';
import '../prefs.dart';
import '../tiles/landing.dart';
import '../tiles/tiles_home.dart' show TileSpec, TileSurface, tileAccent, tileSwatches;
import '../top/header_fonts.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'tv_actions.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';
import 'tv_parts.dart';
import 'tv_settings.dart';

/// What the Resume tile shows: the show that's playing / paused, or the latest from history.
class TvResumeInfo {
  const TvResumeInfo({required this.title, this.app, this.art, this.progress, this.playing = false});
  final String title;
  final String? app;
  final ImageProvider? art;
  final double? progress;
  final bool playing;
}

/// A quick action above the Resume row (Tiles view): a built-in, a pinned app, or "+" (edit).
class TvTileAction {
  const TvTileAction({required this.id, required this.label, required this.onSelect, this.icon, this.app, this.onOptions});
  final String id, label;
  final IconData? icon;
  final AppEntry? app; // pinned app: its icon
  final VoidCallback onSelect;
  final VoidCallback? onOptions;
}

/// One card in the Resume row: what's playing / paused, the watch history, the apps' Watch Next.
class TvResumeCard {
  const TvResumeCard({required this.key, required this.info, required this.onSelect, this.onOptions});
  final String key;
  final TvResumeInfo info;
  final VoidCallback onSelect;
  final VoidCallback? onOptions;
}

/// The Start screen's own landing (Customise → Tiles → Start animation).
final tvStartLanding = Landing();

// ---- Tiles on TV: the list, defaults, pinning ------------------------------------------

/// Tiles saved in prefs (the TV app has its own prefs), else the TV defaults. App tiles whose
/// app is gone are skipped.
List<TileSpec> tvTiles(Prefs prefs, List<AppEntry> apps) {
  final installed = {for (final a in apps) a.package};
  final raw = prefs.tiles;
  final list = raw == null ? _defaults(prefs, apps) : [for (final m in raw) TileSpec.fromJson(m)];
  return [
    for (final t in list)
      if (!t.isApp || installed.contains(t.package)) t,
  ];
}

List<TileSpec> _defaults(Prefs prefs, List<AppEntry> apps) {
  final byPkg = {for (final a in apps) a.package: a};
  final picks = <AppEntry>[
    for (final p in prefs.favourites) ?byPkg[p],
    for (final a in apps)
      if (!prefs.favourites.contains(a.package)) a,
  ].take(8).toList();
  const sizes = ['m', 'm', 's', 's', 's', 's', 'm', 'm'];
  return [
    const TileSpec('clock', 'm'), // (Resume lives in its own row above the tiles)
    for (final (i, a) in picks.indexed) TileSpec('app:${a.package}', sizes[i]),
    const TileSpec('qa:t:inputs', 's'),
    const TileSpec('qa:t:settings', 's'),
    const TileSpec('allapps', 'm'),
  ];
}

Future<void> saveTvTiles(Prefs prefs, List<TileSpec> tiles) => prefs.setTiles([for (final t in tiles) t.toJson()]);

bool tvPinned(Prefs prefs, List<AppEntry> apps, String package) => tvTiles(prefs, apps).any((t) => t.id == 'app:$package');

Future<void> tvTogglePin(Prefs prefs, List<AppEntry> apps, String package) {
  final list = tvTiles(prefs, apps);
  final i = list.indexWhere((t) => t.id == 'app:$package');
  i >= 0 ? list.removeAt(i) : list.add(TileSpec('app:$package', 'm'));
  return saveTvTiles(prefs, list);
}

/// The sizes a tile can take on TV (smallest first). Clock / Resume need room for text.
List<String> _sizes(TileSpec t) => switch (t.id) {
  'clock' || 'resume' => const ['m', 'w', 'l'],
  _ => const ['s', 'm', 'w', 'l'],
};

/// Cells a tile covers: s 1×1, m 2×2, w 4×2, l 4×4 (never taller than the rows on screen).
(int, int) _span(TileSpec t, int rows) {
  final (w, h) = t.span;
  return (w, math.min(h, rows));
}

/// Places tiles column by column (top to bottom, then the next column) on a grid [rows] high
/// that grows sideways — the TV Start scrolls left / right, like Windows Media Center / Xbox.
List<(TileSpec, int, int)> packTvTiles(List<TileSpec> tiles, int rows) {
  final used = <(int, int)>{};
  final out = <(TileSpec, int, int)>[];
  for (final t in tiles) {
    final (w, h) = _span(t, rows);
    var placed = false;
    for (var col = 0; !placed; col++) {
      for (var row = 0; row + h <= rows && !placed; row++) {
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

// ---- The Start screen ---------------------------------------------------------------

/// One Launcher TV in the Tiles design language (Customise → Home screen → Home view):
/// a Metro Start of live tiles that scrolls sideways, driven by the remote. Shares the
/// phone's tile model, look settings (colours, glass, corners, transparency, names),
/// clock-tile style, entrance animations and interactions.
class TvTilesStart extends StatefulWidget {
  const TvTilesStart({
    super.key,
    required this.prefs,
    required this.apps,
    required this.header,
    required this.resume,
    required this.onLaunch,
    required this.onResume,
    required this.onAllApps,
    required this.onTop,
    this.quick = const [],
    this.resumeCards = const [],
  });
  final Prefs prefs;
  final List<AppEntry> apps;
  final Widget header;
  final TvResumeInfo? resume;
  final void Function(AppEntry app) onLaunch;
  final VoidCallback onResume, onAllApps;
  final VoidCallback onTop; // ↑ from the top row: the top bar
  final List<TvTileAction> quick; // quick actions row (top)
  final List<TvResumeCard> resumeCards; // Resume row (under the quick actions)

  @override
  State<TvTilesStart> createState() => TvTilesStartState();
}

class TvTilesStartState extends State<TvTilesStart> {
  final _nodes = <String, FocusNode>{};
  final _scroll = ScrollController(); // the tiles, sideways
  final _page = ScrollController(); // the whole Start, up / down (quick actions → resume → tiles)
  double _gridTop = 0;
  int _qi = 0, _ri = 0; // last focused quick action / resume card
  final _colours = <String, Color>{};
  String? _moving;
  List<(TileSpec, int, int)> _placed = const [];
  int _rows = 4;

  Prefs get prefs => widget.prefs;
  FocusNode _node(String id) => _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'tile:$id'));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => land());
  }

  @override
  void didUpdateWidget(TvTilesStart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The focused card / action went away (Hold OK → Remove from Continue watching / quick
    // actions): focus stays in its row, on the one now in its place, so the remote isn't lost.
    bool lost(Iterable<String> was, Iterable<String> now) => was.toSet().difference(now.toSet()).any((id) => _nodes[id]?.hasPrimaryFocus ?? false);
    final resume = lost([for (final r in oldWidget.resumeCards) 'r:${r.key}'], [for (final r in widget.resumeCards) 'r:${r.key}']);
    final quick = lost([for (final a in oldWidget.quick) 'q:${a.id}'], [for (final a in widget.quick) 'q:${a.id}']);
    if (!resume && !quick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (resume && widget.resumeCards.isNotEmpty) return _toResume();
      if (quick && widget.quick.isNotEmpty) return _toQuick();
      focusFirst();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _page.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Home / Back / landing: back to the top (first quick action, else Resume, else the first
  /// tile), everything scrolled to its start, tiles fly in.
  void land() {
    if (!mounted) return;
    for (final c in [_scroll, _page]) {
      if (c.hasClients) c.jumpTo(0);
    }
    _qi = _ri = 0;
    focusFirst();
    tvStartLanding.play();
  }

  /// ↓ from the top bar: the first row there is (no animation).
  void focusFirst() {
    if (widget.quick.isNotEmpty) return _toQuick();
    if (widget.resumeCards.isNotEmpty) return _toResume();
    _toTiles();
  }

  void _toQuick() => _focusIn('q:${widget.quick[_qi.clamp(0, widget.quick.length - 1)].id}', top: true);
  void _toResume() => _focusIn('r:${widget.resumeCards[_ri.clamp(0, widget.resumeCards.length - 1)].key}', top: true);
  void _toTiles() {
    final first = tvTiles(prefs, widget.apps).firstOrNull;
    if (first != null) _focusIn(first.id, top: false);
  }

  /// Focus [id]; the page shows the top rows ([top]) or the tiles; the row slides it into view.
  void _focusIn(String id, {required bool top}) {
    final node = _node(id)..requestFocus();
    _pageTo(top);
    final ctx = node.context;
    if (ctx != null) _reveal(ctx);
  }

  void _pageTo(bool top) {
    if (!_page.hasClients) return;
    final y = top ? 0.0 : (_gridTop - TvDS.safe.top).clamp(0.0, _page.position.maxScrollExtent);
    if ((_page.offset - y).abs() > 1) _page.animateTo(y, duration: TvLook.anim(const Duration(milliseconds: 380)), curve: Curves.easeOutCubic);
  }

  /// Slide the item's own row (sideways only) so it sits comfortably in view.
  void _reveal(BuildContext ctx) {
    final ro = ctx.findRenderObject();
    final pos = Scrollable.maybeOf(ctx)?.position;
    if (ro == null || pos == null || pos.axis != Axis.horizontal) return;
    pos.ensureVisible(ro, alignment: .3, duration: TvLook.anim(const Duration(milliseconds: 320)), curve: Curves.easeOutCubic);
  }

  bool _moveQuick(int i, AxisDirection d) {
    final n = widget.quick.length;
    switch (d) {
      case AxisDirection.left when i > 0:
        _qi = i - 1;
        _toQuick();
      case AxisDirection.right when i < n - 1:
        _qi = i + 1;
        _toQuick();
      case AxisDirection.up:
        widget.onTop();
      case AxisDirection.down:
        widget.resumeCards.isNotEmpty ? _toResume() : _toTiles();
      default:
        break;
    }
    return true;
  }

  bool _moveResume(int i, AxisDirection d) {
    final n = widget.resumeCards.length;
    switch (d) {
      case AxisDirection.left when i > 0:
        _ri = i - 1;
        _toResume();
      case AxisDirection.right when i < n - 1:
        _ri = i + 1;
        _toResume();
      case AxisDirection.up:
        widget.quick.isNotEmpty ? _toQuick() : widget.onTop();
      case AxisDirection.down:
        _toTiles();
      default:
        break;
    }
    return true;
  }

  /// Leaves for an app: everything swings away (turnstile), the chosen tile last.
  void _go(TileSpec t, VoidCallback open) {
    if (prefs.fx('turnstile') && prefs.tileAnim != 'none' && TvLook.str('motion') != 'reduced') {
      tvStartLanding.exit(last: t.id);
      Future.delayed(const Duration(milliseconds: 260), open);
    } else {
      open();
    }
  }

  void _open(TileSpec t) {
    final byPkg = {for (final a in widget.apps) a.package: a};
    switch (t.id) {
      case 'resume':
        _go(t, widget.onResume);
      case 'allapps':
        widget.onAllApps();
      case 'clock':
        TvApps.instance.openAction('t:datetime');
      default:
        if (t.isApp && byPkg[t.package] != null) _go(t, () => widget.onLaunch(byPkg[t.package]!));
        if (t.isAction) TvApps.instance.openAction(t.action);
    }
  }

  // ---- Editing with the remote ----

  Future<void> _update(List<TileSpec> list) => saveTvTiles(prefs, list);

  void _menu(TileSpec t) {
    final list = tvTiles(prefs, widget.apps);
    final i = list.indexWhere((x) => x.id == t.id);
    final sizes = _sizes(t);
    final s = sizes.indexOf(t.size);
    final app = t.isApp ? widget.apps.where((a) => a.package == t.package).firstOrNull : null;
    showTvPanel(
      context,
      title: _title(t, app),
      actions: [
        TvAction(Icons.open_in_new_rounded, 'Open', () => _open(t)),
        TvAction(Icons.open_with_rounded, 'Move', () {
          setState(() => _moving = t.id);
          _node(t.id).requestFocus();
        }),
        if (s >= 0 && s < sizes.length - 1) TvAction(Icons.zoom_out_map_rounded, 'Bigger', () => _update(list..[i] = t.resized(sizes[s + 1]))),
        if (s > 0) TvAction(Icons.zoom_in_map_rounded, 'Smaller', () => _update(list..[i] = t.resized(sizes[s - 1]))),
        TvAction(Icons.palette_outlined, 'Colour', () => _palette(t)),
        TvAction(Icons.push_pin_outlined, 'Unpin from Start', () => _update(list..removeAt(i))),
        if (app != null) TvAction(Icons.info_outline_rounded, 'App info', () => TvApps.instance.appInfo(app.package)),
      ],
    );
  }

  static const _swatchNames = ['Blue', 'Teal', 'Green', 'Lime', 'Amber', 'Orange', 'Rust', 'Red', 'Pink', 'Purple', 'Indigo', 'Slate'];

  void _palette(TileSpec t) {
    showTvPanel(
      context,
      title: 'Tile colour',
      refresh: prefs,
      build: () {
        final list = tvTiles(prefs, widget.apps);
        final i = list.indexWhere((x) => x.id == t.id);
        final cur = i < 0 ? null : list[i].colour;
        void set(String? c) {
          if (i >= 0) _update(list..[i] = list[i].recoloured(c));
        }

        return [
          TvAction(Icons.auto_awesome_outlined, 'Start default', () => set(null), keepOpen: true, selected: cur == null),
          TvAction(Icons.circle, 'Accent', () => set('accent'), keepOpen: true, swatch: tileAccent(), selected: cur == 'accent'),
          if (t.isApp) TvAction(Icons.apps_rounded, 'App colour', () => set('app'), keepOpen: true, selected: cur == 'app'),
          for (final (k, c) in tileSwatches.indexed)
            TvAction(
              Icons.circle,
              _swatchNames[k % _swatchNames.length],
              () => set(c.toARGB32().toRadixString(16)),
              keepOpen: true,
              swatch: c,
              selected: cur == c.toARGB32().toRadixString(16),
            ),
        ];
      },
    );
  }

  /// Moving: ← ↑ earlier, → ↓ later in the order (the grid repacks around it). OK / Back: done.
  bool _shift(TileSpec t, AxisDirection d) {
    final list = tvTiles(prefs, widget.apps);
    final i = list.indexWhere((x) => x.id == t.id);
    final j = i + (d == AxisDirection.left || d == AxisDirection.up ? -1 : 1);
    if (i < 0 || j < 0 || j >= list.length) return true;
    list.insert(j, list.removeAt(i));
    _update(list);
    WidgetsBinding.instance.addPostFrameCallback((_) => _node(t.id).requestFocus());
    return true;
  }

  /// The remote on the grid: the nearest tile in that direction, preferring ones that line up
  /// (tiles have different sizes, so "below" can be several tiles). ↑ off the top: the top bar.
  bool _navigate(TileSpec from, AxisDirection d) {
    final me = _placed.where((p) => p.$1.id == from.id).firstOrNull;
    if (me == null) return false;
    (double, double, double, double) box((TileSpec, int, int) p) {
      final (w, h) = _span(p.$1, _rows);
      return (p.$2.toDouble(), p.$3.toDouble(), (p.$2 + w).toDouble(), (p.$3 + h).toDouble()); // l, t, r, b
    }

    final (l, t, r, b) = box(me);
    (TileSpec, int, int)? best;
    var bestScore = double.infinity;
    for (final p in _placed) {
      if (p.$1.id == from.id) continue;
      final (pl, pt, pr, pb) = box(p);
      final double gap;
      final double off; // how far apart across the movement (0 = they line up)
      switch (d) {
        case AxisDirection.right:
          if (pl < r) continue;
          gap = pl - r;
          off = math.max(0, math.max(pt - (b - .5), t - (pb - .5)));
        case AxisDirection.left:
          if (pr > l) continue;
          gap = l - pr;
          off = math.max(0, math.max(pt - (b - .5), t - (pb - .5)));
        case AxisDirection.down:
          if (pt < b) continue;
          gap = pt - b;
          off = math.max(0, math.max(pl - (r - .5), l - (pr - .5)));
        case AxisDirection.up:
          if (pb > t) continue;
          gap = t - pb;
          off = math.max(0, math.max(pl - (r - .5), l - (pr - .5)));
      }
      // Lined-up tiles win; then the nearest; then the one closest to where the focus is.
      final across = d == AxisDirection.up || d == AxisDirection.down ? ((pl + pr) / 2 - (l + r) / 2).abs() : ((pt + pb) / 2 - (t + b) / 2).abs();
      final score = off * 100 + gap * 10 + across;
      if (score < bestScore) {
        bestScore = score;
        best = p;
      }
    }
    if (best == null) {
      // ↑ off the tiles: the Resume row, the quick actions, then the top bar.
      if (d == AxisDirection.up) {
        if (widget.resumeCards.isNotEmpty) {
          _toResume();
        } else if (widget.quick.isNotEmpty) {
          _toQuick();
        } else {
          widget.onTop();
        }
      }
      return true;
    }
    _focusIn(best.$1.id, top: false);
    return true;
  }

  bool endMove() {
    if (_moving == null) return false;
    setState(() => _moving = null);
    return true;
  }

  // ---- Colours ----

  Color _colour(TileSpec t) {
    final mode = t.colour ?? (prefs.tileColours == 'colourful' ? 'app' : 'accent');
    final Color c = switch (mode) {
      'accent' => tileAccent(),
      'app' when t.isApp => _colours[t.package] ?? _fetchColour(t.package),
      'app' => tileAccent(),
      _ => Color(int.tryParse(mode, radix: 16) ?? tileAccent().toARGB32()),
    };
    return c.withValues(alpha: prefs.tileOpacity);
  }

  Color _fetchColour(String pkg) {
    TvApps.instance.iconColour(pkg).then((c) {
      if (!mounted || c == null) return;
      // Deep enough for white text, like the phone's tiles.
      final h = HSLColor.fromColor(c);
      setState(() => _colours[pkg] = h.withSaturation(math.max(h.saturation, .45)).withLightness(.4).toColor());
    });
    return tileAccent();
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        TvLook.read(prefs);
        final tiles = tvTiles(prefs, widget.apps);
        final rows = TvLook.number('tileRows').round();
        final placed = packTvTiles(tiles, rows);
        _placed = placed;
        _rows = rows;
        final cols = placed.fold<int>(0, (m, p) => math.max(m, p.$2 + _span(p.$1, rows).$1));
        const gap = 8.0;
        return LayoutBuilder(
          builder: (context, c) {
            const headerH = 60.0, quickH = 44.0, resumeH = 150.0, space = 18.0;
            final hasQuick = widget.quick.isNotEmpty, hasResume = widget.resumeCards.isNotEmpty;
            final stacked = hasQuick || hasResume;
            // With rows above, the tiles fill a screen of their own (scrolled to with ↓) so they stay
            // big, and the gap over them is wider than the top margin: nothing peeks in above them.
            // With no rows above, they fit under "start" (no scrolling).
            final gridGap = stacked ? TvDS.safe.top + 3 : 23.0;
            _gridTop = TvDS.safe.top - 6 + headerH + (hasQuick ? space + quickH : 0) + (hasResume ? space + resumeH : 0) + gridGap;
            final gridH = c.maxHeight - (stacked ? TvDS.safe.top : _gridTop) - TvDS.safe.bottom;
            final unit = (gridH - (rows - 1) * gap) / rows;
            final width = TvDS.safe.left * 2 + cols * unit + (cols - 1) * gap;
            Widget sideways({required double height, required List<Widget> children}) => SizedBox(
              height: height,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.symmetric(horizontal: TvDS.safe.left),
                child: Row(
                  children: [
                    for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(width: gap), w],
                  ],
                ),
              ),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: TvDS.canvas),
                // Customise → Tiles → Background: an accent glow (gives glass tiles something to frost).
                if (TvLook.str('tileBg') == 'glow')
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-.6, -.4),
                        radius: 1.3,
                        colors: [tileAccent().withValues(alpha: .75), tileAccent().withValues(alpha: .18), TvDS.canvas],
                        stops: const [0, .55, 1],
                      ),
                    ),
                  ),
                BackdropGroup(
                  child: SingleChildScrollView(
                    controller: _page,
                    clipBehavior: Clip.none,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: TvDS.safe.top - 6),
                        // "start" and the top bar's tile buttons on one line.
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: TvDS.safe.left),
                          child: SizedBox(
                            height: headerH,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text('start', style: TvDS.heroTitle.copyWith(fontSize: 44, fontWeight: FontWeight.w300, letterSpacing: -1, height: 1)),
                                const Spacer(),
                                widget.header,
                              ],
                            ),
                          ),
                        ),
                        // ---- Quick actions ----
                        if (hasQuick) ...[
                          const SizedBox(height: space),
                          sideways(height: quickH, children: [for (final (i, a) in widget.quick.indexed) _quickTile(a, i)]),
                        ],
                        // ---- Resume: everything you were watching ----
                        if (hasResume) ...[
                          const SizedBox(height: space),
                          sideways(height: resumeH, children: [for (final (i, r) in widget.resumeCards.indexed) _resumeTile(r, i, resumeH)]),
                        ],
                        SizedBox(height: gridGap),
                        // ---- The tiles ----
                        SizedBox(
                          height: rows * unit + (rows - 1) * gap,
                          child: SingleChildScrollView(
                            controller: _scroll,
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            child: SizedBox(
                              width: width,
                              height: rows * unit + (rows - 1) * gap,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (final (t, col, row) in placed)
                                    AnimatedPositioned(
                                      key: ValueKey(t.id),
                                      duration: TvLook.anim(Motion.snapDuration),
                                      curve: Motion.settle,
                                      left: TvDS.safe.left + col * (unit + gap),
                                      top: row * (unit + gap),
                                      width: _span(t, rows).$1 * unit + (_span(t, rows).$1 - 1) * gap,
                                      height: _span(t, rows).$2 * unit + (_span(t, rows).$2 - 1) * gap,
                                      child: Landed(
                                        landing: tvStartLanding,
                                        style: TvLook.str('motion') == 'reduced' ? 'none' : prefs.tileAnim,
                                        delay: Duration(milliseconds: 40 * col + 22 * row),
                                        id: t.id,
                                        child: _tile(t),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: TvDS.safe.bottom),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// A quick action as a small tile (tile colour / glass / corners, white focus frame).
  Widget _quickTile(TvTileAction a, int i) {
    return TvFocusable(
      key: ValueKey('q:${a.id}'), // keyed: a reorder moves the tile (and its focus) with it
      focusNode: _node('q:${a.id}'),
      onSelect: a.onSelect,
      onLongSelect: a.onOptions,
      onMove: (d) => _moveQuick(i, d),
      builder: (context, f) => AnimatedScale(
        scale: f ? 1.06 : 1,
        duration: TvLook.anim(Motion.popDuration),
        curve: Motion.pop,
        child: Container(
          height: 44,
          constraints: const BoxConstraints(minWidth: 44),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(prefs.tileRadius),
            border: Border.all(color: f ? Colors.white : Colors.transparent, width: 2),
          ),
          child: ExcludeFocus(
            child: TileSurface(
              colour: tileAccent().withValues(alpha: prefs.tileOpacity),
              prefs: prefs,
              onTap: a.onSelect,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: a.label.isEmpty ? 0 : 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: a.label.isEmpty ? 44 : null,
                      // A pinned app: its own icon (cached after the first load, so no flicker).
                      child: a.app != null
                          ? SizedBox.square(
                              dimension: 22,
                              child: switch (TvApps.instance.iconNow(a.app!.package)) {
                                final ready? => Image(image: ready, gaplessPlayback: true),
                                _ => FutureBuilder<MemoryImage?>(
                                  future: TvApps.instance.icon(a.app!.package),
                                  builder: (context, s) => s.data != null
                                      ? Image(image: s.data!, gaplessPlayback: true)
                                      : const Icon(Icons.apps_rounded, color: Colors.white, size: 20),
                                ),
                              },
                            )
                          : Icon(a.icon ?? Icons.bolt_rounded, color: Colors.white, size: 20),
                    ),
                    if (a.label.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(a.label.toLowerCase(), style: TvDS.tileName.copyWith(fontSize: 14, color: Colors.white)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A Resume card: wide tile with the artwork, title, app and progress; OK resumes it.
  Widget _resumeTile(TvResumeCard r, int i, double h) {
    return TvFocusable(
      key: ValueKey('r:${r.key}'), // keyed: when a card goes, the others keep their focus / flip
      focusNode: _node('r:${r.key}'),
      onSelect: r.onSelect,
      onLongSelect: r.onOptions,
      onMove: (d) => _moveResume(i, d),
      builder: (context, f) => AnimatedScale(
        scale: f ? 1.05 : 1,
        duration: TvLook.anim(Motion.popDuration),
        curve: Motion.pop,
        child: Container(
          width: h * 16 / 9,
          height: h,
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(prefs.tileRadius),
            border: Border.all(color: f ? Colors.white : Colors.transparent, width: 3),
          ),
          child: ExcludeFocus(
            child: TileSurface(
              colour: tileAccent().withValues(alpha: prefs.tileOpacity),
              prefs: prefs,
              onTap: r.onSelect,
              // Live tiles: only the one that's playing flips.
              child: _ResumeFace(info: r.info, live: prefs.fx('live') && r.info.playing && TvLook.str('motion') != 'reduced', names: true),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(TileSpec t) {
    final moving = _moving == t.id;
    final app = t.isApp ? widget.apps.where((a) => a.package == t.package).firstOrNull : null;
    return TvFocusable(
      focusNode: _node(t.id),
      onSelect: () => moving ? endMove() : _open(t),
      onLongSelect: () => _menu(t),
      onMove: moving ? (d) => _shift(t, d) : (d) => _navigate(t, d),
      builder: (context, f) {
        final radius = BorderRadius.circular(prefs.tileRadius);
        // ExcludeFocus: the surface's own tap target must not catch the remote's focus.
        Widget tile = ExcludeFocus(
          child: TileSurface(colour: _colour(t), prefs: prefs, onTap: () => _open(t), child: _face(t, app)),
        );
        // Focus: Metro's bright frame, a small lift, and (Interactions → Tilt) a slight lean.
        tile = AnimatedContainer(
          duration: TvLook.anim(Motion.pressIn * 2),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: f || moving ? Colors.white : Colors.transparent, width: 3),
          ),
          child: tile,
        );
        final tilt = f && prefs.fx('tilt') && TvLook.str('motion') != 'reduced';
        return AnimatedScale(
          scale: moving ? 1.1 : (f ? 1.05 : 1),
          duration: TvLook.anim(Motion.popDuration),
          curve: Motion.pop,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0012)
              ..rotateY(tilt ? -.018 : 0)
              ..rotateX(tilt ? .01 : 0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                tile,
                if (moving)
                  const IgnorePointer(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.chevron_left_rounded, color: Colors.white, size: 30),
                        Icon(Icons.chevron_right_rounded, color: Colors.white, size: 30),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _title(TileSpec t, AppEntry? app) => switch (t.id) {
    'clock' => 'Clock',
    'resume' => 'Resume',
    'allapps' => 'All apps',
    _ when t.isAction => tvActions[t.action]?.$1 ?? 'Quick action',
    _ => app?.label ?? 'App',
  };

  Widget _label(String text) => Positioned(
    left: 10,
    right: 10,
    bottom: 8,
    child: Text(
      text,
      style: TvDS.tileName.copyWith(fontSize: 13, color: Colors.white),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _face(TileSpec t, AppEntry? app) {
    final small = t.size == 's';
    final names = prefs.tileLabels && !small;
    switch (t.id) {
      case 'clock':
        return _ClockFace(prefs: prefs, big: t.size != 'm');
      case 'resume':
        return _ResumeFace(info: widget.resume, live: prefs.fx('live') && TvLook.str('motion') != 'reduced', names: names);
      case 'allapps':
        return Stack(
          fit: StackFit.expand,
          children: [
            const Center(child: Icon(Icons.apps_rounded, color: Colors.white, size: 40)),
            if (names) _label('all apps'),
          ],
        );
    }
    if (t.isAction) {
      final (label, icon) = tvActions[t.action] ?? ('Action', Icons.bolt_rounded);
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Icon(icon, color: Colors.white, size: small ? 26 : 40),
          ),
          if (names) _label(label.toLowerCase()),
        ],
      );
    }
    if (app == null) return const SizedBox.shrink();
    // App: its TV banner filling the tile (Customise → Tiles → Tile face), else its icon.
    final banner = TvLook.str('tileFace') == 'banner' ? TvApps.instance.artNow(app.package) : null;
    if (banner != null && banner.banner && !small) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image(image: banner.image, fit: BoxFit.cover, gaplessPlayback: true),
          if (names)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x99000000)],
                    stops: [.55, 1],
                  ),
                ),
              ),
            ),
          if (names) _label(app.label),
        ],
      );
    }
    final size = switch (t.size) {
      's' => 34.0,
      'l' => 96.0,
      'w' => 56.0,
      _ => 56.0,
    };
    final ready = TvApps.instance.iconNow(app.package);
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: SizedBox.square(
            dimension: size,
            child: ready != null
                ? Image(image: ready, gaplessPlayback: true)
                : FutureBuilder<MemoryImage?>(
                    future: TvApps.instance.icon(app.package),
                    builder: (context, s) => s.data != null
                        ? Image(image: s.data!, gaplessPlayback: true)
                        : Center(
                            child: Text(app.label.isEmpty ? '?' : app.label[0], style: TvDS.panelTitle.copyWith(fontSize: size * .55)),
                          ),
                  ),
          ),
        ),
        if (names) _label(app.label),
      ],
    );
  }
}

/// The clock tile: the time in the tile clock style (Customise → Tiles → Clock style), the day
/// and date on the bigger sizes. Ticks on the minute.
class _ClockFace extends StatefulWidget {
  const _ClockFace({required this.prefs, required this.big});
  final Prefs prefs;
  final bool big;

  @override
  State<_ClockFace> createState() => _ClockFaceState();
}

class _ClockFaceState extends State<_ClockFace> {
  Timer? _t;
  DateTime _now = DateTime.now();
  static const _days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  static const _months = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];

  @override
  void initState() {
    super.initState();
    _tick();
  }

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
    final p = widget.prefs;
    final h24 = switch (TvLook.str('clock24')) {
      '12' => false,
      '24' => true,
      _ => MediaQuery.alwaysUse24HourFormatOf(context),
    };
    final h = h24 ? _now.hour : (_now.hour % 12 == 0 ? 12 : _now.hour % 12);
    final time = '${h.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: FittedBox(
              alignment: Alignment.bottomLeft,
              child: Text(
                time,
                style: clockStyle(
                  weight: p.tileClockWeight,
                  width: p.tileClockWidth,
                  slant: p.tileClockSlant,
                  round: p.tileClockRound,
                ).copyWith(color: Colors.white, height: 1),
              ),
            ),
          ),
          if (widget.big) ...[
            const SizedBox(height: 6),
            Text('${_days[_now.weekday - 1]} ${_now.day} ${_months[_now.month - 1]}', style: TvDS.tileName.copyWith(color: Colors.white, fontSize: 15)),
          ],
        ],
      ),
    );
  }
}

/// The Resume tile: artwork, title, app and progress of what's playing / paused (or the
/// latest from your history). Live tiles on: it flips between the artwork and the details.
class _ResumeFace extends StatefulWidget {
  const _ResumeFace({required this.info, required this.live, required this.names});
  final TvResumeInfo? info;
  final bool live, names;

  @override
  State<_ResumeFace> createState() => _ResumeFaceState();
}

class _ResumeFaceState extends State<_ResumeFace> {
  Timer? _flip;
  bool _back = false;

  @override
  void initState() {
    super.initState();
    _flip = Timer.periodic(const Duration(milliseconds: 5200), (_) {
      if (mounted && widget.live && widget.info?.art != null) setState(() => _back = !_back);
    });
  }

  @override
  void dispose() {
    _flip?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.info;
    if (i == null) {
      return const Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Icon(Icons.play_circle_outline_rounded, color: Colors.white54, size: 44)),
          Positioned(
            left: 10,
            bottom: 8,
            child: Text(
              'nothing playing',
              style: TextStyle(fontFamily: DS.font, fontSize: 13, color: Colors.white70),
            ),
          ),
        ],
      );
    }
    final details = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              Icon(i.playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 4),
              Text(i.playing ? 'now playing' : 'resume', style: TvDS.tileName.copyWith(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 4),
          Text(i.title, style: TvDS.panelTitle.copyWith(fontSize: 18, height: 1.15), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (i.app != null) Text(i.app!.toLowerCase(), style: TvDS.tileName.copyWith(color: Colors.white70)),
          if (i.progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: i.progress, minHeight: 3, color: Colors.white, backgroundColor: Colors.white24),
            ),
          ],
        ],
      ),
    );
    final art = i.art == null
        ? null
        : Stack(
            fit: StackFit.expand,
            children: [
              Image(image: i.art!, fit: BoxFit.cover, gaplessPlayback: true),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                    stops: [.35, 1],
                  ),
                ),
              ),
              details,
            ],
          );
    if (art == null) return details;
    if (!widget.live) return art;
    // Live tile: flips (around the horizontal axis) between artwork-with-title and details.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 650),
      transitionBuilder: (child, a) => AnimatedBuilder(
        animation: a,
        child: child,
        builder: (context, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0015)
            ..rotateX((1 - a.value) * math.pi / 2),
          child: Opacity(opacity: a.value < .5 ? 0 : 1, child: child),
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_back), child: _back ? details : art),
    );
  }
}

/// A top-bar button drawn as a tile (Tiles view): the tile colour / glass, the tile corners and
/// the tiles' white focus frame. Search carries its word; the others are square icons.
class TvTileButton extends StatelessWidget {
  const TvTileButton({super.key, required this.prefs, required this.icon, required this.focusNode, required this.onSelect, this.label, this.onMove});
  final Prefs prefs;
  final IconData icon;
  final String? label;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final bool Function(AxisDirection)? onMove;

  static const size = 44.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onMove: onMove,
        builder: (context, f) => AnimatedScale(
          scale: f ? 1.08 : 1,
          duration: TvLook.anim(Motion.popDuration),
          curve: Motion.pop,
          child: Container(
            height: size,
            constraints: const BoxConstraints(minWidth: size),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(prefs.tileRadius),
              border: Border.all(color: f ? Colors.white : Colors.transparent, width: 2),
            ),
            child: ExcludeFocus(
              child: TileSurface(
                colour: tileAccent().withValues(alpha: prefs.tileOpacity),
                prefs: prefs,
                onTap: onSelect,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: label == null ? size : null,
                        child: Icon(icon, color: Colors.white, size: 22),
                      ),
                      if (label != null) ...[const SizedBox(width: 8), Text(label!, style: TvDS.tileName.copyWith(fontSize: 15, color: Colors.white))],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
