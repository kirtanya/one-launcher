import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/search_dock.dart';
import 'package:one_launcher/ui/components.dart';
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
          for (final n in ['WhatsApp', 'Slack', 'Paytm', 'Spotify', 'Signal', 'Splitwise', 'Maps']) {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'favourites': ['com.paytm', 'com.slack'], // the green card shows them
      ...stored,
    });
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    return prefs;
  }

  double sheetTop(WidgetTester t) => t.getTopLeft(find.text('Paytm').first).dy;

  testWidgets('pull the drawer down → "Release to search" → search opens; closing glides back', (tester) async {
    await launch(tester);
    final rest = sheetTop(tester);
    expect(find.byType(TextField), findsNothing);

    final g = await tester.startGesture(tester.getCenter(find.text('Paytm').first));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, 15));
      await tester.pump();
    }
    expect(find.text('Pull to search'), findsOneWidget, reason: 'a pill grows in the gap');
    expect(sheetTop(tester), greaterThan(rest + 20), reason: 'the list follows the finger');
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(0, 15));
      await tester.pump();
    }
    expect(find.text('Release to search'), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget, reason: 'search is open');
    expect(find.text('Pull to search'), findsNothing);
    expect(find.text('Release to search'), findsNothing);

    // Type → results: best match, the others as a grid, then the web.
    await tester.enterText(find.byType(TextField), 's');
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Search the web'), findsOneWidget, reason: 'no Google app here → "the web"');
    expect(find.text('Find apps on Play Store'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/17_search_results.png'));
    await tester.tap(find.text('Find apps on Play Store'));
    await tester.pump();
    expect(calls.last.method, 'playSearch');
    expect(calls.last.arguments, {'query': 's'});
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsNothing, reason: 'search closes after handing off');
    expect(sheetTop(tester), closeTo(rest, 2), reason: 'back to the resting drawer (reverse of the pull)');
  });

  testWidgets('a short pull springs back; the gesture can be turned off', (tester) async {
    final prefs = await launch(tester);
    final rest = sheetTop(tester);
    await tester.dragFrom(tester.getCenter(find.text('Paytm').first), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'not far enough');
    expect(sheetTop(tester), closeTo(rest, 1), reason: 'sprang back');

    await prefs.setPullToSearch(false);
    await tester.pumpAndSettle();
    final g = await tester.startGesture(tester.getCenter(find.text('Paytm').first));
    for (var i = 0; i < 14; i++) {
      await g.moveBy(const Offset(0, 15));
      await tester.pump();
    }
    expect(find.text('Pull to search'), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('search bar at the top of the drawer; Enter with no app match searches the web', (tester) async {
    await launch(tester, stored: {'searchPosition': 'top'});
    expect(find.byType(SearchDock), findsOneWidget);
    final bar = tester.getTopLeft(find.byType(SearchDock));
    expect(bar.dy, lessThan(tester.getTopLeft(find.text('Paytm').first).dy), reason: 'above the pinned / most-used card');
    expect(bar.dy, lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio * .6), reason: 'not floating at the bottom');
    expect(find.byTooltip('Launcher settings'), findsOneWidget, reason: 'settings sits next to it');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/18_search_top.png'));

    await tester.tap(find.text('Search 7 apps'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'weather today');
    await tester.pumpAndSettle();
    expect(find.text('Nothing on your phone matches “weather today”'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(calls.last.method, 'webSearch');
    expect(calls.last.arguments, {'query': 'weather today'});
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('search finds phone settings; sources can be switched off; results stack upward from the bar', (tester) async {
    final prefs = await launch(tester);
    await tester.tap(find.text('Search 7 apps'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wifi');
    await tester.pumpAndSettle();
    expect(find.text('Phone settings'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsOneWidget);
    await tester.tap(find.text('Wi-Fi'));
    await tester.pump();
    expect(calls.last.method, 'openSetting');
    expect(calls.last.arguments, {'action': 'android.settings.WIFI_SETTINGS'});
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    // Bar at the bottom: the best app match sits lowest, the web card above it.
    await tester.tap(find.text('Search 7 apps'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sp');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Search the web')).dy, lessThan(tester.getTopLeft(find.text('Open')).dy), reason: 'results grow upward from the bar');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/19_results_upward.png'));

    // Search in: no web, no Play Store.
    await prefs.setSearchIn('google', false);
    await prefs.setSearchIn('play', false);
    await tester.pumpAndSettle();
    expect(find.text('Search the web'), findsNothing);
    expect(find.text('Find apps on Play Store'), findsNothing);
    expect(find.text('Open'), findsOneWidget, reason: 'apps still searched');
  });

  testWidgets('more results than fit above the keyboard: the best match still sits just above the bar', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Search 7 apps'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 1000); // keyboard up (physical px)
    await tester.enterText(find.byType(TextField), 's'); // apps + many phone settings
    await tester.pumpAndSettle();
    final barTop = tester.getTopLeft(find.byType(SearchDock)).dy;
    final open = tester.getBottomLeft(find.text('Open'));
    expect(open.dy, lessThan(barTop), reason: 'best match is above the bar, not behind it');
    expect(open.dy, greaterThan(barTop - 120), reason: 'and right next to it');
    // The other matching apps: one row that scrolls sideways, just above the best match.
    final card = find.ancestor(of: find.text('Open'), matching: find.byType(OneCard)); // the apps card
    final row = find.descendant(of: card, matching: find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal));
    expect(row, findsOneWidget);
    expect(tester.getBottomLeft(row).dy, lessThan(tester.getTopLeft(find.text('Open')).dy));
    expect(tester.getSize(row).height, lessThan(110), reason: 'a single row');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/20_results_keyboard.png'));
  });

  testWidgets('clock roundness: slider + presets set the ROND axis', (tester) async {
    final prefs = await launch(tester);
    await prefs.setClockStyle(round: 70);
    await tester.pumpAndSettle();
    final style = tester.widget<Text>(find.byType(Text).evaluate().map((e) => e.widget).whereType<Text>().where((t) => t.style?.fontFamily == 'ClockFlex').isEmpty
        ? find.byType(Text).first
        : find.byWidgetPredicate((w) => w is Text && w.style?.fontFamily == 'ClockFlex').first).style;
    expect(style?.fontVariations?.firstWhere((v) => v.axis == 'ROND').value, 70);
    expect(prefs.clockRound, 70);
  });

  testWidgets('Settings → Search: position + pull-down switch', (tester) async {
    final prefs = await launch(tester);
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Search'));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top of the app drawer'));
    await tester.pumpAndSettle();
    expect(prefs.searchPosition, 'top');
    await tester.tap(find.text('Pull down to search'));
    await tester.pumpAndSettle();
    expect(prefs.pullToSearch, isFalse);
  });
}
