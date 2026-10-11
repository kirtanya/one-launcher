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

  // ---- Colour ----
  static Color get canvas => DS.canvas;
  static const ink = DS.onCanvas;
  static const inkMuted = DS.onCanvasMuted;
  static const line = DS.onCanvasLine;
  static const surface = Color(0x14FFFFFF); // icon-only tiles, buttons (8% white)
  static const surfaceFocused = Color(0xFFFFFFFF);
  static const glow = Color(0x40FFFFFF);

  // ---- Type (≈1.4× the phone sizes) ----
  static const clockSize = 88.0;
  static const date = TextStyle(fontFamily: DS.font, fontSize: 18, fontWeight: FontWeight.w500, color: inkMuted);
  static const rowTitle = TextStyle(fontFamily: DS.font, fontSize: 17, fontWeight: FontWeight.w600, color: inkMuted);
  static const rowTitleFocused = TextStyle(fontFamily: DS.font, fontSize: 17, fontWeight: FontWeight.w600, color: ink);
  static const label = TextStyle(fontFamily: DS.font, fontSize: 15, fontWeight: FontWeight.w500, color: ink);
  static const hint = TextStyle(fontFamily: DS.font, fontSize: 13, fontWeight: FontWeight.w500, color: ink);
  static const tileName = TextStyle(fontFamily: DS.font, fontSize: 13, fontWeight: FontWeight.w500, color: ink);
  static const panelTitle = TextStyle(fontFamily: DS.font, fontSize: 24, fontWeight: FontWeight.w600, color: ink);
  static const panelRow = TextStyle(fontFamily: DS.font, fontSize: 17, fontWeight: FontWeight.w500, color: ink);
}
