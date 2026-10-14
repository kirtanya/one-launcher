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
    const TileSpec('resume', 'w'),
    const TileSpec('clock', 'm'),
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
  });
  final Prefs prefs;
  final List<AppEntry> apps;
  final Widget header;
  final TvResumeInfo? resume;
  final void Function(AppEntry app) onLaunch;
  final VoidCallback onResume, onAllApps;
  final VoidCallback onTop; // ↑ from the top row: the top bar

  @override
  State<TvTilesStart> createState() => TvTilesStartState();
}

class TvTilesStartState extends State<TvTilesStart> {
  final _nodes = <String, FocusNode>{};
  final _scroll = ScrollController();
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
  void dispose() {
    _scroll.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Home / Back / landing: the first tile, Start scrolled to its beginning, tiles fly in.
  void land() {
    if (!mounted) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    final first = tvTiles(prefs, widget.apps).firstOrNull;
    if (first != null) _node(first.id).requestFocus();
    tvStartLanding.play();
  }

  /// ↓ from the top bar: the first tile on screen (no animation).
  void focusFirst() {
    final first = tvTiles(prefs, widget.apps).firstOrNull;
    if (first != null) _node(first.id).requestFocus();
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
      if (d == AxisDirection.up) widget.onTop();
      return true;
    }
    final node = _node(best.$1.id)..requestFocus();
    final ctx = node.context;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: .35, duration: TvLook.anim(const Duration(milliseconds: 320)), curve: Curves.easeOutCubic);
    }
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
        const gap = 8.0, top = 104.0;
        return LayoutBuilder(
          builder: (context, c) {
            final unit = (c.maxHeight - top - TvDS.safe.bottom - (rows - 1) * gap) / rows;
            final width = TvDS.safe.left * 2 + cols * unit + (cols - 1) * gap;
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
                // "start", Metro style: big, light, lowercase — and the top bar's buttons.
                // "start" and the top bar's tile buttons on one line, centred on each other.
                Positioned(
                  left: TvDS.safe.left,
                  right: TvDS.safe.right,
                  top: TvDS.safe.top - 6,
                  height: 60,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('start', style: TvDS.heroTitle.copyWith(fontSize: 44, fontWeight: FontWeight.w300, letterSpacing: -1, height: 1)),
                      const Spacer(),
                      widget.header,
                    ],
                  ),
                ),
                Positioned(
                  top: top,
                  left: 0,
                  right: 0,
                  bottom: TvDS.safe.bottom,
                  child: BackdropGroup(
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
                ),
              ],
            );
          },
        );
      },
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
