import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/app_drawer.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone search → "Opened from search": the apps last opened from search, shown when search opens.
void main() {
  Future<Prefs> launch(WidgetTester tester, Map<String, Object> values, {String position = 'bottom'}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['Spotify', 'Slack', 'Maps']) {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({'searchPosition': position, ...values});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    return prefs;
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
  }

  test('newest first, no repeats, up to 8; cleared and switched off with search history', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    for (var i = 0; i < 10; i++) {
      await prefs.addSearchApp('p$i');
    }
    await prefs.addSearchApp('p5');
    expect(prefs.searchApps, ['p5', 'p9', 'p8', 'p7', 'p6', 'p4', 'p3', 'p2']);
    await prefs.clearSearchHistory();
    expect(prefs.searchApps, isEmpty);
    await prefs.addSearchApp('p1');
    await prefs.setSaveSearchHistory(false);
    expect(prefs.searchApps, isEmpty);
    await prefs.addSearchApp('p2');
    expect(prefs.searchApps, isEmpty, reason: 'history off: nothing kept');
  });

  testWidgets('none yet: no card', (tester) async {
    await launch(tester, {});
    await openSearch(tester);
    expect(find.byType(SearchAppsCard), findsNothing);
  });

  testWidgets('opening an app from search puts it in the card next time', (tester) async {
    final prefs = await launch(tester, {});
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'slack');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slack').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(prefs.searchApps, ['com.slack']);
    await openSearch(tester);
    final card = find.byType(SearchAppsCard);
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Slack')), findsOneWidget);
  });

  testWidgets('saved apps show newest first (gone ones skipped); long-press takes one off', (tester) async {
    final prefs = await launch(tester, {'searchApps': ['com.maps', 'com.gone', 'com.spotify']});
    await openSearch(tester);
    final card = find.byType(SearchAppsCard);
    expect(card, findsOneWidget);
    final maps = find.byKey(const ValueKey('search-app:com.maps'));
    final spotify = find.byKey(const ValueKey('search-app:com.spotify'));
    expect(tester.getTopLeft(maps).dx, lessThan(tester.getTopLeft(spotify).dx));
    expect(find.byKey(const ValueKey('search-app:com.gone')), findsNothing);
    await tester.longPress(maps);
    await tester.pumpAndSettle();
    expect(prefs.searchApps, ['com.gone', 'com.spotify']);
    expect(maps, findsNothing);
  });
}
