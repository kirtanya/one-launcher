import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/palette.dart';

/// Tactile — the third view's design language (docs/TACTILE_LANGUAGE.md): surfaces are moulded
/// plastic lit from the top, controls are mechanisms that travel, latch and click, light carries
/// state. This file holds the tokens (finish, depth recipes, light) and the feel (haptics, sound);
/// the parts are in parts.dart.
enum TactileFinish { porcelain, concrete, graphite }

abstract final class Tactile {
  /// Set by OneTheme while the third view is on (light cards → Porcelain, dark → Graphite).
  static TactileFinish finish = TactileFinish.porcelain;

  /// The theme's colour as light: LEDs, lit legends, the knob pointer.
  static Color light = const Color(0xFF2BD9C0);

  /// The theme's hue, tinting the plastic a few percent so it belongs to the wallpaper.
  static Color hue = const Color(0xFF808080);

  /// The coloured cap (null: plain plastic everywhere).
  static Color? cap;

  /// How light the plastic is: 0 darker – 1 lighter (0.5 as moulded).
  static double lightness = .5;

  /// Key clicks on (the phone's touch sound); the haptics always play.
  static bool sounds = true;

  /// Dark plastic: Graphite, or a light finish darkened far enough that it reads as dark (then
  /// its text, shading and LEDs switch over too, so nothing goes dark on dark).
  static bool get dark => finish == TactileFinish.graphite || _dim;
  static bool _dim = false;

  /// The plastic: tinted toward the theme a few percent, then made lighter or darker. Darker goes
  /// a long way (Graphite nearly to black, light finishes to a deep grey); lighter a little.
  static Color _t(Color c) {
    final tinted = Color.lerp(c, hue, .05)!;
    final l = lightness - .5;
    if (l == 0) return tinted;
    final graphite = finish == TactileFinish.graphite;
    final amount = l < 0 ? -l * 2 * (graphite ? .88 : .72) : l * 2 * (graphite ? .35 : .6);
    return Color.lerp(tinted, l > 0 ? Colors.white : Colors.black, amount)!;
  }

  /// The choices offered in Settings → Look → Tactile style.
  static const finishes = [('auto', 'Auto'), ('porcelain', 'Porcelain'), ('concrete', 'Concrete'), ('graphite', 'Graphite')];
  static const lights = <(String, String)>[
    ('theme', 'Theme'),
    ('FF2BC4AE', 'Cyan'),
    ('FFF0962A', 'Amber'),
    ('FFE5484D', 'Red'),
    ('FF5DCB5D', 'Green'),
    ('FF4A86F0', 'Blue'),
    ('FFE8E6E3', 'White'),
  ];
  static const caps = <(String, String)>[
    ('none', 'Plain'),
    ('FFC8443F', 'Red'),
    ('FFD9822B', 'Orange'),
    ('FFD8B23A', 'Yellow'),
    ('FF3F6FC4', 'Blue'),
    ('FF3F8F5A', 'Green'),
  ];

  // ---- Materials (§3) ----
  static Color get panel => _t(switch (finish) {
    TactileFinish.porcelain => const Color(0xFFECEDEF),
    TactileFinish.concrete => const Color(0xFFB7B8BA),
    TactileFinish.graphite => const Color(0xFF2B2A2D),
  });
  static Color get plate => _t(switch (finish) {
    TactileFinish.porcelain => const Color(0xFFF6F7F8),
    TactileFinish.concrete => const Color(0xFFC6C7C9),
    TactileFinish.graphite => const Color(0xFF333236),
  });
  static Color get well => _t(switch (finish) {
    TactileFinish.porcelain => const Color(0xFFE0E2E5),
    TactileFinish.concrete => const Color(0xFFA8A9AC),
    TactileFinish.graphite => const Color(0xFF1F1E21),
  });
  static Color get capTop => _t(switch (finish) {
    TactileFinish.porcelain => const Color(0xFFFFFFFF),
    TactileFinish.concrete => const Color(0xFFD6D7D9),
    TactileFinish.graphite => const Color(0xFF3E3D42),
  });
  static Color get capBottom => _t(switch (finish) {
    TactileFinish.porcelain => const Color(0xFFE4E6E9),
    TactileFinish.concrete => const Color(0xFFA9AAAD),
    TactileFinish.graphite => const Color(0xFF29282C),
  });
  static Color get ink => dark ? const Color(0xFFE2E0E4) : const Color(0xFF26282C);
  static Color get inkMuted => ink.withValues(alpha: .62);
  static Color get ledOff => dark ? const Color(0xFF4A494E) : const Color(0xFFBBBEC3);

  // ---- Light and shade (one light, from the top) ----
  static Color get highlight => dark ? const Color(0x1FFFFFFF) : const Color(0xE6FFFFFF);
  static Color get shade => dark ? const Color(0x99000000) : const Color(0x33000000);
  static Color get shadeSoft => dark ? const Color(0x66000000) : const Color(0x1F000000);
  static Color get rim => dark ? const Color(0x17FFFFFF) : const Color(0x1F000000);

  // ---- Type (§5): its own faces, not Classic's ----

  /// The faces to choose from (Settings → Look → Real style → Type): (id, name, family).
  static const faces = [
    ('barlow', 'Barlow', 'TactileBarlow'), // DIN-like signage: panel legends (default)
    ('chakra', 'Chakra', 'TactileChakra'), // angular, instrument-like
    ('grotesk', 'Grotesk', 'TactileGrotesk'), // Space Grotesk: technical, friendly
    ('plex', 'Plex Mono', 'TactilePlexMono'), // all monospace, like a terminal
    ('system', 'Roboto', 'sans-serif'), // the phone's own
  ];

  /// Body, titles and legends: the chosen face (Classic's Instrument Sans is never used here).
  static String font = 'TactileBarlow';

  /// Legends printed on the panel (upper case, tracked): the same face.
  static String get legendFont => font;

  /// Readouts (values, snackbars, tooltips): Space Mono; displays use the dot matrix.
  static const monoFont = 'TactileSpaceMono';

  /// Printed into the plastic: a hairline of light under the letters (dark finishes: a shade
  /// above them), so text reads as pad-printed, not floating.
  static List<Shadow> get emboss => dark
      ? const [Shadow(color: Color(0x80000000), offset: Offset(0, -.6))]
      : const [Shadow(color: Color(0xB3FFFFFF), offset: Offset(0, .8))];

  /// Signal lights (fixed): alert, warning, ok, info.
  static const alert = Color(0xFFFF4D4D), warning = Color(0xFFFF9F1A), ok = Color(0xFF2BD9A0), info = Color(0xFF3D7BFF);

  /// A raised part's face: lighter at the top, a little darker at the bottom.
  static Gradient capFace([Color? tint]) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: tint == null ? [capTop, capBottom] : [Color.lerp(tint, Colors.white, .18)!, Color.lerp(tint, Colors.black, .12)!],
  );

  /// Level +1 (keys, chips, cards you press): a short contact shadow and a soft one under it.
  static List<BoxShadow> raised({bool pressed = false}) => pressed
      ? [BoxShadow(color: shadeSoft, blurRadius: 2, offset: const Offset(0, 1))]
      : [
          BoxShadow(color: shade, blurRadius: 1.5, offset: const Offset(0, 1)),
          BoxShadow(color: shadeSoft, blurRadius: 8, offset: const Offset(0, 4)),
        ];

  /// Level +1, big (plates): the large soft shadow of ref 2.
  static List<BoxShadow> get plateShadow => [
    BoxShadow(color: shadeSoft, blurRadius: 2, offset: const Offset(0, 1)),
    BoxShadow(color: shadeSoft, blurRadius: 26, offset: const Offset(0, 12)),
  ];

  /// Level +2 (knobs, the floating nav): proud of the panel.
  static List<BoxShadow> get proud => [
    BoxShadow(color: shade, blurRadius: 4, offset: const Offset(0, 2)),
    BoxShadow(color: shadeSoft.withValues(alpha: shadeSoft.a * 1.6), blurRadius: 20, offset: const Offset(0, 10)),
  ];

  /// The third view's palette for the shared components (cards, sheets, text) — Tactile's own
  /// colour system, not Material's. Roles: canvas / sheet = the panel; card / base = plates;
  /// cardMuted = wells; hero = the coloured cap (plain plastic unless one is chosen); ink =
  /// printed legends; the theme's colour is used only as light (LEDs, displays), never as a fill.
  static OnePalette palette(OnePalette base, {required String finish, required String light, required String cap, double lightness = .5, bool sounds = true, String face = 'barlow'}) {
    font = faces.firstWhere((f) => f.$1 == face, orElse: () => faces.first).$3;
    Tactile.finish = TactileFinish.values.firstWhere((f) => f.name == finish, orElse: () => TactileFinish.porcelain);
    Tactile.lightness = lightness;
    _dim = false;
    _dim = finish != 'graphite' && panel.computeLuminance() < .2; // darkened past mid-grey
    Tactile.sounds = sounds;
    final hsl = HSLColor.fromColor(base.hero);
    hue = hsl.withSaturation(hsl.saturation.clamp(.15, .4)).withLightness(.45).toColor();
    // Light: calm, not neon — a little below full brightness, deeper on the light plastics.
    final themeLight = hsl.withSaturation(hsl.saturation < .5 ? .62 : hsl.saturation.clamp(.5, .78)).withLightness(dark ? .56 : .44).toColor();
    Tactile.light = light == 'theme' ? themeLight : Color(int.parse(light, radix: 16));
    Tactile.cap = cap == 'none' ? null : Color(int.parse(cap, radix: 16));
    final hero = Tactile.cap == null ? plate : Color.lerp(Tactile.cap, dark ? Colors.black : Colors.white, .15)!;
    final heroInk = Tactile.cap == null ? ink : (hero.computeLuminance() > .45 ? const Color(0xFF26282C) : const Color(0xFFF4F2EE));
    return OnePalette(
      canvas: panel,
      sheet: panel,
      base: plate,
      card: plate,
      cardMuted: well,
      hero: hero,
      heroSoft: Color.lerp(hero, plate, .5)!,
      heroInk: heroInk,
      heroMuted: heroInk.withValues(alpha: .65),
      heroDivider: heroInk.withValues(alpha: .18),
      ink: ink,
      inkMuted: inkMuted,
      inkFaint: ink.withValues(alpha: .4),
      hairline: rim,
    );
  }
}

/// Draws a recess (level −1 / −2): the floor colour, a shadow cast by the top lip onto the floor,
/// and a highlight on the lower inner wall where the light reaches. Flutter has no inner
/// shadows, so this paints them: a blurred frame around the shape, offset, clipped to it.
class WellPainter extends CustomPainter {
  const WellPainter({required this.radius, required this.floor, this.depth = 2, this.shadow, this.highlight});
  final double radius, depth;
  final Color floor;
  final Color? shadow, highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.drawRRect(rrect, Paint()..color = floor);
    canvas.save();
    canvas.clipRRect(rrect);
    void inner(Color c, Offset o, double blur) {
      final frame = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect((Offset.zero & size).inflate(blur * 4))
        ..addRRect(rrect.shift(o));
      canvas.drawPath(frame, Paint()
        ..color = c
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur));
    }

    inner(shadow ?? (Tactile.dark ? const Color(0xB3000000) : const Color(0x4D000000)), Offset(0, depth * 1.5), depth * 1.6);
    inner(highlight ?? Tactile.highlight, Offset(0, -depth * .6), depth * .5);
    canvas.restore();
    // The lip: a hairline that catches the light at the bottom edge.
    canvas.drawRRect(rrect.deflate(.25), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5
      ..color = Tactile.rim);
  }

  @override
  bool shouldRepaint(WellPainter old) => old.radius != radius || old.floor != floor || old.depth != depth || old.shadow != shadow || old.highlight != highlight;
}

/// How Tactile parts feel: a haptic and the phone's click sound at the moment of contact (touch
/// down for keys; the end wall for a switch; each detent for a knob). Ticks are throttled so a
/// fast drag doesn't buzz. The click follows the phone's "Touch sounds" setting.
abstract final class TactileFeel {
  static int _lastTick = 0;

  /// A key reaching the bottom.
  static void press() {
    HapticFeedback.lightImpact();
    if (Tactile.sounds) SystemSound.play(SystemSoundType.click);
  }

  /// A key coming back up: lighter, no sound.
  static void release() => HapticFeedback.selectionClick();

  /// A latch or a switch landing against its wall.
  static void latch() {
    HapticFeedback.heavyImpact();
    if (Tactile.sounds) SystemSound.play(SystemSoundType.click);
  }

  /// A detent (knob step, a switch crossing its middle).
  static void tick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTick < 35) return;
    _lastTick = now;
    HapticFeedback.selectionClick();
  }
}
