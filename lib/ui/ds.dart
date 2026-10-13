import 'package:flutter/material.dart';

import 'palette.dart';

/// Design tokens extracted from the reference (see docs/DESIGN_STYLE.md).
class DS {
  // ---- Colour ----
  /// Active theme colours (Settings → Colours & style). The app rebuilds when it changes.
  static OnePalette palette = OnePalette.original;

  /// The design language in use (docs/DESIGN_LANGUAGES.md). Classic: soft cards and pills.
  /// Metro (the Tiles view): flat, dark or glass panels, lowercase light titles, accent squares,
  /// corners from the tile corner setting. Set by OneTheme from the home view.
  static bool metro = false;
  static double metroRadius = 0;

  /// [text] in the active language's case (Metro writes headers in lowercase).
  static String cased(String text) => metro ? text.toLowerCase() : text;

  static Color get canvas => palette.canvas;
  static const onCanvas = Color(0xFFFFFFFF);
  static const onCanvasMuted = Color(0x8CFFFFFF); // 55%
  static const onCanvasLine = Color(0x26FFFFFF); // 15%

  static Color get card => palette.card;
  static Color get cardMuted => palette.cardMuted;

  static Color get hero => palette.hero;
  static Color get heroSoft => palette.heroSoft;
  static Color get heroInk => palette.heroInk;
  static Color get heroMuted => palette.heroMuted;
  static Color get heroDivider => palette.heroDivider;

  static Color get ink => palette.ink;
  static Color get inkMuted => palette.inkMuted;
  static Color get inkFaint => palette.inkFaint;
  static Color get hairline => palette.hairline;

  // Over the wallpaper (top half). Light glyphs + a soft shadow so any wallpaper works.
  static const onWallpaper = Color(0xFFFFFFFF);
  static const clockInk = Color(0xE6FFFFFF); // 90%, the clock lets the wallpaper breathe through
  static const glass = Color(0x2EFFFFFF); // frosted circle button fill (18%)
  static const glassLine = Color(0x40FFFFFF); // its hairline (25%)
  static const chipOnWallpaper = Color(0x66141414); // dark frosted pill: readable on any wallpaper (40%)
  // No shadows on wallpaper text: legibility comes from the user's wallpaper dim instead.
  static const wallpaperShadow = <Shadow>[];

  static const alert = Color(0xFFE0624A);
  static const dot = Color(0xFFEF7389);

  // ---- Space ----
  static const gutter = 8.0; // canvas → card
  static const stack = 4.0; // card → card
  static const pad = 20.0; // inside a card
  static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s20 = 20.0, s24 = 24.0, s32 = 32.0, s48 = 48.0;

  // ---- Shape ----
  static double get rCard => metro ? metroRadius : 28.0;
  static double get rMedia => metro ? metroRadius * .6 : 20.0;
  static double get rSheet => metro ? metroRadius : 32.0;
  static const circle = 44.0;
  static const tap = 48.0;
  static const datePillW = 44.0, datePillH = 64.0;
  static const appIcon = 48.0;

  // ---- Type ----
  static const font = 'InstrumentSans';
  static const greeting = TextStyle(fontFamily: font, fontSize: 22, fontWeight: FontWeight.w400, height: 1.15, color: onCanvas);
  static TextStyle get display => TextStyle(fontFamily: font, fontSize: 26, fontWeight: FontWeight.w500, height: 1.2, letterSpacing: -0.5, color: heroInk);
  static TextStyle get title => metro
      // Metro: big, light, tight.
      ? TextStyle(fontFamily: font, fontSize: 30, fontWeight: FontWeight.w300, height: 1.1, letterSpacing: -0.6, color: ink)
      : TextStyle(fontFamily: font, fontSize: 24, fontWeight: FontWeight.w500, height: 1.15, letterSpacing: -0.4, color: ink);
  static TextStyle get eyebrow => metro
      // Metro section headers: the accent, lowercase, light.
      ? TextStyle(fontFamily: font, fontSize: 18, fontWeight: FontWeight.w400, color: hero)
      : TextStyle(fontFamily: font, fontSize: 14, fontWeight: FontWeight.w500, color: ink);
  static TextStyle get rowTitle => TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w600, color: ink);
  static TextStyle get rowSub => TextStyle(fontFamily: font, fontSize: 14, fontWeight: FontWeight.w400, color: inkMuted);
  static TextStyle get meta => TextStyle(fontFamily: font, fontSize: 14, fontWeight: FontWeight.w400, color: inkFaint);
  static const pill = TextStyle(fontFamily: font, fontSize: 12, fontWeight: FontWeight.w600);
  static TextStyle get iconLabel => TextStyle(fontFamily: font, fontSize: 12, fontWeight: FontWeight.w500, color: ink, height: 1.2);

  /// The big clock: tall condensed digits that fill the width (scaled with FittedBox).
  static const clockFont = 'ClockFlex'; // Google Sans Flex, variable: weight / width / slant / roundness (top/header_fonts.dart)
  static const clock = TextStyle(
    fontFamily: clockFont,
    fontSize: 200,
    fontWeight: FontWeight.w300,
    height: 1,
    letterSpacing: -4,
    color: clockInk,
    shadows: wallpaperShadow,
  );
  static const wallpaperDate = TextStyle(fontFamily: font, fontSize: 17, fontWeight: FontWeight.w500, color: onWallpaper, shadows: wallpaperShadow);

  // ---- Motion ----
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 260);
  static const ease = Curves.easeOutCubic;
}
