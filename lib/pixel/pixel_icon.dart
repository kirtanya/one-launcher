import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../apps.dart';
import '../widgets.dart';

/// Pixel view's app icon: the app's icon cut to the chosen shape (Settings → Icon shape),
/// an optional notification dot and an optional label under it — Pixel's home / drawer icon.
class PixelIcon extends StatelessWidget {
  const PixelIcon({
    super.key,
    required this.app,
    required this.size,
    this.shape = 'circle',
    this.label = true,
    this.dot = false,
    this.labelColor = Colors.white,
    this.shadow = true,
  });
  final AppEntry app;
  final double size;
  final String shape;
  final bool label, dot;
  final Color labelColor;

  /// Label shadow, for labels on the wallpaper (off in the drawer).
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final icon = SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipPath(clipper: PixelShape(shape), child: AppIcon(app, size: size)),
          if (dot)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: size * .22,
                height: size * .22,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
    if (!label) return Semantics(label: app.label, child: icon);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: 6),
        SizedBox(
          width: size * 1.45,
          child: Text(
            app.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.2,
              color: labelColor,
              shadows: shadow ? const [Shadow(blurRadius: 4, color: Color(0x99000000))] : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// The icon shapes in [pixelShapes] as a clip path (also used for folder backs).
class PixelShape extends CustomClipper<Path> {
  const PixelShape(this.shape);
  final String shape;

  @override
  Path getClip(Size s) => pathFor(shape, s);

  static Path pathFor(String shape, Size s) {
    final r = Offset.zero & s;
    switch (shape) {
      case 'square':
        return Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(s.width * .12)));
      case 'squircle':
        return Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(s.width * .3)));
      case 'arch':
        final w = s.width / 2;
        return Path()
          ..moveTo(0, s.height)
          ..lineTo(0, w)
          ..arcToPoint(Offset(s.width, w), radius: Radius.circular(w))
          ..lineTo(s.width, s.height)
          ..close();
      case 'clover':
      case 'scallop':
        final lobes = shape == 'clover' ? 4 : 12;
        final depth = shape == 'clover' ? .12 : .045;
        final c = r.center;
        final path = Path();
        const steps = 180;
        for (var i = 0; i <= steps; i++) {
          final t = i / steps * 2 * math.pi;
          final rad = s.width / 2 * (1 - depth + depth * math.cos(lobes * t));
          final p = c + Offset(math.cos(t) * rad, math.sin(t) * rad);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        return path..close();
      default:
        return Path()..addOval(r);
    }
  }

  @override
  bool shouldReclip(PixelShape old) => old.shape != shape;
}
