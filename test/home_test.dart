import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
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
  testWidgets('home, app view with folders, open folder, search', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88; // 375pt wide
    final now = DateTime.now().millisecondsSinceEpoch;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final e in _apps.entries)
            {'package': e.value, 'label': e.key, 'system': e.key == 'Settings' || e.key == 'Clock', 'category': -1,
             'installed': e.key == 'Figma' || e.key == 'Uber' ? now : 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'favourites': ['com.whatsapp', 'com.Slack', 'com.figma.mirror', 'com.spotify.music'],
      'launchCounts': '{"com.whatsapp":9,"com.Slack":7,"com.figma.mirror":4}',
    });
    final prefs = await Prefs.load();

    await tester.pumpWidget(ColoredBox(color: const Color(0xFF3A4A6B), child: OneLauncher(prefs: prefs)));
    await tester.pump();
    expect(find.text('WhatsApp'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/home.png'));

    // Swipe left → app view.
    await tester.fling(find.text('WhatsApp'), const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Social'), findsOneWidget);
    expect(find.text('Money'), findsOneWidget);
    expect(find.text('#whatsapp'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/app_view.png'));

    await tester.tap(find.text('Money'));
    await tester.pumpAndSettle();
    expect(find.text('PhonePe'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/folder_open.png'));

    await tester.tap(find.byTooltip('Search apps'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sp');
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/search.png'));

    // Swipe right → back home.
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    await tester.fling(find.text('Social'), const Offset(300, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Social').hitTestable(), findsNothing);
  });
}
