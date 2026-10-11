// Play Store screenshots: the real app, rendered with neutral app names (letter icons, no
// brands, no personal data) over a soft gradient wallpaper. Run:
//   flutter test --update-goldens test/store_shots_test.dart
// then `python3 tool/store_assets.py` frames them into store/screenshots/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
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

// Generic apps; the package names carry the folder keywords.
const _apps = {
  'Messages': 'com.one.messages', 'Phone': 'com.one.dialer', 'Contacts': 'com.one.contacts', 'Chat': 'com.one.chat.messaging', //
  'Mail': 'com.one.mail', 'Calendar': 'com.one.calendar', 'Tasks': 'com.one.todo', 'Docs': 'com.one.docs', 'Meet': 'com.one.meet', //
  'Bank': 'com.one.bank', 'Pay': 'com.one.pay', 'Stocks': 'com.one.invest', 'Wallet': 'com.one.wallet', //
  'Music': 'com.one.music', 'Photos': 'com.one.photos', 'Camera': 'com.one.camera', 'Video': 'com.one.video', 'Podcasts': 'com.one.podcast', //
  'Shop': 'com.one.shop', 'Groceries': 'com.one.grocery.shop', //
  'Maps': 'com.one.maps', 'Metro': 'com.one.metro', 'Trips': 'com.one.booking', //
  'News': 'com.one.news', 'Books': 'com.one.books', //
  'Chess': 'com.one.chess', 'Puzzles': 'com.one.puzzle', //
  'Health': 'com.one.health', 'Sleep': 'com.one.sleep', //
  'Clock': 'com.one.deskclock', 'Calculator': 'com.one.calculator', 'Weather': 'com.one.weather', 'Files': 'com.one.files', 'Settings': 'com.one.settings',
};

void main() {
  testWidgets('store screenshots', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1080, 2160); // Play: long side at most 2× the short
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      switch (call.method) {
        case 'getApps':
          return [
            for (final e in _apps.entries) {'package': e.value, 'label': e.key, 'system': e.key == 'Settings' || e.key == 'Clock', 'category': -1, 'installed': 0},
          ];
        case 'getScreenTime':
          return {
            'granted': true,
            'total': 9840000,
            'top': [
              {'package': 'com.one.messages', 'label': 'Messages', 'ms': 3300000},
              {'package': 'com.one.music', 'label': 'Music', 'ms': 2400000},
              {'package': 'com.one.maps', 'label': 'Maps', 'ms': 1200000},
            ],
          };
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'favourites': ['com.one.messages', 'com.one.camera', 'com.one.maps', 'com.one.music'],
      'launchCounts': '{"com.one.mail":9,"com.one.photos":7,"com.one.pay":6,"com.one.calendar":5}',
      'topShare': 0.35,
    });
    final prefs = await Prefs.load();
    await tester.pumpWidget(
      DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2E4A62), Color(0xFF5B4B7A), Color(0xFFC07A5A)],
            stops: [0, .55, 1],
          ),
        ),
        child: OneLauncher(prefs: prefs),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> shot(String name) => expectLater(find.byType(OneLauncher), matchesGoldenFile('../store/raw/$name.png'));

    await shot('1_home');

    // Screen time page (swipe the top).
    await tester.fling(find.byType(FittedBox).first, const Offset(-250, 0), 1200);
    await tester.pumpAndSettle();
    await shot('2_screen_time');
    await tester.fling(find.text('Screen time today'), const Offset(250, 0), 1200);
    await tester.pumpAndSettle();

    // Full screen + a folder open.
    await tester.timedDrag(find.text('Social'), const Offset(0, -600), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    tester.state<ScrollableState>(find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    await shot('3_folder');
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    // Search.
    await tester.tap(find.byIcon(Icons.search_rounded).last); // the dock (round button here)
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'p');
    await tester.pumpAndSettle();
    await shot('4_search');
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();

    // Colours: basic purple, vibrant.
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await shot('5_settings');
    await tester.tap(find.text('Colours & style'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basic colours'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Colour').at(7));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vibrant'));
    await tester.pumpAndSettle();
    await shot('6_colours');
  });
}
