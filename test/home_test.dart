import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  await (FontLoader('Antonio')..addFont(Future.value(ByteData.view(File('assets/fonts/Antonio-300.ttf').readAsBytesSync().buffer)))).load();
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
  'WhatsApp': 'com.whatsapp', 'Instagram': 'com.instagram.android', 'Messages': 'com.google.android.apps.messaging',
  'Slack': 'com.Slack', 'Gmail': 'com.google.android.gm', 'Figma': 'com.figma.mirror', 'Calendar': 'com.google.android.calendar',
  'Paytm': 'net.one97.paytm', 'PhonePe': 'com.phonepe.app', 'Splitwise': 'com.splitwise.SplitwiseMobile',
  'Spotify': 'com.spotify.music', 'YouTube': 'com.google.android.youtube', 'Photos': 'com.google.android.apps.photos',
  'Swiggy': 'in.swiggy.android', 'Zomato': 'com.application.zomato', 'Maps': 'com.google.android.apps.maps', 'Uber': 'com.ubercab',
  'Clock': 'com.google.android.deskclock', 'Settings': 'com.android.settings', 'Mystery': 'org.example.mystery',
};

void main() {
  testWidgets('one screen: clock on top, app sheet below, swipe up hides clock', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88; // 375pt wide
    final now = DateTime.now().millisecondsSinceEpoch;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final e in _apps.entries)
            {
              'package': e.value,
              'label': e.key,
              'system': e.key == 'Settings' || e.key == 'Clock',
              'category': -1,
              'installed': e.key == 'Figma' || e.key == 'Uber' ? now : 0,
            },
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'favourites': ['com.whatsapp', 'com.Slack'],
      'launchCounts': '{"com.figma.mirror":4}',
    });
    final prefs = await Prefs.load();

    await tester.pumpWidget(ColoredBox(color: const Color(0xFF6B5A4A), child: OneLauncher(prefs: prefs)));
    await tester.pumpAndSettle();
    final clock = find.byType(FittedBox).first;
    expect(clock.hitTestable(), findsOneWidget);
    expect(find.text('Most used'), findsNothing, reason: 'green card has no header now');
    expect(find.text('Figma'), findsOneWidget, reason: 'most-used app shows in it');
    // Pinned first: WhatsApp & Slack (pinned) come before Figma (most used), with pin badges.
    expect(tester.getTopLeft(find.text('WhatsApp').first).dx, lessThan(tester.getTopLeft(find.text('Figma')).dx));
    expect(find.byIcon(Icons.push_pin), findsNWidgets(2));
    expect(find.byTooltip('Customise pinned & most used'), findsOneWidget);
    expect(find.text('Search 20 apps'), findsOneWidget, reason: 'dock starts as a full bar');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/1_rest.png'));

    // Swipe the sheet up to full screen.
    await tester.fling(find.text('Figma'), const Offset(0, -300), 1500);
    await tester.pumpAndSettle();
    expect(clock.hitTestable(), findsNothing, reason: 'clock hidden when sheet is full');

    // Scroll the list up → dock shrinks to a circle.
    await tester.drag(find.text('Social'), const Offset(0, -200));
    await tester.pumpAndSettle();
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/2_scrolled_compact_dock.png'));
    // Scroll back down → full bar again.
    await tester.drag(find.text('Social'), const Offset(0, 400));
    await tester.pumpAndSettle();

    // Accordion: open Work, then Money; Work closes.
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('Gmail'), findsOneWidget);
    await tester.tap(find.text('Money'));
    await tester.pumpAndSettle();
    expect(find.text('PhonePe'), findsOneWidget);
    expect(find.text('Gmail'), findsNothing, reason: 'only one folder open at a time');
    // The opened folder glides to the middle of the screen.
    final screenMid = tester.view.physicalSize.height / tester.view.devicePixelRatio / 2;
    final moneyCardMid = (tester.getTopLeft(find.text('Money')).dy + tester.getBottomLeft(find.text('Splitwise')).dy) / 2;
    expect((moneyCardMid - screenMid).abs(), lessThan(80), reason: 'open folder is centred (mid=$moneyCardMid, screen=$screenMid)');
    expect(find.byTooltip('Customise folder'), findsOneWidget, reason: 'only the open folder shows •••');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/3_one_folder_open.png'));

    await tester.tap(find.byTooltip('Customise folder'));
    await tester.pumpAndSettle();
    expect(find.text('Choose apps'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/4_customise.png'));
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Payments');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Payments'), findsOneWidget);

    // Search from the bottom dock.
    await tester.tap(find.byIcon(Icons.search_rounded).last); // dock is the round button here
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sp');
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget, reason: 'results show the renamed folder');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/5_search.png'));

    // Pull the results down → search closes, keyboard goes, back to the clock.
    await tester.drag(find.text('Splitwise'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'search closed');
    expect(find.byType(FittedBox).first.hitTestable(), findsOneWidget, reason: 'back home with the clock');
  });
}
