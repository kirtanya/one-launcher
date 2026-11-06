import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_real.dart';
import '../third/tactile/tactile.dart';
import '../third/tactile/parts.dart';

import '../apps.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';
import 'tv_metro.dart';

/// Shared TV pieces: app tiles + artwork, the options side panel, search.

PageRoute<void> tvFade(Widget page) => PageRouteBuilder(
  pageBuilder: (_, _, _) => page,
  transitionDuration: const Duration(milliseconds: 220),
  reverseTransitionDuration: const Duration(milliseconds: 160),
  transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
);

/// Decodes [p] at its slot size (logical width × devicePixelRatio) instead of full resolution.
ImageProvider tvSized(ImageProvider p, double logicalW, BuildContext c) {
  final px = (logicalW * MediaQuery.devicePixelRatioOf(c)).round();
  if (px <= 0 || p is ResizeImage) return p;
  return ResizeImage(p, width: px, policy: ResizeImagePolicy.fit);
}

// ---- Cheap drawing on the TV's GPU ---------------------------------------------
// Measured on a Mali-G31 TV (2026-11-06, SurfaceFlinger timestats + PERF_LOG raster times):
// Impeller draws gradients with more than two plain stops through a slow shader (~10 ms for
// one column-sized quad), and every ClipRRect / ClipOval is a stencil pass. So smooth shading is
// painted once into a picture and drawn as a texture ([TvBaked]); rounded pictures are one
// shape filled with the image ([TvRoundImage]), never a clip.

final _baked = <Object, ui.Image>{}; // insertion order = least recently used first
var _bakedBytes = 0;

/// Paints [painter] once into a picture at screen resolution (cached by [id] + size) and draws
/// that 1:1: one texture draw per frame instead of the gradients' shaders. Full resolution on
/// purpose: Impeller dithers gradients, and a smaller bake scaled up shows the dither as dots.
class TvBaked extends StatelessWidget {
  const TvBaked({super.key, required this.painter, required this.id});

  /// A gradient filling the box (same pixels as a [DecoratedBox] with it).
  TvBaked.gradient(Gradient g, {Key? key}) : this(key: key, painter: _GradientPainter(g), id: g);

  final CustomPainter painter;
  final Object id; // everything the painting depends on, besides the size

  static ui.Image _bake(CustomPainter p, Object id, Size size, double scale) {
    final w = math.max(1, (size.width * scale).round()), h = math.max(1, (size.height * scale).round());
    final key = (id, w, h);
    final hit = _baked.remove(key);
    if (hit != null) return _baked[key] = hit; // most recent last
    final r = ui.PictureRecorder();
    final c = Canvas(r)..scale(w / size.width, h / size.height);
    p.paint(c, size);
    final pic = r.endRecording();
    final img = pic.toImageSync(w, h);
    pic.dispose();
    // Keep ~32 MB of these (a full screen is ~8 MB); pictures on screen hold their own clone.
    _bakedBytes += w * h * 4;
    while (_bakedBytes > 32 << 20 && _baked.isNotEmpty) {
      final old = _baked.remove(_baked.keys.first)!;
      _bakedBytes -= old.width * old.height * 4;
      old.dispose();
    }
    return _baked[key] = img;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final size = c.biggest;
          if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
          // RawImage takes ownership of what it's given: hand it a clone, the cache keeps its own.
          return RawImage(image: _bake(painter, id, size, dpr).clone(), width: size.width, height: size.height, fit: BoxFit.fill, filterQuality: FilterQuality.none);
        },
      ),
    );
  }
}

class _GradientPainter extends CustomPainter {
  const _GradientPainter(this.g);
  final Gradient g;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(Offset.zero & size, Paint()..shader = g.createShader(Offset.zero & size));

  @override
  bool shouldRepaint(_GradientPainter o) => o.g != g;
}

/// [image] drawn to fill its box ([fit], centred) with rounded corners — one rounded rect filled
/// with the picture, no clip layer. A circle: radius ≥ half the side. Shows [placeholder] until
/// the picture is ready (and [error] or the placeholder if it fails); keeps the old picture while a
/// new one loads.
class TvRoundImage extends StatefulWidget {
  const TvRoundImage({super.key, required this.image, required this.radius, this.fit = BoxFit.cover, this.placeholder, this.error});
  final ImageProvider image;
  final double radius;
  final BoxFit fit;
  final Widget? placeholder, error;

  @override
  State<TvRoundImage> createState() => _TvRoundImageState();
}

class _TvRoundImageState extends State<TvRoundImage> {
  ImageStream? _stream;
  ImageInfo? _info;
  bool _failed = false;
  late final _listener = ImageStreamListener(
    (info, _) {
      if (!mounted) return info.dispose();
      setState(() {
        _info?.dispose();
        _info = info;
        _failed = false;
      });
    },
    onError: (_, _) {
      if (mounted) setState(() => _failed = true);
    },
  );

  void _resolve() {
    final s = widget.image.resolve(createLocalImageConfiguration(context));
    if (s.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = s..addListener(_listener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(TvRoundImage old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) _resolve();
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return (_failed ? widget.error : null) ?? widget.placeholder ?? const SizedBox.expand();
    return CustomPaint(painter: _RoundImagePainter(info.image, widget.radius, widget.fit), child: const SizedBox.expand());
  }
}

class _RoundImagePainter extends CustomPainter {
  const _RoundImagePainter(this.image, this.radius, this.fit);
  final ui.Image image;
  final double radius;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final img = Size(image.width.toDouble(), image.height.toDouble());
    final fs = applyBoxFit(fit, img, size);
    final src = Alignment.center.inscribe(fs.source, Offset.zero & img);
    final dst = Alignment.center.inscribe(fs.destination, box);
    final sx = dst.width / src.width, sy = dst.height / src.height;
    final m = Matrix4.identity()
      ..translateByDouble(dst.left - src.left * sx, dst.top - src.top * sy, 0, 1)
      ..scaleByDouble(sx, sy, 1, 1);
    final paint = Paint()
      ..shader = ImageShader(image, TileMode.clamp, TileMode.clamp, m.storage, filterQuality: FilterQuality.low)
      ..isAntiAlias = true;
    canvas.drawRRect(RRect.fromRectAndRadius(dst.intersect(box), Radius.circular(radius)), paint);
  }

  @override
  bool shouldRepaint(_RoundImagePainter o) => o.image != image || o.radius != radius || o.fit != fit;
}

// ---- Tiles -------------------------------------------------------------------

class TvAppTile extends StatelessWidget {
  const TvAppTile({super.key, required this.app, required this.focusNode, required this.onSelect, required this.onOptions, this.onMove, this.onFocus});
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
              Container(
                width: TvDS.tileW,
                height: TvDS.tileH,
                // Ring + glow only on the focused tile (one blur on screen at a time). Tiles: the
                // Metro frame and corners.
                foregroundDecoration: TvMetro.on ? TvMetro.frame(f, width: TvDS.focusRing) : TvRing(on: f, radius: TvDS.rTile),
                decoration: BoxDecoration(
                  borderRadius: TvMetro.corners(TvDS.rTile),
                  boxShadow: TvMetro.on ? TvMetro.glow(f) : (f ? const [BoxShadow(color: TvDS.glow, blurRadius: 18)] : null),
                ),
                child: TvAppArt(app: app, width: TvDS.tileW, radius: TvMetro.radius(TvDS.rTile)),
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
/// An app as a circle (Customise → App cards → Circle): its own icon filling it, or its initial
/// on a quiet disc until the icon arrives. The round clip comes from the card.
class TvAppIcon extends StatelessWidget {
  const TvAppIcon({super.key, required this.app, required this.size, this.round = false});
  final AppEntry app;
  final double size;
  final bool round; // a circle drawn as one shape (no ClipOval needed around it)

  @override
  Widget build(BuildContext context) {
    final ready = TvApps.instance.iconNow(app.package);
    Widget letter() => Text(app.label.isEmpty ? '?' : app.label[0].toUpperCase(), style: TvDS.tileName.copyWith(fontSize: size * .36));
    Widget roundView(ImageProvider? icon) => DecoratedBox(
      decoration: BoxDecoration(color: TvDS.surface, shape: BoxShape.circle),
      child: icon != null ? TvRoundImage(image: tvSized(icon, size, context), radius: size / 2) : Center(child: letter()),
    );
    Widget view(ImageProvider? icon) => round ? roundView(icon) : ColoredBox(
      color: TvDS.surface,
      child: Center(
        child: icon != null
            // TV app icons are squares with their own background: they fill the circle, which crops them.
            ? Image(image: tvSized(icon, size, context), width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.low)
            : Text(app.label.isEmpty ? '?' : app.label[0].toUpperCase(), style: TvDS.tileName.copyWith(fontSize: size * .36)),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: ready != null ? view(ready) : FutureBuilder<MemoryImage?>(future: TvApps.instance.icon(app.package), builder: (context, s) => view(s.data)),
    );
  }
}

class TvAppArt extends StatelessWidget {
  const TvAppArt({super.key, required this.app, required this.width, this.radius = 0});
  final AppEntry app;
  final double width;

  /// Rounded corners drawn into the picture itself (no ClipRRect stencil pass); 0 = square.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ready = TvApps.instance.artNow(app.package);
    return SizedBox(
      width: width,
      height: width * 9 / 16,
      child: ready != null
          ? _view(context, ready)
          : FutureBuilder<TvArt?>(future: TvApps.instance.art(app.package), builder: (context, s) => s.data != null ? _view(context, s.data!) : _fallback(context, null)),
    );
  }

  Widget _view(BuildContext context, TvArt art) {
    if (!art.banner) return _fallback(context, art.image);
    final img = tvSized(art.image, width, context);
    return radius > 0 ? TvRoundImage(image: img, radius: radius) : Image(image: img, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.low);
  }

  Widget _fallback(BuildContext context, ImageProvider? icon) {
    final s = width / TvDS.tileW;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TvMetro.on ? TvMetro.tileFill : TvDS.surface, // Tiles: an accent tile
        borderRadius: radius > 0 ? BorderRadius.circular(radius) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 44 * s,
            child: icon != null
                ? Image(image: tvSized(icon, 44 * s, context), gaplessPlayback: true, filterQuality: FilterQuality.low)
                : DecoratedBox(
                    decoration: TvMetro.on
                        ? BoxDecoration(color: Colors.white24, borderRadius: TvMetro.corners(0))
                        : BoxDecoration(color: DS.hero, shape: BoxShape.circle),
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
  const TvAction(this.icon, this.label, this.onSelect, {this.danger = false, this.keepOpen = false, this.swatch, this.selected = false, this.value});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool danger;
  final bool keepOpen; // e.g. clock presets: try several without reopening
  final Color? swatch; // a colour dot instead of the icon (colour picker)
  final bool selected; // a tick at the end
  final String? value; // current setting, shown on the right ("Artwork")
}

/// Options slide in from the right, like the TV's own menus. The remote's Back goes where the
/// panel's own ← row goes (Back / Cancel: the page it came from), else [onBack], else closes.
/// [refresh] + [build]: a panel that updates in place (e.g. ticking quick actions on and off).
Future<void> showTvPanel(
  BuildContext context, {
  required String title,
  Widget? leading,
  List<TvAction> actions = const [],
  Listenable? refresh,
  List<TvAction> Function()? build,
  VoidCallback? onBack,
  bool pages = false,
}) {
  VoidCallback? back() => onBack ?? (build?.call() ?? actions).where((a) => a.icon == Icons.arrow_back_rounded).firstOrNull?.onSelect;
  // Spotlight: the column is on the right, so the panel comes in on the left — see-through, the
  // picture stays in view behind it.
  final left = TvMetro.prefs?.homeView == 'spotlight';
  return showGeneralDialog(
    context: context,
    barrierDismissible: false, // a tap beside the panel closes it (below); Back goes up a level
    barrierLabel: 'Close',
    barrierColor: left ? const Color(0x33000000) : const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) => PopScope(
      // A row picked or a tap beside the panel closes with `true`; Back on the remote (no result)
      // goes up a level.
      onPopInvokedWithResult: (didPop, picked) {
        if (!didPop || picked != null) return;
        final up = back();
        if (up != null) Future.microtask(up); // once this pop is done (the navigator is busy now)
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => Navigator.pop(ctx, true)),
          ),
          Align(
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            child: Material(
              color: DS.third
                  ? Colors.transparent
                  : (TvMetro.on ? DS.card : (left ? const Color(0xF50E0E0E) : const Color(0xFF1C1C1C))), // Tiles: Metro's near-black, flat
              child: Container(
                decoration: DS.third ? TvReal.panel : null, // Real: a moulded plate
                child: SizedBox(
                  width: 440,
                  height: double.infinity,
                  child: FocusTraversalGroup(
                    child: ListenableBuilder(
                      listenable: refresh ?? const AlwaysStoppedAnimation(0),
                      builder: (ctx, _) {
                        final actions2 = build?.call() ?? actions;
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(DS.s32, 40, DS.s32, 40),
                          children: [
                            if (leading != null) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _roundLead(leading, TvMetro.radius(TvDS.rTile)),
                              ),
                              const SizedBox(height: DS.s16),
                            ],
                            TvMetro.on
                                ? Text(TvMetro.cased(title), style: TvMetro.title(size: 34), maxLines: 2, overflow: TextOverflow.ellipsis)
                                : DS.third
                                ? Text(title.toUpperCase(), style: TvReal.legend(24), maxLines: 2, overflow: TextOverflow.ellipsis)
                                : Text(title, style: TvDS.panelTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: DS.s24),
                            for (final (i, a) in actions2.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: DS.s8),
                                // [pages] (Customise): ← up a level, like Back (the first page stays
                                // open: only Back / Home leave Customise); → opens a row that is a page.
                                child: Focus(
                                  canRequestFocus: false,
                                  skipTraversal: true,
                                  onKeyEvent: !pages
                                      ? null
                                      : (_, e) {
                                          if (e is! KeyDownEvent) return KeyEventResult.ignored;
                                          if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                            if (back() != null) Navigator.pop(ctx); // the PopScope above goes up
                                            return KeyEventResult.handled;
                                          }
                                          final opensPage = a.value == null && !a.keepOpen && !a.danger && a.swatch == null && a.icon != Icons.arrow_back_rounded;
                                          if (e.logicalKey == LogicalKeyboardKey.arrowRight && opensPage) {
                                            Navigator.pop(ctx, true);
                                            a.onSelect();
                                            return KeyEventResult.handled;
                                          }
                                          return KeyEventResult.ignored;
                                        },
                                  child: TvFocusable(
                                  autofocus: i == 0,
                                  onSelect: () {
                                    if (!a.keepOpen) Navigator.pop(ctx, true);
                                    a.onSelect();
                                  },
                                  builder: (context, f) => TvMetro.on
                                      ? _MetroRow(action: a, focused: f)
                                      : AnimatedContainer(
                                          duration: Motion.pressIn * 2,
                                          height: 52,
                                          padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                                          decoration: DS.third
                                              ? TvReal.key(focused: f) // Real: the focused row is a key, lit by its indicator
                                              : BoxDecoration(color: f ? TvDS.surfaceFocused : Colors.transparent, borderRadius: BorderRadius.circular(26)),
                                          child: Row(
                                            children: [
                                              if (a.swatch != null)
                                                Container(
                                                  width: 22,
                                                  height: 22,
                                                  decoration: BoxDecoration(
                                                    color: a.swatch,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: TvDS.line),
                                                  ),
                                                )
                                              else
                                                Icon(
                                                  a.icon,
                                                  size: 22,
                                                  color: a.danger ? DS.alert : (f ? (DS.third ? Tactile.light : TvDS.onLight) : TvDS.inkMuted),
                                                ),
                                              const SizedBox(width: DS.s16),
                                              Expanded(
                                                child: Text(
                                                  a.label,
                                                  style: TvDS.panelRow.copyWith(color: f && !DS.third ? TvDS.onLight : TvDS.ink),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (a.value != null)
                                                Text(
                                                  a.value!,
                                                  style: TvDS.panelRow.copyWith(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w400,
                                                    color: f && !DS.third ? TvDS.onLightMuted : TvDS.inkMuted,
                                                  ),
                                                ),
                                              if (a.selected)
                                                DS.third
                                                    ? Padding(
                                                        padding: const EdgeInsets.only(left: 8),
                                                        child: TLed(on: true, size: 8),
                                                      ) // Real: the chosen one's lamp
                                                    : Icon(Icons.check_rounded, size: 22, color: f ? TvDS.onLight : TvDS.ink),
                                            ],
                                          ),
                                        ),
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
          ),
        ],
      ),
    ),
    transitionBuilder: (ctx, a, _, child) => SlideTransition(
      position: Tween(begin: Offset(left ? -.3 : .3, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: a, child: child),
    ),
  );
}

/// The focus ring, drawn just outside the card with a small gap of background between them, so
/// it stays visible on a white picture or a white app logo.
class TvRing extends Decoration {
  const TvRing({required this.on, required this.radius, this.width = TvDS.focusRing, this.gap = TvDS.focusGap});
  final bool on;
  final double radius, width, gap;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _TvRingPainter(this);
}

class _TvRingPainter extends BoxPainter {
  _TvRingPainter(this.ring);
  final TvRing ring;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    if (!ring.on || configuration.size == null) return;
    final out = ring.gap + ring.width / 2; // centre of the stroke, beyond the gap
    final rect = (offset & configuration.size!).inflate(out);
    if (DS.third) return TvReal.paintRing(canvas, RRect.fromRectAndRadius(rect, Radius.circular(ring.radius + out)), ring.width); // Real: phosphor light
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(ring.radius + out)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.width
        ..color = TvDS.surfaceFocused
        ..isAntiAlias = true,
    );
  }
}

/// [w] with rounded corners: when it is app artwork (bare, or in a SizedBox) the radius goes into
/// the picture ([TvAppArt.radius]); anything else keeps the ClipRRect.
Widget _roundLead(Widget w, double r) {
  if (w is TvAppArt) return TvAppArt(app: w.app, width: w.width, radius: r);
  if (w is SizedBox && w.child is TvAppArt) {
    final a = w.child! as TvAppArt;
    return SizedBox(width: w.width, height: w.height, child: TvAppArt(app: a.app, width: a.width, radius: r));
  }
  return ClipRRect(borderRadius: BorderRadius.circular(r), child: w);
}

/// A calm colour from a name (same name → same colour): used where there's no artwork.
Color tvTint(String name) => HSLColor.fromAHSL(1, (name.hashCode % 360).abs().toDouble(), .38, .42).toColor();

/// Darkens a full-bleed picture into the canvas: from the left (behind text) and the bottom,
/// plus a light veil at the top.
class TvScrims extends StatelessWidget {
  const TvScrims({super.key, this.strength = 1, this.colour, this.cinema = false});
  final double strength; // Customise → Background darkness (×, clamped)
  final Color? colour; // what the picture fades into (default the canvas)

  /// The home's full-screen picture: a dark fade behind the title on the left, a deep one under
  /// the rows, a light veil for the top bar and a soft vignette at the edges, like a cinema screen.
  final bool cinema;

  @override
  Widget build(BuildContext context) {
    // All gradients baked once into one picture (a texture draw per frame, no gradient shaders);
    // re-baked only when the strength / colour / look change.
    final c = colour ?? TvDS.canvas;
    return IgnorePointer(
      child: RepaintBoundary(
        child: TvBaked(painter: _ScrimPainter(strength, c, cinema), id: ('scrims', strength, c.toARGB32(), cinema)),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.strength, this.c, this.cinema);
  final double strength;
  final Color c;
  final bool cinema;

  double a(double x) => (x * strength).clamp(0, 1).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    void fill(Gradient g) => canvas.drawRect(rect, Paint()..shader = g.createShader(rect));
    if (cinema) {
      fill(
        LinearGradient(
          colors: [c.withValues(alpha: a(.88)), c.withValues(alpha: a(.66)), c.withValues(alpha: a(.24)), c.withValues(alpha: 0)],
          stops: const [0, .26, .5, .7],
        ),
      );
      fill(
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.withValues(alpha: a(.5)), c.withValues(alpha: 0), c.withValues(alpha: 0), c.withValues(alpha: a(.72)), c.withValues(alpha: a(.94))],
          stops: const [0, .22, .36, .6, .82],
        ),
      );
      fill(
        RadialGradient(
          center: const Alignment(.3, -.3),
          radius: 1.25,
          colors: [c.withValues(alpha: 0), c.withValues(alpha: 0), c.withValues(alpha: a(.45))],
          stops: const [0, .55, 1],
        ),
      );
      return;
    }
    fill(
      LinearGradient(
        colors: [c, c.withValues(alpha: (.92 * strength).clamp(0, 1)), c.withValues(alpha: (.35 * strength).clamp(0, 1)), c.withValues(alpha: 0)],
        stops: const [0, .3, .55, .75],
      ),
    );
    fill(
      LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          TvDS.scrim.withValues(alpha: (.35 * strength).clamp(0, 1)),
          c.withValues(alpha: 0),
          c.withValues(alpha: (.85 * strength).clamp(0, 1)),
          c,
        ],
        stops: const [0, .2, .58, .74],
      ),
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter o) => o.strength != strength || o.c != c || o.cinema != cinema;
}

/// A pill button: icon (or a small picture) + label (+ quiet detail); white when focused.
class TvActionPill extends StatelessWidget {
  const TvActionPill({super.key, required this.label, required this.onSelect, this.icon, this.leading, this.detail, this.focusNode, this.autofocus = false});
  final String label;
  final String? detail; // e.g. "Stream", "Rent"
  final VoidCallback onSelect;
  final IconData? icon;
  final Widget? leading;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        onSelect: onSelect,
        builder: (context, f) => TvMetro.on
            ? _metro(f)
            : AnimatedContainer(
                duration: Motion.pressIn * 2,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                decoration: BoxDecoration(color: f ? TvDS.surfaceFocused : TvDS.surface, borderRadius: BorderRadius.circular(24)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null)
                      _roundLead(leading!, 6)
                    else if (icon != null)
                      Icon(icon, size: 22, color: f ? TvDS.onLight : TvDS.ink),
                    const SizedBox(width: DS.s12),
                    Text(label, style: TvDS.panelRow.copyWith(fontSize: 15, color: f ? TvDS.onLight : TvDS.ink)),
                    if (detail != null) ...[
                      const SizedBox(width: DS.s8),
                      Text(
                        detail!,
                        style: TvDS.panelRow.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: f ? TvDS.onLightMuted : TvDS.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  /// Tiles: an accent tile button — flat, the tile corners, lowercase; focus is the Metro frame.
  Widget _metro(bool f) => AnimatedContainer(
    duration: Motion.pressIn * 2,
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: DS.s16),
    decoration: BoxDecoration(color: TvMetro.tileFill, borderRadius: TvMetro.corners(0), boxShadow: TvMetro.glow(f)),
    foregroundDecoration: TvMetro.frame(f, width: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) _roundLead(leading!, TvMetro.radius(0)) else if (icon != null) Icon(icon, size: 22, color: Colors.white),
        const SizedBox(width: DS.s12),
        Text(TvMetro.cased(label), style: TvDS.panelRow.copyWith(fontSize: 15, color: Colors.white)),
        if (detail != null) ...[
          const SizedBox(width: DS.s8),
          Text(
            TvMetro.cased(detail!),
            style: TvDS.panelRow.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white70),
          ),
        ],
      ],
    ),
  );
}

/// A side-panel row in Tiles (Metro): the icon on a small accent tile (or a square colour
/// swatch), the label in Metro's case, the value muted; focus is the Metro frame — no white pill.
class _MetroRow extends StatelessWidget {
  const _MetroRow({required this.action, required this.focused});
  final TvAction action;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final a = action, f = focused;
    final r = TvMetro.corners(0);
    return AnimatedContainer(
      duration: Motion.pressIn * 2,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: DS.s12),
      decoration: BoxDecoration(color: f ? const Color(0x14FFFFFF) : Colors.transparent, borderRadius: r, boxShadow: TvMetro.glow(f)),
      foregroundDecoration: TvMetro.frame(f, width: 2),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: a.swatch ?? (a.danger ? DS.alert : TvMetro.accent),
              borderRadius: BorderRadius.circular(TvMetro.radius(0) * .6),
              border: a.swatch != null ? Border.all(color: TvDS.line) : null,
            ),
            child: a.swatch != null ? null : Icon(a.icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: DS.s16),
          Expanded(
            child: Text(
              TvMetro.cased(a.label),
              style: TvDS.panelRow.copyWith(fontWeight: FontWeight.w400, color: a.danger ? DS.alert : Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (a.value != null)
            Text(
              TvMetro.cased(a.value!),
              style: TvDS.panelRow.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: f ? TvMetro.accentText : TvDS.inkMuted),
            ),
          if (a.selected) Icon(Icons.check_rounded, size: 22, color: TvMetro.accentText),
        ],
      ),
    );
  }
}

/// Ask before a reset or clear: Cancel / [action]. Either way [back] (if given) reopens the
/// panel it came from.
void tvConfirm(BuildContext context, {required String title, required String action, required Future<void> Function() onConfirm, VoidCallback? back}) {
  showTvPanel(
    context,
    title: title,
    actions: [
      TvAction(Icons.arrow_back_rounded, 'Cancel', back ?? () {}),
      TvAction(Icons.restart_alt_rounded, action, () async {
        await onConfirm();
        back?.call();
      }, danger: true),
    ],
  );
}
