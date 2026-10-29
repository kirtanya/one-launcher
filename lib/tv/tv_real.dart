import 'package:flutter/material.dart';

import '../third/tactile/tactile.dart';

/// Real (Tactile) on the TV: the launcher as an old television set (docs/TACTILE_LANGUAGE.md).
/// The picture sits behind curved CRT glass — scanlines, a vignette that falls off to the
/// tube's rounded corners, a faint phosphor bloom — and the controls are the set's own: keys
/// that light an indicator when focused, a channel-style display for the clock, mechanical
/// clicks from the speaker (TvApps.sound). Shared plastic, light and type come from Tactile.
abstract final class TvReal {
  /// A panel (Customise, menus): a graphite plate with a lit top edge and a moulded rim.
  static BoxDecoration get panel => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(Tactile.plate, Colors.white, .05)!, Tactile.plate, Color.lerp(Tactile.plate, Colors.black, .2)!],
      stops: const [0, .06, 1],
    ),
    border: Border(left: BorderSide(color: Tactile.rim, width: 1)),
    boxShadow: [BoxShadow(color: Tactile.shade, blurRadius: 40, offset: const Offset(-12, 0))],
  );

  /// A focused row / button: a key pressed in, faintly lit by the indicator.
  static BoxDecoration key({required bool focused, double radius = 12}) => BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: focused
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(Tactile.capBottom, Tactile.light, .12)!, Color.lerp(Tactile.capTop, Tactile.light, .08)!],
          )
        : null,
    border: Border.all(color: focused ? Tactile.light.withValues(alpha: .7) : Colors.transparent, width: 1.2),
    boxShadow: focused ? [BoxShadow(color: Tactile.light.withValues(alpha: .35), blurRadius: 18)] : null,
  );

  /// The focus ring: phosphor light around the card (a glow, not a white line).
  static void paintRing(Canvas canvas, RRect r, double width) {
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width + 6
      ..color = Tactile.light.withValues(alpha: .28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * .8
      ..color = Color.lerp(Tactile.light, Colors.white, .35)!);
  }

  static TextStyle legend(double size, {Color? color}) => TextStyle(
    fontFamily: Tactile.legendFont,
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: size * .09,
    color: color ?? Tactile.ink,
    shadows: Tactile.emboss,
  );
}

/// The CRT glass over the whole screen (it never takes a touch or a key): scanlines, the
/// tube's vignette and rounded corners, a slight bloom at the centre. Drawn once and cached.
class CrtGlass extends StatelessWidget {
  const CrtGlass({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _CrtPainter(), size: Size.infinite)));
}

class _CrtPainter extends CustomPainter {
  const _CrtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Scanlines: a faint dark line every 3 px.
    final line = Paint()..color = const Color(0x14000000);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
    // Phosphor bloom: the middle of the tube a touch brighter.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: .035), Colors.transparent], radius: .7).createShader(rect)
        ..blendMode = BlendMode.plus,
    );
    // Vignette: the glass darkens toward the edges, more in the corners.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 1.05,
          colors: [Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: .38), Colors.black.withValues(alpha: .75)],
          stops: const [0, .62, .9, 1],
        ).createShader(rect),
    );
    // The tube's rounded corners and the bezel lip around it.
    final tube = RRect.fromRectAndRadius(rect.deflate(6), const Radius.circular(36));
    canvas.drawDRRect(RRect.fromRectAndRadius(rect.inflate(1), Radius.zero), tube, Paint()..color = const Color(0xFF0B0B0C));
    canvas.drawRRect(
      tube,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: .06),
    );
  }

  @override
  bool shouldRepaint(_CrtPainter old) => false;
}
