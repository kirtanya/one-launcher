import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/search_dock.dart';
import 'package:one_launcher/search_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final calls = <MethodCall>[];
  Future<Prefs> launch(WidgetTester tester, {Map<String, Object> stored = const {}}) async {
    calls.clear();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      calls.add(call);
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Slack', 'Paytm', 'Spotify', 'Signal', 'Splitwise', 'Maps'])
            {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'favourites': ['com.paytm', 'com.slack'],
      ...stored,
    });
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    return prefs;
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.text('Search 7 apps'));
    await tester.pumpAndSettle();
  }

  String typed(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

  const history = ['weather today', 'spotify', 'maps'];

  test('saving rules: newest first, no duplicates (any case), at most 20, 2+ letters, only while on', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    expect(prefs.saveSearchHistory, isTrue, reason: 'on by default');
    await prefs.addSearch('a');
    await prefs.addSearch('   ');
    expect(prefs.searchHistory, isEmpty, reason: 'under 2 letters is not kept');
    await prefs.addSearch(' maps ');
    await prefs.addSearch('Slack');
    await prefs.addSearch('MAPS');
    expect(prefs.searchHistory, ['MAPS', 'Slack'], reason: 'a repeat (any case) moves to the top, trimmed, once');
    for (var i = 0; i < 25; i++) {
      await prefs.addSearch('query $i');
    }
    expect(prefs.searchHistory.length, Prefs.searchHistoryMax);
    expect(prefs.searchHistory.first, 'query 24');
    expect(prefs.searchHistory, isNot(contains('MAPS')), reason: 'oldest drop off');
    await prefs.removeSearch('query 24');
    expect(prefs.searchHistory.first, 'query 23');
    await prefs.addSearch('query 24', at: 3);
    expect(prefs.searchHistory[3], 'query 24', reason: 'Undo puts it back where it was');
    await prefs.setSaveSearchHistory(false);
    expect(prefs.searchHistory, isEmpty);
    await prefs.addSearch('nothing saved');
    await prefs.setSaveSearchHistory(true);
    expect(prefs.searchHistory, isEmpty, reason: 'turning it off cleared it, and nothing was saved meanwhile');
    expect(prefs.exportBackup(), isNot(contains('searchHistory')), reason: 'stays on this phone');
  });

  testWidgets('only searches that were used are saved: Enter, an app, a web row', (tester) async {
    final prefs = await launch(tester);
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'sp');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(prefs.searchHistory, isEmpty, reason: 'typed, then closed: not used');

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'weather');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(prefs.searchHistory, ['weather']);

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'spot');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spotify').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(prefs.searchHistory, ['spot', 'weather'], reason: 'an app opened from search');

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'news');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find apps on Play Store'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(prefs.searchHistory.first, 'news');
  });

  testWidgets('Classic, bar at the bottom: the card shows on an empty search, newest nearest the bar; tap searches it', (tester) async {
    final prefs = await launch(tester, stored: {'searchHistory': history});
    await openSearch(tester);
    expect(find.byType(RecentSearches), findsOneWidget);
    expect(find.text('Recent searches'), findsOneWidget);
    final bar = tester.getTopLeft(find.byType(SearchDock)).dy;
    expect(tester.getTopLeft(find.text('weather today')).dy, greaterThan(tester.getTopLeft(find.text('maps')).dy), reason: 'grows upward');
    expect(tester.getBottomLeft(find.text('weather today')).dy, lessThan(bar));
    expect(tester.getTopLeft(find.text('Recent searches')).dy, lessThan(tester.getTopLeft(find.text('maps')).dy), reason: 'title stays on top');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/58_recent_searches.png'));

    // The arrow only fills it in (history order unchanged).
    await tester.tap(find.byTooltip('Fill in “spotify”'));
    await tester.pumpAndSettle();
    expect(typed(tester), 'spotify');
    expect(prefs.searchHistory, history);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    // Tap: typed in, results show, moved to the top.
    await tester.tap(find.text('maps'));
    await tester.pumpAndSettle();
    expect(typed(tester), 'maps');
    expect(find.byType(RecentSearches), findsNothing);
    expect(find.text('Open'), findsOneWidget, reason: 'its results, as if typed');
    expect(prefs.searchHistory.first, 'maps');
  });

  testWidgets('Classic, bar at the top: newest first; empty history or saving off → no card', (tester) async {
    final prefs = await launch(tester, stored: {'searchHistory': history, 'searchPosition': 'top'});
    await openSearch(tester);
    expect(tester.getTopLeft(find.text('weather today')).dy, lessThan(tester.getTopLeft(find.text('maps')).dy));
    expect(tester.getTopLeft(find.text('Recent searches')).dy, greaterThan(tester.getTopLeft(find.byType(SearchDock)).dy));
    await prefs.clearSearchHistory();
    await tester.pumpAndSettle();
    expect(find.byType(RecentSearches), findsNothing);
    expect(find.text('Paytm'), findsWidgets, reason: 'the usual list');
  });

  testWidgets('swipe a row away → removed, with Undo', (tester) async {
    final prefs = await launch(tester, stored: {'searchHistory': history});
    await openSearch(tester);
    await tester.drag(find.text('spotify'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('spotify'), findsNothing);
    expect(prefs.searchHistory, ['weather today', 'maps']);
    expect(find.text('Removed'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.searchHistory, history, reason: 'back where it was');
    expect(find.text('spotify'), findsOneWidget);
    // The other way works too.
    await tester.drag(find.text('maps'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(prefs.searchHistory, ['weather today', 'spotify']);
  });

  testWidgets('long-press menu: remove one, or clear all (asks first); Clear all asks too', (tester) async {
    final prefs = await launch(tester, stored: {'searchHistory': history});
    await openSearch(tester);
    await tester.longPress(find.text('spotify'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from history'), findsOneWidget);
    expect(find.text('Clear all history'), findsOneWidget);
    await tester.tap(find.text('Remove from history'));
    await tester.pumpAndSettle();
    expect(prefs.searchHistory, ['weather today', 'maps']);

    await tester.longPress(find.text('maps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all history'));
    await tester.pumpAndSettle();
    expect(find.text('Clear search history?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(prefs.searchHistory, ['weather today', 'maps'], reason: 'cancelled');

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(prefs.searchHistory, isEmpty);
    expect(find.byType(RecentSearches), findsNothing);
  });

  testWidgets('Settings → Search → Save search history: off asks, clears and hides the card', (tester) async {
    final prefs = await launch(tester, stored: {'searchHistory': history});
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Search'));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save search history'));
    await tester.tap(find.text('Save search history'));
    await tester.pumpAndSettle();
    expect(find.text('Stop saving searches?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(prefs.saveSearchHistory, isTrue);
    expect(prefs.searchHistory, history);
    await tester.tap(find.text('Save search history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(prefs.saveSearchHistory, isFalse);
    expect(prefs.searchHistory, isEmpty);
    await prefs.addSearch('ignored');
    expect(prefs.searchHistory, isEmpty);
  });

  testWidgets('Tiles: recent searches above your apps; tap searches it, Enter saves', (tester) async {
    final prefs = await launch(tester, stored: {'searchHistory': history, 'homeView': 'tiles'});
    await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(RecentSearches), findsOneWidget);
    expect(find.text('recent searches'), findsOneWidget);
    expect(tester.getTopLeft(find.text('weather today')).dy, lessThan(tester.getTopLeft(find.text('maps')).dy), reason: 'newest first');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/59_recent_searches_tiles.png'));

    await tester.tap(find.byTooltip('Fill in “weather today”'));
    await tester.pumpAndSettle();
    expect(typed(tester), 'weather today');
    expect(prefs.searchHistory, history);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    await tester.tap(find.text('spotify'));
    await tester.pumpAndSettle();
    expect(typed(tester), 'spotify');
    expect(find.byType(RecentSearches), findsNothing);
    expect(prefs.searchHistory.first, 'spotify');

    await tester.enterText(find.byType(TextField), 'slack news');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(prefs.searchHistory.first, 'slack news');
  });
}
