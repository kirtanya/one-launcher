import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main_tv.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tv/tv_apps.dart';
import 'package:one_launcher/tv/tv_quick_settings.dart';
import 'package:one_launcher/tv/tv_settings.dart';
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

Future<Prefs> _start(WidgetTester tester) async {
  await _loadFonts();
  TvApps.demo = true;
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  // No clock: it shows the real time, so the goldens would change every minute.
  SharedPreferences.setMockInitialValues({'homeView': 'googletv', 'tvSettings': '{"clock":false,"date":false}'});
  final prefs = await Prefs.load();
  await tester.pumpWidget(OneLauncherTv(prefs: prefs));
  await tester.pumpAndSettle();
  return prefs;
}

/// The grid tile's focus: outline + glow only — its size never changes (user, 2026-11-06).
Size _cardSize(WidgetTester t, int i) => t.getSize(find.descendant(of: find.byKey(ValueKey('gtv:$i')), matching: find.byType(ClipRRect)).first);

void main() {
  testWidgets('TV Google TV: lands on the Home tab; ↓ hero grows, ↓ the apps grid scrolls row by row, Back lands', (tester) async {
    await _start(tester);
    expect(_focused(), 'gtv top home', reason: 'lands on the Home tab: hero + the first apps row at rest');
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Your apps'), findsOneWidget);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_google_1_home.png'));

    // → along the top bar: tabs, then Search and Settings.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(), 'gtv top apps');

    // ↓ to the hero (when there is one), ↓ again into the grid.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    if (_focused() == 'gtv hero') {
      await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_google_2_hero.png'));
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused(), 'gtv app 0');
    final size = _cardSize(tester, 0);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_google_3_grid.png'));

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(), 'gtv app 1');
    expect(_cardSize(tester, 0), size, reason: 'focus never scales a tile');
    expect(_cardSize(tester, 1), size);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'gtv app 6', reason: '↓ is the tile below (5 columns)');

    // Back: the Home tab again, everything at rest.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_focused(), 'gtv top home');
  });

  testWidgets('TV Google TV: Settings icon → the side Customise panel, as in every view', (tester) async {
    await _start(tester);
    // Home · Apps (· One Stream) · Search · Settings
    while (_focused() != 'gtv top settings') {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Customise'), findsOneWidget);
    expect(tvQuickSettingsOpen, isFalse, reason: 'the bottom Quick settings band is parked (user, 2026-11-06)');
  });

  testWidgets('TV Quick settings (parked, not in the launcher): band; OK grows a picker, Back closes picker then panel', (tester) async {
    await _start(tester);
    showTvQuickSettings(tester.element(find.byType(Scaffold).first), extras: [TvQuickItem('customise', Icons.tune_rounded, 'Customise home', () {})]);
    await tester.pumpAndSettle();
    expect(tvQuickSettingsOpen, isTrue);
    expect(find.text('Quick settings'), findsOneWidget);
    for (final name in ['Settings', 'Customise home', 'Volume', 'Mute', 'Sleep timer', 'Screensaver', 'Inputs', 'Network', 'Bluetooth']) {
      expect(find.descendant(of: find.byType(TvQuickSettings), matching: find.text(name)), findsWidgets, reason: name);
    }
    expect(find.text('Wi-Fi'), findsOneWidget, reason: 'values are what the TV says (demo: Wi-Fi)');
    expect(find.text('Brightness'), findsNothing, reason: 'not offered: TVs ignore it');
    expect(_focused(), 'qs settings');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_google_4_quick_settings.png'));

    // → to the sleep timer, OK: its picker grows up out of it.
    while (_focused() != 'qs sleep') {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('Then the screen turns off'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowDown); // 15 min, applied live
    await _press(tester, LogicalKeyboardKey.arrowDown); // 30 min
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_google_5_picker.png'));

    // Back: the picker closes (its value stays), Back again: the panel.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Then the screen turns off'), findsNothing);
    expect(find.text('Quick settings'), findsOneWidget);
    expect(find.textContaining('min'), findsWidgets, reason: 'the timer is set');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tvQuickSettingsOpen, isFalse);
    expect(find.text('Quick settings'), findsNothing);
  });

  testWidgets('TV Google TV: Customise has its own pages; Home view lists Google TV', (tester) async {
    expect(tvTilesHomeView.choices.map((c) => c.$1), contains('googletv'));
    final pages = [for (final (name, _, _) in tvSectionsFor('googletv')) name];
    expect(pages, containsAll(['Background', 'Clock', 'Continue watching', 'Remote & behaviour']));
    expect(pages, isNot(contains('Quick actions')), reason: 'no quick action chips in this view');
    final keys = [for (final (_, _, opts) in tvSectionsFor('googletv')) for (final o in opts) o.key];
    expect(keys, isNot(contains('landing')));
    expect(keys, isNot(contains('appCards')));
  });
}
