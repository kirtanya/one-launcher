import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/app_drawer.dart' show NewDot;
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Recently installed: a folder of the last week’s installs, a dot until opened once, period + hide', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    int daysAgo(int d) => now.subtract(Duration(days: d)).millisecondsSinceEpoch;
    final launches = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          {'package': 'com.whatsapp', 'label': 'WhatsApp', 'system': false, 'category': -1, 'installed': 0},
          {'package': 'com.slack', 'label': 'Slack', 'system': false, 'category': -1, 'installed': daysAgo(200)},
          {'package': 'com.zepto', 'label': 'Zepto', 'system': false, 'category': -1, 'installed': daysAgo(2)},
          {'package': 'com.strava', 'label': 'Strava', 'system': false, 'category': -1, 'installed': daysAgo(5)},
          {'package': 'com.ixigo', 'label': 'ixigo', 'system': false, 'category': -1, 'installed': daysAgo(10)},
        ];
      }
      if (call.method == 'launch') launches.add((call.arguments as Map)['package'] as String);
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();

    expect(prefs.recentInstalls, isTrue, reason: 'on by default');
    expect(prefs.recentDays, 7, reason: '1 week by default');
    expect(find.text('Recently installed'), findsOneWidget, reason: 'a folder in the list');

    await tester.tap(find.text('Recently installed'));
    await tester.pumpAndSettle();
    final folder = find.ancestor(of: find.text('Recently installed'), matching: find.byType(SliverMainAxisGroup)).first;
    Finder inFolder(String label) => find.descendant(of: folder, matching: find.text(label));
    expect(inFolder('Zepto'), findsOneWidget);
    expect(inFolder('Strava'), findsOneWidget);
    expect(inFolder('ixigo'), findsNothing, reason: 'installed 10 days ago: outside 1 week');
    expect(inFolder('Slack'), findsNothing);
    expect(tester.getTopLeft(inFolder('Zepto')).dx, lessThan(tester.getTopLeft(inFolder('Strava')).dx), reason: 'newest first');
    expect(find.descendant(of: folder, matching: find.byType(NewDot)), findsNWidgets(2), reason: 'a dot on each new app');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/49_recently_installed.png'));

    // Opening Zepto from the launcher clears its dot — it stays in the folder.
    await tester.tap(inFolder('Zepto'));
    await tester.pumpAndSettle();
    expect(launches, contains('com.zepto'));
    // Launching folds the list away; back on it, open the folder again.
    if (inFolder('Strava').evaluate().isEmpty) {
      await tester.tap(find.text('Recently installed'));
      await tester.pumpAndSettle();
    }
    expect(find.descendant(of: folder, matching: find.byType(NewDot)), findsOneWidget, reason: 'only Strava still new');
    expect(inFolder('Zepto'), findsOneWidget, reason: 'kept for the whole period');

    // A longer period takes in ixigo (with its dot); hidden, the folder goes (dots stay).
    await prefs.setRecentInstalls(days: 14);
    await tester.pumpAndSettle();
    expect(inFolder('ixigo'), findsOneWidget);
    expect(find.descendant(of: folder, matching: find.byType(NewDot)), findsNWidgets(2));
    await prefs.setRecentInstalls(on: false);
    await tester.pumpAndSettle();
    expect(find.text('Recently installed'), findsNothing, reason: 'folder hidden');
  });
}
