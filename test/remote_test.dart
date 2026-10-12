import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('remote: volume slider follows the TV and presses keys to a level; TV text field → phone keyboard', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    final calls = <MethodCall>[];
    Future<void> send(Map<String, Object?> m) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage('one_launcher/apps', const StandardMethodCodec().encodeMethodCall(MethodCall('tvState', m)), (_) {});
      await tester.pumpAndSettle();
    }
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getApps':
          return [
            {'package': 'com.slack', 'label': 'Slack', 'system': false, 'category': -1, 'installed': 0},
          ];
        case 'tvConnect':
          return true;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({'tvHost': '192.168.1.23', 'tvName': 'Kame TV'});
    final prefs = await Prefs.load();
    Apps.instance.init(); // listens for the TV's messages (main() does this in the app)
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('TV remote'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'tvConnect'), isNotEmpty, reason: 'connects to the paired TV');
    await send({'state': 'connected', 'host': '192.168.1.23'});
    await send({'state': 'volume', 'host': '192.168.1.23', 'level': 10, 'max': 100, 'muted': false});
    expect(find.text('Kame TV'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('10'), findsOneWidget, reason: 'TV volume shown');
    expect(find.byType(Slider), findsOneWidget, reason: 'volume slider');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/22_remote.png'));

    // Drag the slider up → several volume-up presses (no absolute volume in the protocol).
    calls.clear();
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final ups = calls.where((c) => c.method == 'tvKey' && (c.arguments as Map)['code'] == 24).length;
    expect(ups, greaterThan(3), reason: 'pressed volume up to reach the dragged level ($ups)');

    // The TV focuses a text field → a typing bar with the phone keyboard; typing goes to the TV.
    await send({'state': 'ime', 'host': '192.168.1.23', 'text': 'stra', 'label': 'Search'});
    expect(find.byTooltip('Done typing'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'stranger things');
    await tester.pump();
    final sent = calls.lastWhere((c) => c.method == 'tvText');
    expect((sent.arguments as Map)['text'], 'stranger things');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'tvKey' && (c.arguments as Map)['code'] == 66), isNotEmpty, reason: 'Enter submits on the TV');
    expect(find.byTooltip('Done typing'), findsNothing);
  });
}
