import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tv_remote.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('remote: volume slider follows the TV and presses keys to a level; TV text field → phone keyboard', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    final calls = <MethodCall>[];
    Future<void> send(Map<String, Object?> m) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'one_launcher/apps',
        const StandardMethodCodec().encodeMethodCall(MethodCall('tvState', m)),
        (_) {},
      );
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
    expect(find.byType(Slider), findsNWidgets(2), reason: 'volume + brightness sliders');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/22_remote.png'));

    // Quick apps: the user's own. Default YouTube, Netflix, Prime Video, JioHotstar; Edit → remove
    // Netflix, add Nuvio (no web link: opens through One Launcher TV).
    expect(prefs.remoteApps, ['youtube', 'netflix', 'prime', 'hotstar'], reason: 'JioHotstar, not Disney+, by default');
    Future<void> chip(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
    }

    await chip(find.byTooltip('Edit quick apps'));
    await tester.tap(find.byTooltip('Edit quick apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Netflix'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('Add Nuvio'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byTooltip('Add Nuvio'));
    await tester.pumpAndSettle();
    expect(prefs.remoteApps, ['youtube', 'prime', 'hotstar', 'nuvio']);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    calls.clear();
    await chip(find.widgetWithText(ActionChip, 'Nuvio'));
    await tester.tap(find.widgetWithText(ActionChip, 'Nuvio'));
    await tester.pumpAndSettle();
    expect((calls.lastWhere((c) => c.method == 'tvAppLink').arguments as Map)['link'], 'onelauncher://launch?package=com.nuvio.app');
    await chip(find.widgetWithText(ActionChip, 'JioHotstar'));
    await tester.tap(find.widgetWithText(ActionChip, 'JioHotstar'));
    await tester.pumpAndSettle();
    expect((calls.lastWhere((c) => c.method == 'tvAppLink').arguments as Map)['link'], 'https://www.hotstar.com');

    // Drag the slider up → several volume-up presses (no absolute volume in the protocol).
    calls.clear();
    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final ups = calls.where((c) => c.method == 'tvKey' && (c.arguments as Map)['code'] == 24).length;
    expect(ups, greaterThan(3), reason: 'pressed volume up to reach the dragged level ($ups)');

    // Brightness: direct slider (Android brightness via One Launcher TV) + the TV's picture panel.
    calls.clear();
    await tester.drag(find.byType(Slider).last, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect((calls.lastWhere((c) => c.method == 'tvAppLink').arguments as Map)['link'], startsWith('onelauncher://brightness?level='));
    expect(prefs.tvBrightness, greaterThan(40), reason: 'remembered');
    await tester.tap(find.byTooltip('TV picture settings'));
    await tester.pumpAndSettle();
    expect((calls.lastWhere((c) => c.method == 'tvAppLink').arguments as Map)['link'], 'onelauncher://picture');

    // The TV focuses a text field → a typing bar with the phone keyboard; typing goes to the TV.
    await send({'state': 'ime', 'host': '192.168.1.23', 'text': 'stra', 'label': 'Search'});
    expect(find.byTooltip('Done typing'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'stranger things');
    await tester.pump();
    // Only the new letters go (the TV adds what it's sent to its field, it doesn't replace it).
    final sent = calls.lastWhere((c) => c.method == 'tvText');
    expect((sent.arguments as Map)['text'], 'nger things');
    // This TV gave no text field (tvText → not sent): the letters went as key presses instead.
    final keys = [for (final c in calls.where((c) => c.method == 'tvKey')) (c.arguments as Map)['code']];
    expect(keys, containsAllInOrder([TvRemote.keyFor('n'), TvRemote.keyFor('g'), TvRemote.keyFor(' '), TvRemote.keyFor('t')]), reason: 'typed as keys');
    // Deleting goes as Delete presses — one per removed letter, nothing re-sent.
    calls.clear();
    await tester.enterText(find.byType(TextField), 'stranger thi');
    await tester.pump();
    expect([for (final c in calls.where((c) => c.method == 'tvKey')) (c.arguments as Map)['code']], [TvKey.delete, TvKey.delete, TvKey.delete]);
    expect(calls.where((c) => c.method == 'tvText'), isEmpty, reason: 'nothing to add');
    // A changed letter mid-word: delete back to it, then add the rest.
    calls.clear();
    await tester.enterText(find.byType(TextField), 'stranger tha');
    await tester.pump();
    expect([for (final c in calls.where((c) => c.method == 'tvKey')) (c.arguments as Map)['code']].first, TvKey.delete);
    expect((calls.firstWhere((c) => c.method == 'tvText').arguments as Map)['text'], 'a');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'tvKey' && (c.arguments as Map)['code'] == 66), isNotEmpty, reason: 'Enter submits on the TV');
    expect(find.byTooltip('Done typing'), findsNothing);
  });

  testWidgets('remote in the Tiles view speaks Metro: square pad, accent OK, square buttons', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') return [{'package': 'com.slack', 'label': 'Slack', 'system': false, 'category': -1, 'installed': 0}];
      if (call.method == 'tvConnect') return true;
      return null;
    });
    SharedPreferences.setMockInitialValues({'tvHost': '192.168.1.23', 'tvName': 'Kame TV', 'homeView': 'tiles'});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('All apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('TV remote'));
    await tester.pumpAndSettle();
    expect(find.text('Kame TV'), findsOneWidget, reason: 'the TV keeps its own name');
    expect(find.text('ok'), findsOneWidget, reason: 'Metro OK');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/40_remote_tiles.png'));
  });
}
