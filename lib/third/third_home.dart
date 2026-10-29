import 'package:flutter/material.dart';

import '../home.dart';
import '../prefs.dart';
import '../ui/theme.dart';

/// The third home view (Settings → Home screen → Home view → New view) and the root of its own
/// design language (`DesignLanguage.third`, docs/DESIGN_LANGUAGES.md). Everything this view
/// shows — and every sheet, menu and page it opens — speaks that language.
///
/// Being designed: until its own layout is built, it hosts the Classic home in the third
/// language (which itself starts from Classic's tokens), so the view is usable from day one.
/// Its own surfaces go in lib/third/.
class ThirdHome extends StatelessWidget {
  const ThirdHome({super.key, required this.prefs, required this.theme});
  final Prefs prefs;
  final OneTheme theme;

  @override
  Widget build(BuildContext context) => HomeScreen(prefs: prefs, theme: theme);
}
