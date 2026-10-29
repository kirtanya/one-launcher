import 'package:flutter/material.dart';

/// The colours that follow the theme. Everything else in DS (wallpaper text, alert, dot) is fixed.
class OnePalette {
  const OnePalette({
    required this.canvas,
    Color? sheet,
    Color? base,
    required this.card,
    required this.cardMuted,
    required this.hero,
    required this.heroSoft,
    required this.heroInk,
    required this.heroMuted,
    required this.heroDivider,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.hairline,
  }) : sheet = sheet ?? canvas,
       base = base ?? card;

  /// The lowest surface (Material's surfaceContainerLowest): the nav / search bar and the
  /// Remote and Settings pages.
  final Color base;

  /// The phone's app sheet behind the cards: light with light cards, else the dark [canvas]
  /// (which the TV and other dark surfaces keep using).
  final Color sheet;
  final Color canvas, card, cardMuted;
  final Color hero, heroSoft, heroInk, heroMuted, heroDivider;
  final Color ink, inkMuted, inkFaint, hairline;

  /// Metro (the Tiles view's language): black canvas, near-black panels, white type, the
  /// [accent] as the one colour.
  factory OnePalette.metro(Color accent) => OnePalette(
    canvas: const Color(0xFF000000),
    base: const Color(0xFF000000),
    card: const Color(0xFF1B1B1B),
    cardMuted: const Color(0xFF2A2A2A),
    hero: accent,
    heroSoft: accent.withValues(alpha: .28),
    heroInk: const Color(0xFFFFFFFF),
    heroMuted: const Color(0xB3FFFFFF),
    heroDivider: const Color(0x40FFFFFF),
    ink: const Color(0xFFFFFFFF),
    inkMuted: const Color(0xFFA3A3A3),
    inkFaint: const Color(0xFF6E6E6E),
    hairline: const Color(0xFF383838),
  );

  /// The third view's palette, made from the theme's [base] (being designed: [base] as is, until
  /// its own colours are set).
  factory OnePalette.third(OnePalette base) => base;

  /// "One original": the look extracted from the first reference (see docs/DESIGN_STYLE.md).
  static const original = OnePalette(
    canvas: Color(0xFF1F1F1F),
    sheet: Color(0xFFEBEBEB),
    card: Color(0xFFFFFFFF),
    cardMuted: Color(0xFFF6F5F8),
    hero: Color(0xFFCFE9BC),
    heroSoft: Color(0xFFDFF2D1),
    heroInk: Color(0xFF0D1F00),
    heroMuted: Color(0xFF7E956D),
    heroDivider: Color(0xFFB4C99E),
    ink: Color(0xFF1F1F1F),
    inkMuted: Color(0xFF8F8F8F),
    inkFaint: Color(0xFFB8B8B8),
    hairline: Color(0xFFE6E6E6),
  );

  /// "One original" with dark cards: charcoal cards, deep green hero, light text.
  static const originalDark = OnePalette(
    canvas: Color(0xFF111111),
    base: Color(0xFF111111),
    card: Color(0xFF262626),
    cardMuted: Color(0xFF1E1E1E),
    hero: Color(0xFF2E4724),
    heroSoft: Color(0xFF3B5A2F),
    heroInk: Color(0xFFD6EEC4),
    heroMuted: Color(0xFF9DB88A),
    heroDivider: Color(0xFF46633A),
    ink: Color(0xFFF2F2F2),
    inkMuted: Color(0xFFA8A8A8),
    inkFaint: Color(0xFF7C7C7C),
    hairline: Color(0xFF3A3A3A),
  );

  /// Maps a Material 3 scheme onto One's roles, keeping One's structure: a dark tinted sheet,
  /// tinted cards (light, or dark with [darkCards]) and a primary tint as the hero card (the
  /// primary container on dark cards; 20 % primary over white on light ones).
  factory OnePalette.fromSchemes(ColorScheme light, ColorScheme dark, {bool darkCards = false}) {
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    if (darkCards) {
      return OnePalette(
        canvas: dark.surfaceContainerLowest,
        base: dark.surfaceContainerLowest,
        card: dark.surfaceContainerHigh,
        cardMuted: dark.surfaceContainer,
        hero: dark.primaryContainer,
        heroSoft: mix(dark.primaryContainer, dark.onPrimaryContainer, .14),
        heroInk: dark.onPrimaryContainer,
        heroMuted: mix(dark.onPrimaryContainer, dark.primaryContainer, .4),
        heroDivider: mix(dark.onPrimaryContainer, dark.primaryContainer, .75),
        ink: dark.onSurface,
        inkMuted: dark.onSurfaceVariant,
        inkFaint: dark.outline,
        hairline: dark.outlineVariant,
      );
    }
    // Light cards: the hero is the primary at 20 % over the card white (solid, so glass and
    // shadows stay clean) — the primary container read too bright against the light cards.
    final hero = mix(light.surfaceContainerLowest, light.primary, .2);
    return OnePalette(
      canvas: dark.surfaceContainerLow,
      sheet: light.surfaceContainerHighest,
      base: light.surfaceContainerLowest,
      card: light.surfaceContainerLowest,
      cardMuted: light.surfaceContainer,
      hero: hero,
      heroSoft: mix(hero, light.surfaceContainerLowest, .45),
      heroInk: light.onPrimaryContainer,
      heroMuted: mix(light.onPrimaryContainer, hero, .45),
      heroDivider: mix(light.onPrimaryContainer, hero, .78),
      ink: light.onSurface,
      inkMuted: light.onSurfaceVariant,
      inkFaint: light.outline,
      hairline: light.outlineVariant,
    );
  }

  factory OnePalette.fromSeed(Color seed, DynamicSchemeVariant variant, {bool darkCards = false}) => OnePalette.fromSchemes(
    ColorScheme.fromSeed(seedColor: seed, dynamicSchemeVariant: variant),
    ColorScheme.fromSeed(seedColor: seed, dynamicSchemeVariant: variant, brightness: Brightness.dark),
    darkCards: darkCards,
  );
}
