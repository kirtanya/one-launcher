import 'package:flutter/widgets.dart';

import '../prefs.dart';
import '../ui/ds.dart';

/// The big figures (clock, screen time, battery %, event time) use one variable font,
/// Google Sans Flex, whose weight / width / slant / roundness the user tunes — like the Pixel
/// or iOS lock screen.
TextStyle clockStyle({required double weight, required double width, required double slant, double round = 0}) {
  // Narrow digits sit closer together; wide ones need less squeezing.
  final spacing = -6 + (width - 25) / 126 * 4;
  return DS.clock.copyWith(
    fontFamily: DS.clockFont,
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)], // no faux bold
    letterSpacing: spacing,
    fontVariations: [FontVariation('wght', weight), FontVariation('wdth', width), FontVariation('slnt', slant), FontVariation('ROND', round)],
  );
}

TextStyle clockStyleOf(Prefs p) => clockStyle(weight: p.clockWeight, width: p.clockWidth, slant: p.clockSlant, round: p.clockRound);

/// Quick starting points (the sliders fine-tune from there).
/// (name, weight, width, slant, roundness)
const clockPresets = <(String, double, double, double, double)>[
  ('Classic', 300, 25, 0, 0), // tall & light — the original look
  ('Soft', 500, 60, 0, 100), // friendly, fully rounded
  ('Bold', 800, 50, 0, 0),
  ('Bubble', 900, 110, 0, 100),
  ('Wide', 250, 151, 0, 0),
  ('Italic', 500, 70, -10, 0),
  ('Hairline', 100, 40, 0, 0),
];

/// Does the current style match preset [p]?
bool isClockPreset((String, double, double, double, double) p, Prefs prefs) =>
    (prefs.clockWeight - p.$2).abs() < 1 && (prefs.clockWidth - p.$3).abs() < 1 && (prefs.clockSlant - p.$4).abs() < .1 && (prefs.clockRound - p.$5).abs() < 1;

/// Hands the clock style down to every page of the carousel.
class HeaderFontScope extends InheritedWidget {
  const HeaderFontScope({super.key, required this.style, required super.child});
  final TextStyle style;

  static TextStyle of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HeaderFontScope>()?.style ?? DS.clock;

  @override
  bool updateShouldNotify(HeaderFontScope old) => old.style != style;
}
