// CorePalette is marked deprecated upstream but is still what Android hands us.
// ignore_for_file: deprecated_member_use
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../prefs.dart';
import 'ds.dart';
import '../third/tactile/tactile.dart';
import 'palette.dart';

/// Theming like Pixel's "Wallpaper & style":
/// - system:   the phone's Material You colours (from the wallpaper), in any style
/// - basic:    one of 8 fixed colours, in any style
/// - original: One's own green look
/// The Metro accent from a theme colour: saturated enough to read as a colour, dark enough
/// for white type on it (the same rule as Start's tiles).
Color metroAccent(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withSaturation(hsl.saturation < .5 ? .5 : hsl.saturation).withLightness(.38).toColor();
}

class OneTheme extends ChangeNotifier with WidgetsBindingObserver {
  /// The app's theme (the latest made): settings editors draw their home preview with it.
  static OneTheme? current;

  OneTheme(this.prefs) {
    current = this;
    prefs.addListener(_apply);
    WidgetsBinding.instance.addObserver(this); // "Auto" cards follow the phone's dark theme
    _apply();
  }

  @override
  void didChangePlatformBrightness() => _apply();

  /// Dark cards right now? ('auto' asks the phone.)
  bool get darkCards => switch (prefs.cardStyle) {
    'dark' => true,
    'auto' => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
    _ => false,
  };

  final Prefs prefs;
  CorePalette? _system;

  /// Dark cards whatever the setting, for now (the TV remote's page is always dark).
  bool get forceDark => _forceDark;
  bool _forceDark = false;
  set forceDark(bool on) {
    if (on == _forceDark) return;
    _forceDark = on;
    _apply();
  }

  /// Material You available on this phone (Android 12+)?
  bool get hasSystem => _system != null;
  Color? get systemSeed => _system == null ? null : Color(_system!.primary.get(40));

  static const basicSeeds = <Color>[
    Color(0xFF4285F4), // blue
    Color(0xFF00897B), // teal
    Color(0xFF34A853), // green
    Color(0xFFFBBC04), // yellow
    Color(0xFFFF7043), // orange
    Color(0xFFEA4335), // red
    Color(0xFFE91E63), // pink
    Color(0xFF9C27B0), // purple
  ];

  static const styles = <String, (String, DynamicSchemeVariant)>{
    'tonal': ('Tonal', DynamicSchemeVariant.tonalSpot),
    'vibrant': ('Vibrant', DynamicSchemeVariant.vibrant),
    'expressive': ('Expressive', DynamicSchemeVariant.expressive),
    'neutral': ('Neutral', DynamicSchemeVariant.neutral),
    'monochrome': ('Mono', DynamicSchemeVariant.monochrome),
  };

  /// Re-read the phone's colours (call on start and when the launcher comes back: the
  /// wallpaper may have changed).
  Future<void> refreshSystem() async {
    try {
      _system = await DynamicColorPlugin.getCorePalette();
    } catch (_) {
      _system = null;
    }
    _apply();
  }

  /// Light scheme for a choice (swatches show its primary / secondary / tertiary).
  ColorScheme? schemeFor(String source, {int? seed, String style = 'tonal'}) {
    final variant = styles[style]?.$2 ?? DynamicSchemeVariant.tonalSpot;
    if (source == 'system') {
      final sys = _system;
      if (sys == null) return null;
      if (variant == DynamicSchemeVariant.tonalSpot) return _fromCore(sys, Brightness.light);
      return ColorScheme.fromSeed(seedColor: Color(sys.primary.get(40)), dynamicSchemeVariant: variant);
    }
    if (source == 'basic') return ColorScheme.fromSeed(seedColor: Color(seed ?? basicSeeds.first.toARGB32()), dynamicSchemeVariant: variant);
    return null;
  }

  /// The palette for a given choice (also used to draw the swatches).
  OnePalette paletteFor(String source, {int? seed, String style = 'tonal', bool darkCards = false}) {
    final variant = styles[style]?.$2 ?? DynamicSchemeVariant.tonalSpot;
    switch (source) {
      case 'system':
        final sys = _system;
        if (sys == null) return darkCards ? OnePalette.originalDark : OnePalette.original;
        // Tonal = exactly the phone's own scheme; other styles re-derive from its main colour.
        if (variant == DynamicSchemeVariant.tonalSpot) {
          return OnePalette.fromSchemes(_fromCore(sys, Brightness.light), _fromCore(sys, Brightness.dark), darkCards: darkCards);
        }
        return OnePalette.fromSeed(Color(sys.primary.get(40)), variant, darkCards: darkCards);
      case 'basic':
        return OnePalette.fromSeed(Color(seed ?? basicSeeds.first.toARGB32()), variant, darkCards: darkCards);
      default:
        return darkCards ? OnePalette.originalDark : OnePalette.original;
    }
  }

  /// The phone's own Material You scheme, built from its tonal palettes with the standard
  /// Material 3 tone mapping (so it matches the system exactly).
  static ColorScheme _fromCore(CorePalette p, Brightness b) {
    Color t(TonalPalette pal, int tone) => Color(pal.get(tone));
    final light = b == Brightness.light;
    return ColorScheme(
      brightness: b,
      primary: t(p.primary, light ? 40 : 80),
      onPrimary: t(p.primary, light ? 100 : 20),
      primaryContainer: t(p.primary, light ? 90 : 30),
      onPrimaryContainer: t(p.primary, light ? 10 : 90),
      secondary: t(p.secondary, light ? 40 : 80),
      onSecondary: t(p.secondary, light ? 100 : 20),
      secondaryContainer: t(p.secondary, light ? 90 : 30),
      onSecondaryContainer: t(p.secondary, light ? 10 : 90),
      tertiary: t(p.tertiary, light ? 40 : 80),
      onTertiary: t(p.tertiary, light ? 100 : 20),
      tertiaryContainer: t(p.tertiary, light ? 90 : 30),
      onTertiaryContainer: t(p.tertiary, light ? 10 : 90),
      error: t(p.error, light ? 40 : 80),
      onError: t(p.error, light ? 100 : 20),
      surface: t(p.neutral, light ? 98 : 6),
      onSurface: t(p.neutral, light ? 10 : 90),
      onSurfaceVariant: t(p.neutralVariant, light ? 30 : 80),
      outline: t(p.neutralVariant, light ? 50 : 60),
      outlineVariant: t(p.neutralVariant, light ? 80 : 30),
      surfaceContainerLowest: t(p.neutral, light ? 100 : 4),
      surfaceContainerLow: t(p.neutral, light ? 96 : 10),
      surfaceContainer: t(p.neutral, light ? 94 : 12),
      surfaceContainerHigh: t(p.neutral, light ? 92 : 17),
      surfaceContainerHighest: t(p.neutral, light ? 90 : 22),
    );
  }

  String _key = '';

  void _apply() {
    final source = prefs.themeSource == 'system' && !hasSystem ? 'original' : prefs.themeSource;
    final dark = darkCards || _forceDark;
    final lang = DesignLanguage.of(prefs.homeView);
    final tactile = '${prefs.tactileFinish}|${prefs.tactileLight}|${prefs.tactileCap}|${prefs.tactileLightness}|${prefs.tactileLightnessDark}|${prefs.tactileSounds}|${prefs.tactileFace}|$_forceDark|${WidgetsBinding.instance.platformDispatcher.platformBrightness}';
    final key = '$source|${prefs.themeSeed}|${prefs.themeStyle}|${systemSeed?.toARGB32()}|$dark|$lang|${prefs.tileRadius}|$tactile';
    if (key == _key) return;
    _key = key;
    final palette = paletteFor(source, seed: prefs.themeSeed, style: prefs.themeStyle, darkCards: dark);
    // The Tiles view speaks Metro everywhere (docs/DESIGN_LANGUAGES.md): its own palette from
    // the theme's colour, corners from the tile setting.
    // Real's plastic (its own setting, not the card style).
    final finish = _forceDark
        ? 'graphite'
        : (prefs.tactileFinish == 'auto'
              ? (WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark ? 'graphite' : 'porcelain')
              : prefs.tactileFinish);
    DS.lang = lang;
    DS.metroRadius = prefs.tileRadius;
    DS.palette = switch (lang) {
      DesignLanguage.metro => OnePalette.metro(metroAccent(palette.hero)),
      // Tactile has its own theming (Settings → Look → Tactile style), not the Material one.
      DesignLanguage.third => Tactile.palette(
        palette,
        finish: finish,
        light: prefs.tactileLight,
        cap: prefs.tactileCap,
        lightness: finish == 'graphite' ? prefs.tactileLightnessDark : prefs.tactileLightness,
        sounds: prefs.tactileSounds,
        face: prefs.tactileFace,
      ),
      DesignLanguage.classic => palette,
    };
    notifyListeners();
  }

  @override
  void dispose() {
    prefs.removeListener(_apply);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
