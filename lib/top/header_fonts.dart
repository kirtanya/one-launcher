import 'package:flutter/widgets.dart';

import '../ui/ds.dart';

/// Typefaces for the big figures in the top half (clock, screen time, battery %, event time).
/// Each keeps the DS.clock colour/shadow; only the face and its spacing change.
class HeaderFont {
  const HeaderFont(this.id, this.name, this.family, this.weight, {this.letterSpacing = -2});
  final String id, name, family;
  final FontWeight weight;
  final double letterSpacing;

  TextStyle get style => DS.clock.copyWith(fontFamily: family, fontWeight: weight, letterSpacing: letterSpacing);
}

const headerFonts = <HeaderFont>[
  HeaderFont('condensed', 'Condensed', 'Antonio', FontWeight.w300, letterSpacing: -4),
  HeaderFont('bold', 'Bold', 'BebasNeue', FontWeight.w400, letterSpacing: 0),
  HeaderFont('serif', 'Serif', 'InstrumentSerif', FontWeight.w400, letterSpacing: -3),
  HeaderFont('rounded', 'Rounded', 'Nunito', FontWeight.w200, letterSpacing: -4),
  HeaderFont('mono', 'Mono', 'SpaceMono', FontWeight.w400, letterSpacing: -8),
  HeaderFont('thin', 'Thin', 'Outfit', FontWeight.w200, letterSpacing: -4),
];

HeaderFont headerFontById(String id) => headerFonts.firstWhere((f) => f.id == id, orElse: () => headerFonts.first);

/// Hands the chosen big-figure style down to every page of the carousel.
class HeaderFontScope extends InheritedWidget {
  const HeaderFontScope({super.key, required this.style, required super.child});
  final TextStyle style;

  static TextStyle of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HeaderFontScope>()?.style ?? DS.clock;

  @override
  bool updateShouldNotify(HeaderFontScope old) => old.style != style;
}
