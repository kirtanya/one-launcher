import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main_tv.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tv/tv_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  await (FontLoader('ClockFlex')..addFont(Future.value(ByteData.view(File('assets/fonts/ClockFlex.ttf').readAsBytesSync().buffer)))).load();
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
  testWidgets('TV Spotlight: one column on the right; ↑↓ in it, ←→ between columns, ↑ to the top bar, Back lands', (tester) async {
    await _loadFonts();
    TvApps.demo = true;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'homeView': 'spotlight'});
    final prefs = await Prefs.load();

    await tester.pumpWidget(OneLauncherTv(prefs: prefs));
    await tester.pumpAndSettle();
    expect(_focused(), startsWith('spotlight continue:0'), reason: 'lands on the first card of the first column');
    expect(find.text('Continue watching'), findsOneWidget);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_spotlight_1_home.png'));

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), startsWith('spotlight continue:1'));

    // → the next column (Your apps), from its first card.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('Your apps'), findsOneWidget);
    expect(_focused(), startsWith('spotlight fav:0'));
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_spotlight_2_apps.png'));

    // ← back: Continue watching remembers its card.
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused(), startsWith('spotlight continue:1'));

    // ↑↑ to the top bar.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), startsWith('spotlight top search'));

    // Back: the first card again.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_focused(), startsWith('spotlight continue:0'));
    // Customise open (top bar → customise), then something changes under it: focus stays in the panel.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(), startsWith('spotlight top customise'));
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Customise'), findsWidgets);
    // One page per thing, Spotlight's own names.
    for (final page in ['Background', 'Clock', 'Continue watching', 'Quick actions', 'Your apps']) {
      expect(find.text(page), findsWidgets, reason: page);
    }
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_spotlight_5_customise.png'));
    final inPanel = _focused();
    await prefs.setTvQuickActions([...prefs.tvQuickActions]);
    await tester.pumpAndSettle();
    expect(_focused(), inPanel, reason: 'the home screen rebuilt underneath; the panel keeps focus');
    expect(_focused(), isNot(startsWith('spotlight')));
  });

  testWidgets('TV Spotlight: small cards per column (Customise → Columns)', (tester) async {
    await _loadFonts();
    TvApps.demo = true;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'homeView': 'spotlight', 'tvSettings': '{"spotCardContinue":"small","spotCardFav":"small"}'});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncherTv(prefs: prefs));
    await tester.pumpAndSettle();
    expect(_focused(), startsWith('spotlight continue:0'));
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_spotlight_3_small.png'));
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(), startsWith('spotlight fav:0'));
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_spotlight_4_small_apps.png'));
  });

  testWidgets('TV Customise: Hold OK on an app → "Customise “Your apps”" → that page with its own rows', (tester) async {
    await _loadFonts();
    TvApps.demo = true;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'homeView': 'spotlight'});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncherTv(prefs: prefs));
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowRight); // Your apps
    expect(_focused(), startsWith('spotlight fav:0'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final customise = find.text('Customise “Your apps”');
    await tester.scrollUntilVisible(customise, 120, scrollable: find.byType(Scrollable).last);
    await tester.tap(customise);
    await tester.pumpAndSettle();
    for (final row in ['Your apps', 'Cards', 'All apps']) {
      expect(find.text(row), findsWidgets, reason: row);
    }
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_spotlight_6_your_apps_page.png'));
  });
}
