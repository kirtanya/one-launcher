import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tiles/day_line.dart';
import 'package:one_launcher/tiles/today_panel.dart';
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

const _apps = {
  'WhatsApp': 'com.whatsapp',
  'Instagram': 'com.instagram.android',
  'Slack': 'com.Slack',
  'Gmail': 'com.google.android.gm',
  'Figma': 'com.figma.mirror',
  'Calendar': 'com.google.android.calendar',
  'Spotify': 'com.spotify.music',
  'YouTube': 'com.google.android.youtube',
  'Photos': 'com.google.android.apps.photos',
  'Maps': 'com.google.android.apps.maps',
  'Clock': 'com.google.android.deskclock',
  'Settings': 'com.android.settings',
};

Future<Prefs> _setUp(WidgetTester tester, Map<String, Object> initial) async {
  await _loadFonts();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.88; // 375pt wide
  addTearDown(tester.view.reset);
  final now = DateTime.now();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
    switch (call.method) {
      case 'getApps':
        return [
          for (final e in _apps.entries)
            {'package': e.value, 'label': e.key, 'system': e.key == 'Settings' || e.key == 'Clock', 'category': -1, 'installed': 0},
        ];
      case 'getScreenTime':
        return {
          'granted': true,
          'total': 13920000,
          'top': [
            {'package': 'com.whatsapp', 'label': 'WhatsApp', 'ms': 4200000},
            {'package': 'com.google.android.youtube', 'label': 'YouTube', 'ms': 3100000},
          ],
        };
      case 'getBattery':
        return {'level': 64, 'charging': true, 'full': false, 'chargeMsLeft': 2700000};
      case 'getEvents':
        final b = now.add(const Duration(minutes: 40)).millisecondsSinceEpoch;
        return {
          'granted': true,
          'events': [
            {'id': 1, 'title': 'Design review', 'begin': b, 'end': b + 1800000, 'allDay': false},
          ],
        };
      case 'nextAlarm':
        return {'at': DateTime(now.year, now.month, now.day + 1, 7).millisecondsSinceEpoch, 'package': 'com.google.android.deskclock'};
      case 'notifCounts':
        return {'com.whatsapp': 3, 'com.Slack': 2};
    }
    return null;
  });
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await Prefs.load();
  await tester.pumpWidget(
    ColoredBox(
      color: const Color(0xFF6B5A4A),
      child: OneLauncher(prefs: prefs),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

Finder get _panel => find.byType(TodayPanel).hitTestable();
Finder get _clock => find.byType(FittedBox).first.hitTestable();

void main() {
  tearDown(() {
    Apps.instance.media.value = null;
    Apps.instance.notifCounts.value = const {};
  });

  testWidgets('Classic: today panel left of home — swipe in, Classic cards, reorder, list, Back / Home return; carousel + sheet still work', (tester) async {
    final prefs = await _setUp(tester, {
      'favourites': ['com.whatsapp', 'com.Slack'],
    });
    expect(prefs.classicToday, isTrue, reason: 'on by default');
    expect(_panel, findsNothing, reason: 'home first');
    expect(_clock, findsOneWidget);

    // The top carousel still swipes between its own pages (left → Screen time, right → back).
    await tester.fling(find.byType(FittedBox).first, const Offset(-250, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Screen time today'), findsOneWidget, reason: 'carousel page 2');
    expect(_panel, findsNothing);
    await tester.fling(find.text('Screen time today'), const Offset(250, 0), 1200);
    await tester.pumpAndSettle();
    expect(_clock, findsOneWidget, reason: 'carousel back on the clock — not the panel yet');
    expect(_panel, findsNothing);

    // At the carousel's first page a swipe right carries on into the panel.
    await tester.fling(find.byType(FittedBox).first, const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget, reason: 'carousel hands over to the panel');
    expect(find.text('Today'), findsWidgets, reason: 'the panel title (and Screen time\'s caption)');
    // The same widgets as Tiles, in Classic words (Sentence case).
    expect(find.byType(DayLine), findsOneWidget, reason: 'Your day');
    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.textContaining('Design review · in'), findsWidgets, reason: 'glance with the next event');

    // Back → home.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(_clock, findsOneWidget, reason: 'Back returns home');

    // A swipe right anywhere outside the carousel (here on the app drawer) opens it too.
    await tester.fling(find.text('Slack').first, const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget, reason: 'swipe right on home → panel');
    Apps.instance.media.value = {'granted': true, 'active': true, 'app': 'Spotify', 'title': 'Midnight City', 'artist': 'M83', 'playing': true};
    await tester.pumpAndSettle();
    // Classic look: rounded cards (the card radius), the first one the hero.
    final cards = find.descendant(of: find.byType(TodayPanel), matching: find.byWidgetPredicate((w) => w is Material && w.shape is RoundedRectangleBorder));
    final radius = (tester.widget<Material>(cards.first).shape! as RoundedRectangleBorder).borderRadius as BorderRadius;
    expect(radius.topLeft.x, 28, reason: 'Classic card corners');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/46_classic_today.png'));

    // Hold and drag the first widget onto the second: they swap; edit mode comes on.
    final first = todayTiles(prefs).first.id, second = todayTiles(prefs)[1].id;
    final g = await tester.startGesture(tester.getCenter(find.byType(DayLine)));
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 22));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(todayTiles(prefs).take(2).map((t) => t.id), [second, first], reason: 'swapped by dragging');
    expect(find.byTooltip('Widget options'), findsWidgets, reason: 'edit mode with ⋯ menus');

    // Back while editing ends editing first — still on the panel.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Widget options'), findsNothing);
    expect(_panel, findsOneWidget, reason: 'Back while editing stays on the panel');

    // Edit → List layout (Classic pills), then Done.
    await tester.tap(find.byTooltip('Edit today'));
    await tester.pumpAndSettle();
    expect(find.text('Add widget'), findsOneWidget, reason: 'Classic edit bar');
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(prefs.todayLayout, 'list');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('YOUR DAY'), findsOneWidget, reason: 'Classic list: small-caps card headers');
    expect(find.text('WhatsApp'), findsWidgets, reason: 'notification rows with app icons');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/47_classic_today_list.png'));
    await prefs.setTodayLook(layout: 'tiles');
    await tester.pumpAndSettle();

    // Home button → home, from the panel.
    Apps.instance.onHomePressed?.call();
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(_clock, findsOneWidget, reason: 'Home returns home');

    // The app sheet still scrolls up and down (vertical drags stay the sheet's).
    final restY = tester.getTopLeft(find.text('Slack').first).dy;
    await tester.fling(find.text('Slack').first, const Offset(0, -300), 1500);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Slack').first).dy, lessThan(restY - 150), reason: 'sheet up to full screen');
    expect(_clock, findsNothing, reason: 'clock hidden when the sheet is full');
    expect(_panel, findsNothing);
    await tester.binding.handlePopRoute(); // Back: the sheet comes down
    await tester.pumpAndSettle();
    expect(_clock, findsOneWidget);
  });

  testWidgets('Today panel: Card height → Hug content — rows only as tall as their widgets, edges still line up', (tester) async {
    double bottom() {
      final cards = find.descendant(of: find.byType(TodayPanel), matching: find.byWidgetPredicate((w) => w is Material && w.shape is RoundedRectangleBorder));
      return [for (final e in cards.evaluate()) tester.getRect(find.byWidget(e.widget)).bottom].reduce((a, b) => a > b ? a : b);
    }

    final prefs = await _setUp(tester, {
      'favourites': ['com.whatsapp', 'com.Slack'],
    });
    await tester.fling(find.text('Slack').first, const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    final grid = bottom();

    await prefs.setTodayLook(hug: true);
    Apps.instance.media.value = {'granted': true, 'active': true, 'app': 'Spotify', 'title': 'Midnight City', 'artist': 'M83', 'playing': true};
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'every widget lays out at its content height');
    expect(find.byType(DayLine), findsOneWidget);
    expect(find.text('Midnight City'), findsOneWidget);
    expect(bottom(), lessThan(grid), reason: 'hugging takes less room than the square grid');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/48_classic_today_hug.png'));

    // Edit mode (⋯ menus, the smaller scale) still lays out while hugging.
    await tester.tap(find.byTooltip('Edit today'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Widget options'), findsWidgets);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await prefs.setTodayLook(hug: false);
    await tester.pumpAndSettle();
    expect(bottom(), closeTo(grid, 1), reason: 'Fixed grid again');
  });

  testWidgets('Classic: Settings → Today panel — off stops the swipe, on again, open from Settings', (tester) async {
    final prefs = await _setUp(tester, {});
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Today panel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today panel'));
    await tester.pumpAndSettle();
    expect(find.text('Side panel'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget, reason: 'Classic names the tiles layout "Cards"');
    await tester.tap(find.text('Side panel'));
    await tester.pumpAndSettle();
    expect(prefs.classicToday, isFalse);
    expect(find.text('Open the panel'), findsNothing, reason: 'nothing to set while it is off');
    Navigator.of(tester.element(find.text('Side panel')), rootNavigator: true).pop();
    await tester.pumpAndSettle();

    await tester.flingFrom(const Offset(180, 600), const Offset(300, 0), 1200); // on the app drawer
    await tester.pumpAndSettle();
    expect(_panel, findsNothing, reason: 'switched off: no panel');
    await tester.fling(find.byType(FittedBox).first, const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing, reason: 'nor from the carousel');

    // On again, and open it straight from Settings.
    await prefs.setClassicToday(true);
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Today panel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today panel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the panel'));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget, reason: 'Settings → Open the panel');
  });
}
