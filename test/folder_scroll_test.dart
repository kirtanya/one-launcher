import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Four apps in each of the ten folders, so the list is much taller than the screen.
const _apps = {
  'Telegram': 'org.telegram', 'Signal': 'org.signal', 'Discord': 'com.discord', 'Reddit': 'com.reddit', //
  'Slack': 'com.slack', 'Zoom': 'us.zoom', 'Notion': 'so.notion', 'Jira': 'com.atlassian.jira', //
  'Groww': 'com.groww', 'Kite': 'com.zerodha.kite', 'CRED': 'com.dreamplug', 'Slice': 'com.slice', //
  'Spotify': 'com.spotify', 'Netflix': 'com.netflix', 'VLC': 'org.videolan.vlc', 'Shazam': 'com.shazam', //
  'Myntra': 'com.myntra', 'Zepto': 'com.zepto', 'Nykaa': 'com.nykaa', 'Ajio': 'com.ajio', //
  'Uber': 'com.ubercab', 'Rapido': 'com.rapido', 'Waze': 'com.waze', 'Agoda': 'com.agoda', //
  'Kindle': 'com.kindle', 'Medium': 'com.medium', 'Quora': 'com.quora', 'Inshorts': 'com.inshorts', //
  'Chess': 'com.chess', 'Ludo King': 'com.ludo', 'Puzzle': 'com.puzzle', 'Rummy': 'com.rummy', //
  'Strava': 'com.strava', 'Headspace': 'com.headspace', 'Practo': 'com.practo', 'Fitbit': 'com.fitbit', //
  'Calculator': 'com.calculator', 'Chrome': 'com.android.chrome', 'Recorder': 'com.recorder', 'Weather': 'com.weather',
};
const _folders = ['Social', 'Work', 'Money', 'Watch & Listen', 'Shop & Services', 'Travel', 'News & Reading', 'Games', 'Health & Home', 'Tools'];

void main() {
  ScrollPosition list(WidgetTester t) =>
      t.state<ScrollableState>(find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first).position;
  Future<Prefs> start(WidgetTester tester, {required bool auto}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final e in _apps.entries) {'package': e.value, 'label': e.key, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({'autoOpenFolders': auto});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    // Sheet to full screen: a slow drag (no fling), so the list itself stays at the top.
    await tester.timedDrag(find.text('Social'), const Offset(0, -700), const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400)); // a beat before browsing
    expect(find.byTooltip('Customise folder'), findsNothing, reason: 'opening the drawer opens no folder');
    // Start browsing from the top of the list (a jump the app makes, not the user's scroll).
    list(tester).jumpTo(0);
    await tester.pumpAndSettle();
    return prefs;
  }

  double screenH(WidgetTester t) => t.view.physicalSize.height / t.view.devicePixelRatio;
  Finder open() => find.byTooltip('Customise folder'); // only the open folder shows •••

  testWidgets('scroll-to-open: the folder that stops in the middle opens, the last one opens at the bottom, the top closes them', (tester) async {
    await start(tester, auto: true);
    expect(open(), findsNothing, reason: 'at the top the green card has focus');

    // Scroll a little and let go → the folder in the middle opens and is centred.
    await tester.dragFrom(const Offset(200, 500), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(open(), findsOneWidget, reason: 'a folder opened when the scroll came to rest');
    final firstOpenY = tester.getCenter(open()).dy;
    String openName() {
      final y = tester.getTopLeft(open()).dy;
      // The open folder's name is the closest folder title above its ••• button.
      String? best;
      var bestY = double.negativeInfinity;
      for (final n in _folders) {
        final f = find.text(n);
        if (f.evaluate().isEmpty) continue;
        final ny = tester.getTopLeft(f.first).dy;
        if (ny <= y && ny > bestY) (best, bestY) = (n, ny);
      }
      return best!;
    }

    final first = openName();
    final mid = screenH(tester) / 2;
    expect((tester.getTopLeft(find.text(first)).dy - mid).abs(), lessThan(screenH(tester) * .4), reason: '$first is around the middle');

    // Keep scrolling → the next folder takes over; only one is open.
    await tester.dragFrom(const Offset(200, 650), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(open(), findsOneWidget);
    final second = openName();
    expect(second, isNot(first), reason: 'the next folder opened, $first closed');
    expect(_folders.indexOf(second), greaterThan(_folders.indexOf(first)));
    expect(firstOpenY, isNonZero);

    // All the way to the bottom: the last folder can't reach the middle, but still opens.
    for (var i = 0; i < 6; i++) {
      await tester.flingFrom(const Offset(200, 600), const Offset(0, -500), 3000);
      await tester.pumpAndSettle();
    }
    expect(open(), findsOneWidget);
    expect(find.text('Calculator'), findsOneWidget, reason: 'bottom edge case: the last folder (Tools) opens');
    expect(find.text('Strava'), findsNothing, reason: 'and the one before it closed');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/16_scroll_open_bottom.png'));

    // Back to the top: the green card is in focus, so the open folder closes.
    for (var i = 0; i < 8; i++) {
      await tester.flingFrom(const Offset(200, 200), const Offset(0, 300), 1500);
      await tester.pumpAndSettle();
    }
    expect(open(), findsNothing, reason: 'top edge: nothing open');
  });

  testWidgets('scroll-to-open is off by default: scrolling opens nothing; Settings has the switch', (tester) async {
    final prefs = await start(tester, auto: false);
    await tester.dragFrom(const Offset(200, 500), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(open(), findsNothing);
    expect(prefs.autoOpenFolders, isFalse);
  });
}
