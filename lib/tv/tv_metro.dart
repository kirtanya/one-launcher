import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../prefs.dart';
import '../ui/ds.dart';
import '../ui/palette.dart';
import '../ui/theme.dart';
import 'tv_ds.dart';
import 'tv_settings.dart';

/// The Tiles (Metro) design language on TV, in one place (docs/DESIGN_LANGUAGES.md).
///
/// When the home view is Tiles ([on]), every TV screen — search, a title's page, All apps, side
/// panels, editors — reads its look from here: lowercase light titles, accent section headers,
/// flat squares with the tile corners, accent tile buttons, a frame for focus instead of a white
/// pill. Cinematic (off) keeps its own look: callers branch on [on] and pass their classic values.
class TvMetro {
  /// Tiles' settings that aren't in [TvLook] (tile transparency, glass…). Set by the TV app.
  static Prefs? prefs;

  /// Tiles view on (set by OneTheme from the home view).
  static bool get on => DS.metro;

  /// Corners: the tile corner setting in Tiles, else [classic].
  static double radius(double classic) => on ? DS.metroRadius : classic;
  static BorderRadius corners(double classic) => BorderRadius.circular(radius(classic));

  /// The one accent (fills) and the accent as text (lightened to read on black).
  static Color get accent => DS.hero;
  static Color get accentText => DS.accentText;

  /// A tile's fill: the accent with the tiles' transparency.
  static Color get tileFill => accent.withValues(alpha: prefs?.tileOpacity ?? 1);

  /// Text in Metro's case (Customise → Tiles → Text case): lowercase, or as named.
  static String cased(String text) => on && TvLook.str('tileCase') == 'lower' ? text.toLowerCase() : text;

  /// The focus frame's colour (Customise → Tiles → Focus colour).
  static Color get focus => TvLook.str('tileFocusColour') == 'accent' ? accentText : Colors.white;

  /// Focus look (Customise → Tiles → Focus): 'frame', 'glow' (frame + soft light) or 'lift'.
  static String get focusStyle => TvLook.str('tileFocus');

  /// A focused tile's frame (and glow), as a foreground decoration.
  static BoxDecoration frame(bool focused, {double width = 3, double? r}) => BoxDecoration(
    borderRadius: BorderRadius.circular(r ?? DS.metroRadius),
    border: Border.all(color: focused && focusStyle != 'lift' ? focus : Colors.transparent, width: width),
  );

  /// The glow under a focused tile ('glow' focus only).
  static List<BoxShadow>? glow(bool focused) =>
      focused && focusStyle == 'glow' ? [BoxShadow(color: focus.withValues(alpha: .45), blurRadius: 22, spreadRadius: 1)] : null;

  /// Big light page title ("search", "all apps").
  static TextStyle title({double size = 44}) =>
      TextStyle(fontFamily: DS.font, fontSize: size, fontWeight: FontWeight.w300, height: 1.05, letterSpacing: -size / 44, color: Colors.white);

  /// Section headers: lowercase, light, in the accent (Customise → Tiles → Row headings).
  static TextStyle get header => TextStyle(
    fontFamily: DS.font,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    height: 1.1,
    color: TvLook.str('tileHeadings') == 'white' ? Colors.white : accentText,
  );

  /// Classic [style] in Cinematic; Metro's header in Tiles.
  static TextStyle headerOr(TextStyle style) => on ? header : style;

  /// Panels: near-black, flat.
  static const panel = Color(0xFF111111);

  /// The Metro accent for a colour choice (Customise → Colours). Keeps every choice apart: the
  /// colour's hue, a chroma per style (Tonal calm-vivid, Vibrant full, Neutral muted, Mono grey),
  /// a tone dark enough for white type — so Red ≠ Orange ≠ Pink and each style looks different.
  static Color accentFor(OneTheme theme, Prefs p, {String? source, int? seed, String? style}) {
    final src0 = source ?? p.themeSource;
    final src = src0 == 'system' && !theme.hasSystem ? 'original' : src0;
    final st = style ?? p.themeStyle;
    final scheme = theme.schemeFor(src, seed: seed ?? p.themeSeed, style: st);
    if (scheme == null) return metroAccent(OnePalette.original.hero); // One original: its green
    final hct = Hct.fromInt(scheme.primary.toARGB32());
    final chroma = switch (st) {
      'vibrant' => 120.0, // as vivid as the screen can show
      'neutral' => 16.0,
      'monochrome' => 0.0,
      _ => 64.0, // tonal, expressive (its own hue)
    };
    // Yellows only read as yellow when light; everything else sits dark enough for white text.
    final h = hct.hue;
    final tone = chroma > 0 && h >= 70 && h <= 112 ? 56.0 : 42.0;
    return Color(Hct.from(h, chroma, tone).toInt());
  }

  /// Puts the TV's Metro accent into the palette (Tiles only). Called whenever the theme changes.
  static void apply(OneTheme theme, Prefs p) {
    if (!DS.metro) return;
    final a = accentFor(theme, p);
    if (DS.palette.hero != a) DS.palette = OnePalette.metro(a);
  }

  /// White-ish surface for small things (fields): flat, the tile corners.
  static Color get field => TvDS.surface;
}
