import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<List<String>> launch(WidgetTester tester, Map? state) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getApps':
          return [
            {'package': 'com.spotify.music', 'label': 'Spotify', 'system': false, 'category': -1, 'installed': 0},
          ];
        case 'mediaState':
          return state;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({'topOrder': ['now_playing', 'clock'], 'topEnabled': ['now_playing', 'clock'], 'blankAdded': true, 'nowPlayingAdded': true});
    Apps.instance.init(); // listen for Android's pushes (main() does this in the app)
    await tester.pumpWidget(OneLauncher(prefs: await Prefs.load()));
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('without notification access it asks for it', (tester) async {
    final calls = await launch(tester, {'granted': false});
    await tester.tap(find.text('Allow notification access'));
    await tester.pump();
    expect(calls, contains('openNotificationAccess'));
  });

  testWidgets('shows the track and controls the player; follows changes', (tester) async {
    final calls = await launch(tester, {
      'granted': true, 'active': true, 'app': 'Spotify', 'title': 'Midnight City', 'artist': 'M83', 'playing': true,
      'position': 60000, 'duration': 240000, 'speed': 1.0, 'canPrev': true, 'canNext': true,
    });
    expect(find.text('Now playing · Spotify'), findsOneWidget);
    expect(find.text('Midnight City'), findsOneWidget);
    expect(find.text('M83'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/12_now_playing.png'));

    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();
    expect(calls, contains('mediaPlayPause'));
    expect(find.bySemanticsLabel('Play'), findsOneWidget, reason: 'flips straight away');
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pump();
    expect(calls, contains('mediaNext'));

    // Android reports a new track.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'one_launcher/apps',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('mediaChanged', {
        'granted': true, 'active': true, 'app': 'Spotify', 'title': 'Wait', 'artist': 'M83', 'playing': true,
        'position': 0, 'duration': 300000, 'speed': 1.0, 'canPrev': true, 'canNext': true,
      })),
      (_) {},
    );
    await tester.pump();
    expect(find.text('Wait'), findsOneWidget, reason: 'live update');
  });
}
