import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/ui/ds.dart';
import 'package:one_launcher/ui/palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _fonts() async {
  for (final (fam, file) in [('InstrumentSans', 'InstrumentSans-500'), ('Antonio', 'Antonio-300')]) {
    await (FontLoader(fam)..addFont(Future.value(ByteData.view(File('assets/fonts/$file.ttf').readAsBytesSync().buffer)))).load();
  }
  final icons = File('/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
}

void main() {
  testWidgets('Colours & style: basic purple recolours everything live', (tester) async {
    await _fonts();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Slack', 'Gmail', 'Paytm', 'Spotify', 'Maps'])
            {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'favourites': ['com.whatsapp', 'com.slack'],
    });
    await tester.pumpWidget(OneLauncher(prefs: await Prefs.load()));
    await tester.pumpAndSettle();
    // No Material You in tests → falls back to One's original look.
    expect(DS.palette.hero, OnePalette.original.hero);

    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colours & style'));
    await tester.pumpAndSettle();
    expect(find.text('Wallpaper colours need Android 12 or newer.'), findsOneWidget);
    await tester.tap(find.text('Basic colours'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Colour').at(7)); // purple
    await tester.pumpAndSettle();
    expect(DS.palette.hero, isNot(OnePalette.original.hero), reason: 'palette switched');
    await tester.tap(find.text('Vibrant'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/9_theme_sheet.png'));

    // Cards: Dark → dark cards with light text; then Auto (phone is in light mode in tests).
    await tester.ensureVisible(find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(DS.palette.card.computeLuminance(), lessThan(.1), reason: 'dark cards');
    expect(DS.palette.ink.computeLuminance(), greaterThan(.6), reason: 'light text on them');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/11_dark_cards_sheet.png'));
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(DS.palette.card.computeLuminance(), greaterThan(.8), reason: 'auto + light phone = light cards');
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('Colours & style'))).pop();
    await tester.pumpAndSettle();
    // Const widgets got rebuilt too: the dividers use the new hairline colour.
    final dividerColors = tester
        .widgetList<Container>(find.descendant(of: find.byType(Scaffold), matching: find.byType(Container)))
        .map((c) => c.color)
        .toSet();
    expect(dividerColors.contains(OnePalette.original.hairline), isFalse, reason: 'no stale original colours');
    expect(dividerColors.contains(OnePalette.original.card), isFalse, reason: 'no stale white cards');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/10_theme_purple_dark.png'));
  });
}
