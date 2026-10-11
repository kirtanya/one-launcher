import 'package:flutter/material.dart';

/// One Launcher design tokens. Change the look here, not in the screens.
class T {
  // Colours — text sits on top of the user's wallpaper, so it is always light
  // with a soft shadow for legibility on bright wallpapers.
  static const ink = Color(0xFFFFFFFF);
  static const inkMuted = Color(0xB3FFFFFF); // 70%
  static const inkFaint = Color(0x66FFFFFF); // 40%
  static const scrim = Color(0x33000000); // light dim over wallpaper on home
  static const drawer = Color(0xF2101114); // app drawer surface (95%)
  static const sheet = Color(0xFF1B1C20); // bottom sheets
  static const field = Color(0x14FFFFFF); // search field fill (8%)
  static const divider = Color(0x1FFFFFFF);
  static const accent = Color(0xFFFFD84D); // "One" yellow — used once per screen
  static const danger = Color(0xFFFF6B6B);

  static const shadow = [Shadow(color: Color(0x66000000), blurRadius: 12)];

  // Spacing (4pt grid)
  static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s20 = 20.0, s24 = 24.0, s32 = 32.0, s48 = 48.0;

  // Radii
  static const rField = 16.0, rSheet = 28.0, rIcon = 14.0;

  // Sizes
  static const iconApp = 40.0;
  static const tapMin = 48.0;

  // Type
  static const clock = TextStyle(fontSize: 72, fontWeight: FontWeight.w200, height: 1, letterSpacing: -2, color: ink, shadows: shadow);
  static const date = TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: inkMuted, shadows: shadow);
  static const favourite = TextStyle(fontSize: 24, fontWeight: FontWeight.w400, color: ink, shadows: shadow);
  static const appName = TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: ink);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: inkFaint);
  static const body = TextStyle(fontSize: 14, color: inkMuted);

  // Motion
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
}
