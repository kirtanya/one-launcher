import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake phone: first-run flag, file picker answers, widgets that exist.
Future<Prefs> _launch(WidgetTester tester, Map<String, Object> saved, {required bool firstRun, List<String?> picks = const [], List<bool>? pickedInDownloads, List<int>? bound}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.88;
  final queue = [...picks];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
    switch (call.method) {
      case 'getApps':
        return [
          for (final n in ['WhatsApp', 'Slack'])
            {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      case 'installState':
        return {'firstRun': firstRun};
      case 'openBackup':
        pickedInDownloads?.add((call.arguments as Map)['downloads'] == true);
        return queue.isEmpty ? null : queue.removeAt(0);
      case 'boundWidgetIds':
        return bound;
    }
    return null;
  });
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await Prefs.load();
  await tester.pumpWidget(OneLauncher(prefs: prefs));
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  const backup = '{"app":"One Launcher","format":1,"created":"2026-10-01T10:00:00","settings":{'
      '"favourites":{"t":"l","v":["com.whatsapp"]},"folderNames":{"t":"s","v":"{\\"money\\":\\"Payments\\"}"}}}';

  testWidgets('fresh install: not in Downloads → look elsewhere → restored', (tester) async {
    final where = <bool>[];
    final prefs = await _launch(tester, {}, firstRun: true, picks: [null, backup], pickedInDownloads: where);
    expect(find.text('Welcome to One Launcher'), findsOneWidget);
    await tester.tap(find.text('Find my backup'));
    await tester.pumpAndSettle();
    expect(find.text('Saved somewhere else?'), findsOneWidget, reason: 'nothing picked in Downloads');
    await tester.tap(find.text('Look in another folder'));
    await tester.pumpAndSettle();
    expect(where, [true, false], reason: 'first opened in Downloads, then anywhere');
    expect(find.text('All set'), findsOneWidget);
    expect(prefs.favourites, ['com.whatsapp']);
    expect(prefs.folderNames['money'], 'Payments');
    expect(prefs.installId, isNotNull);
  });

  testWidgets('Android restored settings from the Google backup → welcome back', (tester) async {
    await _launch(tester, {'installId': 'old', 'favourites': ['com.slack']}, firstRun: true);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Use a backup file instead'), findsOneWidget);
  });

  testWidgets('update from an older version → no prompt', (tester) async {
    final prefs = await _launch(tester, {'favourites': ['com.slack']}, firstRun: true);
    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Welcome to One Launcher'), findsNothing);
    expect(prefs.installId, isNotNull);
  });

  testWidgets('widget pages that do not exist on this phone are dropped', (tester) async {
    final prefs = await _launch(
      tester,
      {
        'widgetLabels': '{"widget:7":"Calendar","widget:9":"Weather"}',
        'topOrder': ['clock', 'widget:7', 'widget:9', 'blank'],
        'topEnabled': ['clock', 'widget:7', 'widget:9'],
        'installId': 'x',
        'blankAdded': true,
        'nowPlayingAdded': true,
      },
      firstRun: false,
      bound: [7],
    );
    expect(prefs.topPages, ['clock', 'widget:7']);
    expect(prefs.widgetLabels.keys, ['widget:7']);
  });
}
