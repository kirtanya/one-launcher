import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'perf.dart';

/// Glass look (Settings → Home view → Look): surfaces become frosted panes — the wallpaper
/// blurred behind them, tinted with their usual colour, a thin bright edge and a soft sheen.
/// [classic] is the Classic home's switch; the Frost / Tint / Edge / Sheen values are shared
/// with glass tiles. Kept in sync with prefs by the app (see main.dart).
abstract final class Glass {
  static bool classic = false;
  static bool tiles = false; // glass tiles: Metro sheets and search frost too
  static double blur = 18, tint = .25;
  static bool edge = true, sheen = true;

  /// [c] as a pane's tint: see-through enough for the frost, solid enough for text on it.
  static Color tinted(Color c) => c.withValues(alpha: (.3 + tint).clamp(.25, .92));

  /// [c] tinted when the Classic home is glass, else as is.
  static Color on(Color c) => classic ? tinted(c) : c;

  static BorderSide get edgeSide => edge ? BorderSide(color: Colors.white.withValues(alpha: .35), width: 1) : BorderSide.none;

  static const sheenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x38FFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x14FFFFFF)],
    stops: [0, .45, .75, 1],
  );
}

/// A frosted pane of [shape] behind [child]: blur (unless lighter effects or [frost] is off —
/// e.g. cards inside an already frosted drawer), the tinted [colour], edge and sheen.
class GlassPane extends StatelessWidget {
  const GlassPane({super.key, required this.colour, required this.shape, required this.child, this.frost = true});
  final Color colour;
  final ShapeBorder shape;
  final Widget child;
  final bool frost;

  @override
  Widget build(BuildContext context) {
    final side = Glass.edgeSide;
    final outlined = switch (shape) {
      RoundedRectangleBorder(:final borderRadius) => RoundedRectangleBorder(borderRadius: borderRadius, side: side),
      StadiumBorder() => StadiumBorder(side: side),
      CircleBorder() => CircleBorder(side: side),
      _ => shape,
    };
    final pane = Material(
      color: Glass.tinted(colour),
      shape: outlined,
      clipBehavior: Clip.antiAlias,
      child: Glass.sheen
          ? Stack(
              fit: StackFit.passthrough,
              children: [
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(decoration: BoxDecoration(gradient: Glass.sheenGradient)),
                  ),
                ),
                child,
              ],
            )
          : child,
    );
    if (!frost || Glass.blur <= 0 || Perf.lite.value) return pane;
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: Glass.blur, sigmaY: Glass.blur),
        child: pane,
      ),
    );
  }
}

/// A Classic-home surface: a glass pane when the Classic home is glass, else a plain
/// [Material] of [colour] and [shape].
Widget glassOr({required Color colour, required ShapeBorder shape, required Widget child}) =>
    Glass.classic ? GlassPane(colour: colour, shape: shape, child: child) : Material(color: colour, shape: shape, clipBehavior: Clip.antiAlias, child: child);
