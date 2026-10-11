import 'package:flutter/widgets.dart';

import '../prefs.dart';
import '../ui/ds.dart';

/// The big figures (clock, screen time, battery %, event time) use one variable font,
/// Roboto Flex, whose weight / width / slant the user tunes — like the Pixel or iOS lock screen.
TextStyle clockStyle({required double weight, required double width, required double slant}) {
  // Narrow digits sit closer together; wide ones need less squeezing.
  final spacing = -6 + (width - 25) / 126 * 4;
  return DS.clock.copyWith(
    fontFamily: DS.clockFont,
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)], // no faux bold
    letterSpacing: spacing,
    fontVariations: [FontVariation('wght', weight), FontVariation('wdth', width), FontVariation('slnt', slant)],
  );
}

TextStyle clockStyleOf(Prefs p) => clockStyle(weight: p.clockWeight, width: p.clockWidth, slant: p.clockSlant);

/// Quick starting points (the sliders fine-tune from there).
const clockPresets = <(String, double, double, double)>[
  ('Classic', 300, 25, 0), // tall & light — the original look
  ('Bold', 800, 50, 0),
  ('Wide', 250, 151, 0),
  ('Italic', 500, 70, -10),
  ('Hairline', 100, 40, 0),
];

/// Hands the clock style down to every page of the carousel.
class HeaderFontScope extends InheritedWidget {
  const HeaderFontScope({super.key, required this.style, required super.child});
  final TextStyle style;

  static TextStyle of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HeaderFontScope>()?.style ?? DS.clock;

  @override
  bool updateShouldNotify(HeaderFontScope old) => old.style != style;
}
