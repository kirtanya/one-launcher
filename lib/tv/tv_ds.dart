import 'package:flutter/material.dart';

import '../third/tactile/tactile.dart';
import '../ui/ds.dart';

/// TV design tokens (10-foot UI). Built on the phone DS (fonts, colours, motion) but sized
/// for a screen across the room: bigger type, 16:9 banner tiles, overscan-safe margins.
/// Sizes are logical pixels on a 960×540 (1080p) TV screen.
class TvDS {
  /// Real prints its text into the set (its face, an emboss); other views as they are.
  static TextStyle _f(TextStyle s) => DS.third ? s.copyWith(shadows: [...?s.shadows, ...Tactile.emboss]) : s;

  // ---- Space ----
  /// Overscan-safe margins: some TVs crop the outer ~5% of the picture.
  static const safe = EdgeInsets.fromLTRB(48, 27, 48, 27);
  static const gap = 20.0; // tile → tile

  // ---- Tiles ----
  static const tileW = 176.0, tileH = 99.0; // 16:9, like TV app banners
  static const appCircle = 80.0; // Customise → App cards → Circle: its diameter (under half a banner)
  static const rTile = 14.0;
  static const focusScale = 1.12;
  static const focusRing = 3.0;
  static const focusGap = 3.0; // background between a focused card and its ring

  // ---- Rows ----
  static const headerH = 164.0; // clock + date + buttons
  static const rowTitleH = 28.0;
  static const rowPadTop = 12.0; // room for a focused tile to grow
  static const labelH = 40.0; // focused app name under the tile
  static const rowH = rowTitleH + rowPadTop + tileH + labelH;

  // ---- Cinematic home ----
  static const heroTop = 92.0; // title block, under the top bar
  static const heroW = 470.0;
  static const rowsTop = .55; // rows start at 55% of the screen; the backdrop owns the rest
  static const wideW = 208.0, wideH = 117.0; // shows & films (16:9, bigger than app banners)
  static const cardRowTitleH = 26.0, cardRowPad = 10.0, cardRowGap = 22.0;
  static const focusScaleCard = 1.08;
  static const progressH = 3.0;

  // ---- Colour ----
  static Color get canvas => DS.canvas;
  static const ink = DS.onCanvas;
  static const inkMuted = DS.onCanvasMuted;
  static const line = DS.onCanvasLine;
  // Surfaces by role (Real: the set's keys — plastic at rest, lit by the indicator when focused,
  // legends printed on them; others: 8% white, white when focused, dark text on it).
  static Color get surface => DS.third ? Tactile.capBottom : const Color(0x14FFFFFF); // icon-only tiles, buttons
  static Color get surfaceFocused => DS.third ? Color.lerp(Tactile.capTop, Tactile.light, .22)! : const Color(0xFFFFFFFF);
  // Text / icons on a focused surface: fixed dark, whatever the theme (Tiles' ink is white).
  static Color get onLight => DS.third ? Tactile.ink : const Color(0xFF161616);
  static Color get onLightMuted => DS.third ? Tactile.inkMuted : const Color(0xFF5F5F5F);
  static const glow = Color(0x40FFFFFF);

  // ---- Type (≈1.4× the phone sizes) ----
  static const clockSize = 88.0;
  static TextStyle get date => _f(TextStyle(fontFamily: DS.face, fontSize: 18, fontWeight: FontWeight.w500, color: inkMuted));
  static TextStyle get rowTitle => _f(TextStyle(fontFamily: DS.face, fontSize: 17, fontWeight: FontWeight.w600, color: inkMuted));
  static TextStyle get rowTitleFocused => _f(TextStyle(fontFamily: DS.face, fontSize: 17, fontWeight: FontWeight.w600, color: ink));
  static TextStyle get label => _f(TextStyle(fontFamily: DS.face, fontSize: 15, fontWeight: FontWeight.w500, color: ink));
  static TextStyle get hint => _f(TextStyle(fontFamily: DS.face, fontSize: 13, fontWeight: FontWeight.w500, color: ink));
  static TextStyle get tileName => _f(TextStyle(fontFamily: DS.face, fontSize: 13, fontWeight: FontWeight.w500, color: ink));
  // Hero text sits on full-screen pictures: a soft shadow keeps it readable on bright frames.
  static const heroShadow = [Shadow(color: Color(0x99000000), blurRadius: 18)];
  static TextStyle get heroEyebrow => _f(TextStyle(
    fontFamily: DS.face,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.4,
    color: inkMuted,
    shadows: heroShadow,
  ));
  static TextStyle get heroTitle => _f(TextStyle(
    fontFamily: DS.face,
    fontSize: 40,
    fontWeight: FontWeight.w600,
    height: 1.05,
    letterSpacing: -.8,
    color: ink,
    shadows: heroShadow,
  ));
  static TextStyle get heroMeta => _f(TextStyle(fontFamily: DS.face, fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xD9FFFFFF), shadows: heroShadow));
  static TextStyle get heroBody => _f(TextStyle(fontFamily: DS.face, fontSize: 15, fontWeight: FontWeight.w400, height: 1.4, color: inkMuted, shadows: heroShadow));
  static TextStyle get keycap => _f(TextStyle(fontFamily: DS.face, fontSize: 12, fontWeight: FontWeight.w600, color: ink));
  static TextStyle get topClock => _f(TextStyle(fontFamily: DS.face, fontSize: 20, fontWeight: FontWeight.w500, color: ink));
  static const panel = Color(0xFF1C1C1C);
  static const scrim = Color(0xFF000000); // backdrop fades into the canvas through this
  static TextStyle get panelTitle => _f(TextStyle(fontFamily: DS.face, fontSize: 24, fontWeight: FontWeight.w600, color: ink));
  static TextStyle get panelRow => _f(TextStyle(fontFamily: DS.face, fontSize: 17, fontWeight: FontWeight.w500, color: ink));
}
