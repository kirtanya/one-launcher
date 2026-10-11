import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'prefs.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'ui/photo_file.dart';

/// The user's own photo behind the launcher (Settings → Wallpaper → Your photo), framed by
/// zoom / position / blur. Draws nothing when the phone wallpaper is used.
///
/// Cheap per frame: the photo is decoded at about screen size, and blur is baked once into a
/// small image (re-made only when the blur setting changes) instead of a live blur filter.
class PhotoWallpaper extends StatefulWidget {
  const PhotoWallpaper({super.key, required this.prefs});
  final Prefs prefs;

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
        _stream = ResizeImage(file, height: (px * 1.5).round(), policy: ResizeImagePolicy.fit).resolve(createLocalImageConfiguration(context));
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
    final at = Alignment(p.photoX, p.photoY);
    // Zooming around the chosen spot keeps that part of the photo on screen.
    return RepaintBoundary(
      child: ClipRect(
        child: Transform.scale(
          scale: p.photoZoom,
          alignment: at,
          child: RawImage(image: img, fit: BoxFit.cover, alignment: at, filterQuality: FilterQuality.medium, width: double.infinity, height: double.infinity),
        ),
      ),
    );
  }
}

/// Full-screen photo framing, like setting a lock-screen wallpaper: drag to move, pinch to
/// zoom, blur slider at the bottom. Saves as you go; Reset puts it back centred.
Future<void> showPhotoEditor(BuildContext context, {required Prefs prefs}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    transitionDuration: Motion.snapDuration,
    reverseTransitionDuration: Motion.snapDuration,
    pageBuilder: (_, _, _) => _PhotoEditor(prefs: prefs),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ),
);

class _PhotoEditor extends StatefulWidget {
  const _PhotoEditor({required this.prefs});
  final Prefs prefs;

  @override
  State<_PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<_PhotoEditor> {
  late double _zoom0;
  late Offset _at0;
  Offset _focal0 = Offset.zero;

  void _start(ScaleStartDetails d) {
    final p = widget.prefs;
    _zoom0 = p.photoZoom;
    _at0 = Offset(p.photoX, p.photoY);
    _focal0 = d.focalPoint;
  }

  void _update(ScaleUpdateDetails d) {
    final p = widget.prefs;
    final screen = MediaQuery.sizeOf(context);
    final img = PhotoWallpaper.size.value ?? screen;
    final zoom = (_zoom0 * d.scale).clamp(1.0, 3.0);
    // The photo covers the screen; at zoom z it overflows by (cover·z − screen) on each axis.
    // Moving the alignment from −1 to 1 slides it across that whole overflow.
    final cover = img.width / img.height > screen.width / screen.height
        ? Size(screen.height * img.width / img.height, screen.height)
        : Size(screen.width, screen.width * img.height / img.width);
    final over = Size(cover.width * zoom - screen.width, cover.height * zoom - screen.height);
    final drag = d.focalPoint - _focal0;
    final x = over.width < 1 ? p.photoX : (_at0.dx - 2 * drag.dx / over.width).clamp(-1.0, 1.0);
    final y = over.height < 1 ? p.photoY : (_at0.dy - 2 * drag.dy / over.height).clamp(-1.0, 1.0);
    if ((zoom - 1).abs() < .01 && (p.photoZoom - 1).abs() >= .01 || (zoom - 3).abs() < .01 && (p.photoZoom - 3).abs() >= .01) {
      HapticFeedback.selectionClick(); // hit the zoom limit
    }
    p.setPhotoFrame(zoom: zoom, x: x, y: y);
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
              p.setPhotoFrame(zoom: 1, x: 0, y: 0);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                PhotoWallpaper(prefs: p),
                ListenableBuilder(
                  listenable: p,
                  builder: (context, _) => ColoredBox(color: Colors.black.withValues(alpha: p.wallpaperDim)),
                ),
              ],
            ),
          ),
          // Hint.
          Positioned(
            top: pad.top + DS.s16,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s8),
                  decoration: BoxDecoration(color: DS.chipOnWallpaper, borderRadius: BorderRadius.circular(DS.s20)),
                  child: Text('Drag to move · pinch to zoom', style: DS.rowSub.copyWith(color: DS.onWallpaper)),
                ),
              ),
            ),
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
                            p.setPhotoFrame(zoom: 1, x: 0, y: 0, blur: 0);
                          },
                          child: Text('Reset', style: DS.rowTitle.copyWith(color: DS.onWallpaper)),
                        ),
                        const Spacer(),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: DS.onWallpaper, foregroundColor: Colors.black, minimumSize: const Size(96, 44)),
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
