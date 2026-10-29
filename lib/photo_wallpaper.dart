import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'prefs.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'ui/photo_file.dart';

/// The part of the screen where the photo is actually seen: the Classic view's top area above
/// the app sheet, or the whole screen behind Tiles.
double photoWindow(Prefs p, Size screen, {bool tiles = false}) => tiles ? screen.height : screen.height * p.topShare;

/// Where the photo is drawn: it covers the visible window (full width, [windowH] tall) at
/// [zoom]; x / y (−1…1) choose which part of the photo fills that window.
Rect photoRect(Size img, Size screen, double windowH, double zoom, double x, double y) {
  final s = math.max(screen.width / img.width, windowH / img.height) * zoom;
  final w = img.width * s, h = img.height * s;
  return Rect.fromLTWH(-(w - screen.width) * (x + 1) / 2, -(h - windowH) * (y + 1) / 2, w, h);
}

/// The user's own photo behind the launcher (Settings → Wallpaper → Your photo), framed by
/// zoom / position / blur. Draws nothing when the phone wallpaper is used.
///
/// Cheap per frame: the photo is decoded at about screen size, and blur is baked once into a
/// small image (re-made only when the blur setting changes) instead of a live blur filter.
class PhotoWallpaper extends StatefulWidget {
  const PhotoWallpaper({super.key, required this.prefs, this.fullScreen = false});
  final Prefs prefs;

  /// Fill the whole screen (Tiles view) instead of the classic view's top window.
  final bool fullScreen;

  /// Pixel size of the decoded photo (the editor needs its shape to turn drags into position).
  static final size = ValueNotifier<Size?>(null);

  @override
  State<PhotoWallpaper> createState() => _PhotoWallpaperState();
}

class _PhotoWallpaperState extends State<PhotoWallpaper> {
  String? _path;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _sharp, _blurred;
  double _blurDone = 0;
  int _job = 0;

  @override
  void initState() {
    super.initState();
    widget.prefs.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    widget.prefs.removeListener(_sync);
    _unlisten();
    _blurred?.dispose();
    super.dispose();
  }

  void _unlisten() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  void _sync() {
    if (!mounted) return;
    final path = widget.prefs.wallpaperPhoto;
    if (path != _path) {
      _path = path;
      _unlisten();
      _sharp = null;
      _blurred?.dispose();
      _blurred = null;
      final file = path == null ? null : photoFile(path);
      if (file != null) {
        final px = MediaQuery.sizeOf(context).height * MediaQuery.devicePixelRatioOf(context);
        // At most 2048 px on the long side: plenty for the top window even zoomed, and a texture
        // budget phones handle (a full 1.5× screen decode was ~40 MB of GPU memory).
        final cap = math.min(2048, (px * 1.2).round());
        _stream = ResizeImage(file, width: cap, height: cap, policy: ResizeImagePolicy.fit).resolve(createLocalImageConfiguration(context));
        _listener = ImageStreamListener((info, _) {
          if (!mounted) return;
          setState(() => _sharp = info.image);
          PhotoWallpaper.size.value = Size(info.image.width.toDouble(), info.image.height.toDouble());
          _bake();
        });
        _stream!.addListener(_listener!);
      }
      setState(() {});
    } else {
      if (widget.prefs.photoBlur != _blurDone) _bake();
      setState(() {}); // zoom / position
    }
  }

  /// Blur baked into a small copy: blurring a quarter-size image then stretching it back
  /// looks the same as a big blur and costs nothing while scrolling.
  Future<void> _bake() async {
    final src = _sharp;
    final blur = widget.prefs.photoBlur;
    final job = ++_job;
    if (src == null || blur < .5) {
      _blurDone = blur;
      setState(() {
        _blurred?.dispose();
        _blurred = null;
      });
      return;
    }
    final w = (src.width / 4).clamp(1, 480).round();
    final h = (src.height * w / src.width).round().clamp(1, 4096);
    final sigma = blur * w / 400; // the setting is in screen points (~400 wide)
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
    );
    final img = await rec.endRecording().toImage(w, h);
    if (!mounted || job != _job) {
      img.dispose();
      return;
    }
    _blurDone = blur;
    setState(() {
      _blurred?.dispose();
      _blurred = img;
    });
  }

  @override
  Widget build(BuildContext context) {
    final img = _blurred ?? _sharp;
    if (_path == null || img == null) return const SizedBox.shrink();
    final p = widget.prefs;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PhotoPainter(
          img,
          Size(_sharp!.width.toDouble(), _sharp!.height.toDouble()),
          widget.fullScreen ? 1.0 : p.topShare,
          p.photoFrame(tiles: widget.fullScreen).$1,
          p.photoFrame(tiles: widget.fullScreen).$2,
          p.photoFrame(tiles: widget.fullScreen).$3,
        ),
      ),
    );
  }
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter(this.img, this.full, this.share, this.zoom, this.x, this.y);
  final ui.Image img; // may be the small blurred copy
  final Size full; // the photo's real shape
  final double share, zoom, x, y;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000)); // under a short photo
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final dst = photoRect(full, size, size.height * share, zoom, x, y);
    if (dst.bottom >= size.height - .5) {
      canvas.drawImageRect(img, src, dst, paint);
      return;
    }
    // Classic frames the photo for the top window only; the app sheet hides the rest, but the
    // Today panel shows the whole screen. Below the framed photo: the same photo covering the
    // whole screen, with the framed one fading into it (the top stays exactly as framed).
    canvas.drawImageRect(img, src, photoRect(full, size, size.height, 1, 0, 0), paint);
    final fade = math.min(dst.height * .25, 160.0);
    canvas.saveLayer(dst, Paint());
    canvas.drawImageRect(img, src, dst, paint);
    canvas.drawRect(
      Rect.fromLTRB(dst.left, dst.bottom - fade, dst.right, dst.bottom),
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(Offset(0, dst.bottom - fade), Offset(0, dst.bottom), const [Color(0xFF000000), Color(0x00000000)]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PhotoPainter o) => o.img != img || o.share != share || o.zoom != zoom || o.x != x || o.y != y;
}

/// Full-screen photo framing, like setting a lock-screen wallpaper: drag to move, pinch to
/// zoom, blur slider at the bottom. Saves as you go; Reset puts it back centred. Frames for
/// the view in use: Classic's top window (the rest shaded, as its apps cover it), or the whole
/// screen with a ghost of Start's tiles for Tiles.
Future<void> showPhotoEditor(BuildContext context, {required Prefs prefs}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    transitionDuration: Motion.snapDuration,
    reverseTransitionDuration: Motion.snapDuration,
    pageBuilder: (_, _, _) => _PhotoEditor(prefs: prefs, tiles: prefs.homeView == 'tiles'),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ),
);

class _PhotoEditor extends StatefulWidget {
  const _PhotoEditor({required this.prefs, required this.tiles});
  final Prefs prefs;
  final bool tiles;

  @override
  State<_PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<_PhotoEditor> {
  late double _zoom0;
  late Offset _at0;
  Offset _focal0 = Offset.zero;

  void _start(ScaleStartDetails d) {
    final (zoom, x, y) = widget.prefs.photoFrame(tiles: widget.tiles);
    _zoom0 = zoom;
    _at0 = Offset(x, y);
    _focal0 = d.focalPoint;
  }

  void _update(ScaleUpdateDetails d) {
    final p = widget.prefs;
    final screen = MediaQuery.sizeOf(context);
    final img = PhotoWallpaper.size.value ?? screen;
    final zoom = (_zoom0 * d.scale).clamp(1.0, 3.0);
    // The photo covers the visible window; at zoom z it overflows that window on each axis.
    // Moving x / y from −1 to 1 slides it across that whole overflow.
    final (z0, x0, y0) = p.photoFrame(tiles: widget.tiles);
    final win = photoWindow(p, screen, tiles: widget.tiles);
    final r = photoRect(img, screen, win, zoom, 0, 0);
    final over = Size(r.width - screen.width, r.height - win);
    final drag = d.focalPoint - _focal0;
    final x = over.width < 1 ? x0 : (_at0.dx - 2 * drag.dx / over.width).clamp(-1.0, 1.0);
    final y = over.height < 1 ? y0 : (_at0.dy - 2 * drag.dy / over.height).clamp(-1.0, 1.0);
    if ((zoom - 1).abs() < .01 && (z0 - 1).abs() >= .01 || (zoom - 3).abs() < .01 && (z0 - 3).abs() >= .01) {
      HapticFeedback.selectionClick(); // hit the zoom limit
    }
    p.setPhotoFrame(zoom: zoom, x: x, y: y, tiles: widget.tiles);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prefs;
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onScaleStart: _start,
            onScaleUpdate: _update,
            onDoubleTap: () {
              HapticFeedback.lightImpact();
              p.setPhotoFrame(zoom: 1, x: 0, y: 0, tiles: widget.tiles);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                PhotoWallpaper(prefs: p, fullScreen: widget.tiles),
                ListenableBuilder(
                  listenable: p,
                  builder: (context, _) => ColoredBox(color: Colors.black.withValues(alpha: p.wallpaperDim)),
                ),
              ],
            ),
          ),
          // Tiles: the whole screen shows the photo — a faint ghost of Start's tiles shows
          // where they'll sit, and the tip floats at the top.
          if (widget.tiles) ...[
            IgnorePointer(
              child: _GhostTiles(columns: p.tileColumns, radius: p.tileRadius),
            ),
            Positioned(
              top: pad.top + DS.s16,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s8),
                    decoration: BoxDecoration(color: DS.glass, borderRadius: BorderRadius.circular(DS.s20)),
                    child: Text('Drag to move · pinch to zoom', style: DS.rowSub.copyWith(color: DS.onWallpaper)),
                  ),
                ),
              ),
            ),
          ] else
            // Only the top window is seen on the home screen: the rest is shaded, as the
            // app sheet covers it there. Frame the photo inside the clear part.
            ListenableBuilder(
              listenable: p,
              builder: (context, _) {
                final win = photoWindow(p, MediaQuery.sizeOf(context));
                return Positioned(
                  top: win,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0xB8000000),
                        border: Border(top: BorderSide(color: DS.glassLine, width: 1.5)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: DS.s16),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s8),
                              decoration: BoxDecoration(color: DS.glass, borderRadius: BorderRadius.circular(DS.s20)),
                              child: Text('Drag to move · pinch to zoom', style: DS.rowSub.copyWith(color: DS.onWallpaper)),
                            ),
                            const SizedBox(height: DS.s8),
                            Text('Your apps cover this part', style: DS.rowSub.copyWith(color: DS.onWallpaper.withValues(alpha: .6))),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          // Blur + Reset / Done.
          Positioned(
            left: DS.s16,
            right: DS.s16,
            bottom: pad.bottom + DS.s16,
            child: Container(
              padding: const EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s8, DS.s8),
              decoration: BoxDecoration(color: DS.chipOnWallpaper, borderRadius: BorderRadius.circular(DS.rCard)),
              child: ListenableBuilder(
                listenable: p,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.blur_on_rounded, color: DS.onWallpaper, size: 20),
                        Expanded(
                          child: Slider(
                            value: p.photoBlur,
                            max: 24,
                            activeColor: DS.onWallpaper,
                            inactiveColor: DS.glassLine,
                            thumbColor: DS.onWallpaper,
                            onChanged: (v) {
                              if ((v / 2).round() != (p.photoBlur / 2).round()) HapticFeedback.selectionClick();
                              p.setPhotoFrame(blur: v);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(p.photoBlur < .5 ? 'Off' : '${p.photoBlur.round()}', style: DS.rowSub.copyWith(color: DS.onWallpaper)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            p.setPhotoFrame(zoom: 1, x: 0, y: 0, blur: 0, tiles: widget.tiles);
                          },
                          child: Text('Reset', style: DS.rowTitle.copyWith(color: DS.onWallpaper)),
                        ),
                        const Spacer(),
                        FilledButton(
                          style: DS.third ? null : FilledButton.styleFrom(backgroundColor: DS.onWallpaper, foregroundColor: Colors.black, minimumSize: const Size(96, 44)),
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Done',
                            style: DS.rowTitle.copyWith(color: Colors.black, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A faint outline of a Start screen (clock, then rows of tiles) for framing the photo.
class _GhostTiles extends StatelessWidget {
  const _GhostTiles({required this.columns, required this.radius});
  final int columns;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    const gap = 6.0, side = 12.0;
    final unit = (MediaQuery.sizeOf(context).width - 2 * side - (columns - 1) * gap) / columns;
    Widget cell(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        border: Border.all(color: Colors.white.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    final full = columns * unit + (columns - 1) * gap;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, pad.top + 72, side, 0),
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          cell(full, unit * 2 + gap), // the clock
          for (var i = 0; i < 2; i++) cell(unit * 2 + gap, unit * 2 + gap),
          for (var i = 0; i < columns * 2; i++) cell(unit, unit),
        ],
      ),
    );
  }
}
