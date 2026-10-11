import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main_tv.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tv/tv_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  await (FontLoader('RobotoFlex')..addFont(Future.value(ByteData.view(File('assets/fonts/RobotoFlex-Clock.ttf').readAsBytesSync().buffer)))).load();
  final loader = FontLoader('InstrumentSans');
  for (final w in [400, 500, 600]) {
    loader.addFont(Future.value(ByteData.view(File('assets/fonts/InstrumentSans-$w.ttf').readAsBytesSync().buffer)));
  }
  await loader.load();
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
  }
}

String? _focused() => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> _press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('TV: remote moves tile by tile, rows remember their spot, OK-hold opens options, search', (tester) async {
    await _loadFonts();
    TvApps.demo = true;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2; // 960×540, a 1080p TV
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();

    await tester.pumpWidget(OneLauncherTv(prefs: prefs));
    await tester.pumpAndSettle();
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Games'), findsOneWidget);
    // Starts on the first favourite (Watch & Listen apps until you pick your own).
    final first = _focused()!;
    expect(first, startsWith('fav:'));
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_1_home.png'));

    // → → moves along the row; ↓ goes to the next row, ↑ comes back to the same tile.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    final third = _focused()!;
    expect(third, isNot(first));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), isNot(startsWith('fav:')));
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_2_next_row.png'));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), third, reason: 'row remembers the last tile');

    // ↑ from the first row reaches the top buttons.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), startsWith('h:'));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), third);

    // Hold OK → options panel (and letting go doesn't pick the first option).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Remove from Favourites').evaluate().isNotEmpty || find.text('Add to Favourites').evaluate().isNotEmpty, isTrue);
    expect(find.text('App info'), findsOneWidget, reason: 'panel still open after release');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_3_options.png'));
    await tester.tapAt(const Offset(40, 270)); // outside the panel
    await tester.pumpAndSettle();
    expect(find.text('App info'), findsNothing);

    // Search: header → search button → type → ↓ into results.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    while (_focused() != 'h:search') {
      await _press(tester, LogicalKeyboardKey.arrowLeft);
    }
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'you');
    await tester.pumpAndSettle();
    expect(find.text('2 apps'), findsOneWidget); // YouTube, YouTube Music
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<EditableText>()));
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_4_search.png'));
  });
}
