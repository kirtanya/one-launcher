import 'package:flutter/material.dart';

import '../ui/ds.dart';

/// TV design tokens (10-foot UI). Built on the phone DS (fonts, colours, motion) but sized
/// for a screen across the room: bigger type, 16:9 banner tiles, overscan-safe margins.
/// Sizes are logical pixels on a 960×540 (1080p) TV screen.
class TvDS {
  // ---- Space ----
  /// Overscan-safe margins: some TVs crop the outer ~5% of the picture.
  static const safe = EdgeInsets.fromLTRB(48, 27, 48, 27);
  static const gap = 20.0; // tile → tile

  // ---- Tiles ----
  static const tileW = 176.0, tileH = 99.0; // 16:9, like TV app banners
  static const rTile = 14.0;
  static const focusScale = 1.12;
  static const focusRing = 3.0;

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
  static const surface = Color(0x14FFFFFF); // icon-only tiles, buttons (8% white)
  static const surfaceFocused = Color(0xFFFFFFFF);
  // Text / icons on a focused (white) surface: fixed dark, whatever the theme (Tiles' ink is white).
  static const onLight = Color(0xFF161616);
  static const onLightMuted = Color(0xFF5F5F5F);
  static const glow = Color(0x40FFFFFF);

  // ---- Type (≈1.4× the phone sizes) ----
  static const clockSize = 88.0;
  static const date = TextStyle(fontFamily: DS.font, fontSize: 18, fontWeight: FontWeight.w500, color: inkMuted);
  static const rowTitle = TextStyle(fontFamily: DS.font, fontSize: 17, fontWeight: FontWeight.w600, color: inkMuted);
  static const rowTitleFocused = TextStyle(fontFamily: DS.font, fontSize: 17, fontWeight: FontWeight.w600, color: ink);
  static const label = TextStyle(fontFamily: DS.font, fontSize: 15, fontWeight: FontWeight.w500, color: ink);
  static const hint = TextStyle(fontFamily: DS.font, fontSize: 13, fontWeight: FontWeight.w500, color: ink);
  static const tileName = TextStyle(fontFamily: DS.font, fontSize: 13, fontWeight: FontWeight.w500, color: ink);
  // Hero text sits on full-screen pictures: a soft shadow keeps it readable on bright frames.
  static const heroShadow = [Shadow(color: Color(0x99000000), blurRadius: 18)];
  static const heroEyebrow = TextStyle(
    fontFamily: DS.font,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.4,
    color: inkMuted,
    shadows: heroShadow,
  );
  static const heroTitle = TextStyle(
    fontFamily: DS.font,
    fontSize: 40,
    fontWeight: FontWeight.w600,
    height: 1.05,
    letterSpacing: -.8,
    color: ink,
    shadows: heroShadow,
  );
  static const heroMeta = TextStyle(fontFamily: DS.font, fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xD9FFFFFF), shadows: heroShadow);
  static const heroBody = TextStyle(fontFamily: DS.font, fontSize: 15, fontWeight: FontWeight.w400, height: 1.4, color: inkMuted, shadows: heroShadow);
  static const keycap = TextStyle(fontFamily: DS.font, fontSize: 12, fontWeight: FontWeight.w600, color: ink);
  static const topClock = TextStyle(fontFamily: DS.font, fontSize: 20, fontWeight: FontWeight.w500, color: ink);
  static const panel = Color(0xFF1C1C1C);
  static const scrim = Color(0xFF000000); // backdrop fades into the canvas through this
  static const panelTitle = TextStyle(fontFamily: DS.font, fontSize: 24, fontWeight: FontWeight.w600, color: ink);
  static const panelRow = TextStyle(fontFamily: DS.font, fontSize: 17, fontWeight: FontWeight.w500, color: ink);
}
