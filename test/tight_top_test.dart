import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Worst case for the top area: phone status bar, smallest split, most padding, chips row.
/// Every page must fit (any overflow fails the test).
void main() {
  for (final media in [
    {'granted': false},
    {'granted': true, 'active': false},
    {'granted': true, 'active': true, 'app': 'Spotify', 'title': 'Midnight City', 'artist': 'M83', 'playing': true, 'position': 1, 'duration': 2000, 'speed': 1.0},
  ]) {
    testWidgets('all top pages fit a 20% top area (now playing: ${media['active'] ?? media['granted']})', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.88;
      tester.view.padding = const FakeViewPadding(top: 130, bottom: 70); // ~45pt status bar, gesture bar
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
        switch (call.method) {
          case 'getApps':
            return [{'package': 'com.whatsapp', 'label': 'WhatsApp', 'system': false, 'category': -1, 'installed': 0}];
          case 'mediaState':
            return media;
          case 'getScreenTime':
            return {'granted': true, 'total': 7200000, 'top': [{'package': 'com.whatsapp', 'label': 'WhatsApp', 'ms': 3600000}]};
          case 'getBattery':
            return {'level': 80, 'charging': true, 'full': false, 'chargeMsLeft': 600000};
          case 'getNextEvent':
            return {'granted': false};
        }
        return null;
      });
      SharedPreferences.setMockInitialValues({
        'topShare': 0.2,
        'topPadding': 40.0,
        'topOrder': ['clock', 'screen_time', 'battery', 'up_next', 'now_playing'],
        'topEnabled': ['clock', 'screen_time', 'battery', 'up_next', 'now_playing'],
        'blankAdded': true,
        'nowPlayingAdded': true,
      });
      Apps.instance.init();
      await tester.pumpWidget(OneLauncher(prefs: await Prefs.load()));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.fling(find.byType(PageView).first, const Offset(-300, 0), 1500);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
