import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main_tv.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tv/tv_apps.dart';
import 'package:one_launcher/tv/tv_ratings.dart';
import 'package:one_launcher/tv/tv_title.dart';
import 'package:one_launcher/ui/ds.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  await (FontLoader('ClockFlex')..addFont(Future.value(ByteData.view(File('assets/fonts/ClockFlex.ttf').readAsBytesSync().buffer)))).load();
  final loader = FontLoader('InstrumentSans');
  for (final w in [400, 500, 600]) {
    loader.addFont(Future.value(ByteData.view(File('assets/fonts/InstrumentSans-$w.ttf').readAsBytesSync().buffer)));
  }
  await loader.load();
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
  }
}

String? _focused() => FocusManager.instance.primaryFocus?.debugLabel;

/// Puts focus back on a node by its label (after a panel closes, focus returns to the chip).
void _focusLabel(String label) {
  void visit(FocusNode n) {
    if (n.debugLabel == label) n.requestFocus();
    n.children.forEach(visit);
  }

  visit(FocusManager.instance.rootScope);
}

Future<void> _press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('TV: quick action chips — labels always / only when focused / never, and size', (tester) async {
    await _loadFonts();
    TvApps.demo = true;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncherTv(prefs: prefs));
    await tester.pumpAndSettle();
    expect(find.text('Network'), findsOneWidget, reason: 'labels by default');
    double chipHeight() => tester.getSize(find.ancestor(of: find.byIcon(Icons.wifi_rounded), matching: find.byType(AnimatedContainer)).first).height;
    expect(chipHeight(), 40);

    await prefs.setTvSetting('quickLabels', 'never');
    await tester.pumpAndSettle();
    expect(find.text('Network'), findsNothing, reason: 'icons only');
    expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);

    await prefs.setTvSetting('quickLabels', 'focus');
    await tester.pumpAndSettle();
    expect(find.text('Network'), findsNothing, reason: 'not focused');
    expect(find.text('Inputs'), findsOneWidget, reason: 'the focused (first) chip keeps its label');

    await prefs.setTvSetting('quickSize', .8);
    await tester.pumpAndSettle();
    expect(chipHeight(), closeTo(32, .1), reason: 'small chips');
  });

  testWidgets('TV: remote moves tile by tile, rows remember their spot, OK-hold opens options, search', (tester) async {
    await _loadFonts();
    TvApps.demo = true;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2; // 960×540, a 1080p TV
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();

    await tester.pumpWidget(OneLauncherTv(prefs: prefs));
    await tester.pumpAndSettle();
    expect(find.text('Continue watching'), findsOneWidget);
    // Watch history kept on the TV joins Continue watching (apps closed since).
    expect(find.text('Midnight City'), findsWidgets);
    expect(find.text('How lighthouses work'), findsWidgets);
    expect(find.text('Your apps'), findsOneWidget);
    // Lands on the first quick action; the title block shows what you were watching.
    expect(_focused(), 'quick:t:inputs');
    // Quick action chips sit above the rows.
    expect(find.text('Inputs'), findsOneWidget);
    expect(find.text('Network'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets); // chip + the Settings app tile
    // ▶ Resume sits right above the quick actions (something is paused: The Long Night).
    expect(find.text('Resume'), findsWidgets);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), startsWith('resume:'));
    expect(find.text('The Long Night on Netflix'), findsOneWidget);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_8_resume.png'));
    // Live controls next to Resume: ⏮ ⏯ ⏭.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(), 'resume:m:prev');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(), 'resume:m:toggle');
    expect(find.text('Play'), findsOneWidget, reason: 'paused → the hint says Play');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_9_controls.png'));
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), 'h:search', reason: 'then Search');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'quick:t:inputs');
    expect(find.text('Open Inputs'), findsOneWidget, reason: 'hint names the chip; the title block keeps the show');
    // Hold OK on a chip → its options → Edit quick actions → tick Captions → a new chip.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Remove from quick actions'), findsOneWidget);
    await tester.tap(find.text('Edit quick actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Captions'));
    await tester.pumpAndSettle();
    expect(prefs.tvQuickActions, contains('t:captions'));
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_7_quick_edit.png'));
    await tester.tapAt(const Offset(40, 270)); // close the panel
    await tester.pumpAndSettle();
    expect(find.text('Captions'), findsOneWidget, reason: 'new chip in the row');
    _focusLabel('quick:t:inputs');
    await tester.pumpAndSettle();
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_0_quick.png'));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final first = _focused()!;
    expect(first, startsWith('continue:now:'));
    expect(find.text('The Long Night'), findsWidgets);
    expect(find.textContaining('CONTINUE WATCHING · NETFLIX'), findsOneWidget);
    expect(find.textContaining('min left'), findsWidgets);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_1_home.png'));

    // → → moves along the row; ↓ goes to the next row, ↑ comes back to the same tile.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    final third = _focused()!;
    expect(third, isNot(first));
    expect(find.text('How lighthouses work'), findsWidgets, reason: 'title block follows focus (a history item)');
    expect(find.textContaining('2 days ago'), findsOneWidget, reason: 'history says when');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), startsWith('fav:'));
    // Netflix is what you were watching: focusing the app shows that show, not just its name.
    expect(find.textContaining('CONTINUE WATCHING · NETFLIX'), findsOneWidget);
    expect(find.text('The Long Night'), findsWidgets);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_2_next_row.png'));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), third, reason: 'row remembers the last tile');

    // ↑ goes through the chips to the top bar, ↓ comes back to the same card.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), startsWith('quick:'));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), startsWith('resume:'));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), startsWith('h:'));
    for (var k = 0; k < 3; k++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused(), third);

    // Hold OK → options panel (and letting go doesn't pick the first option).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Remove from Continue watching'), findsOneWidget, reason: 'history item options; panel still open after release');
    expect(find.text('App info'), findsOneWidget);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_3_options.png'));
    await tester.tapAt(const Offset(40, 270)); // outside the panel
    await tester.pumpAndSettle();
    expect(find.text('App info'), findsNothing);
    // An app's options.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Add to Your apps').evaluate().isNotEmpty || find.text('Remove from Your apps').evaluate().isNotEmpty, isTrue);
    // Move: Hold OK → Move → → slides the app one place right → OK done. Saved.
    final before = [...prefs.favourites];
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget, reason: 'hint says OK = done');
    final moved = _focused()!;
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_5_move.png'));
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Done'), findsNothing);
    expect(_focused(), moved, reason: 'focus stays on the moved app');
    expect(prefs.favourites.indexOf(moved.split(':').last), 1, reason: 'now second (was first): $before → ${prefs.favourites}');

    // Your apps ends with "All apps" → the All apps screen (every app, sortable).
    for (var k = 0; k < 20 && _focused() != 'fav:all-apps'; k++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(_focused(), 'fav:all-apps');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('All apps'), findsOneWidget);
    expect(find.text('A–Z'), findsOneWidget);
    expect(find.text('File Manager'), findsWidgets, reason: 'apps that aren’t in Your apps are here too');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_12_all_apps.png'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Sort'), findsNothing, reason: 'Back returns home');

    // Back on the home screen → the default spot: the first quick action.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_focused(), 'quick:t:inputs');

    // No quick actions → the default spot is the first app.
    final saved = prefs.tvQuickActions;
    await prefs.setTvQuickActions([]);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_focused(), startsWith('fav:'), reason: 'first app');
    await prefs.setTvQuickActions(saved);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), 'h:search');

    // Customise → Colours → Purple: the accent changes live.
    final before2 = DS.palette.hero;
    await _press(tester, LogicalKeyboardKey.arrowRight); // Search → Voice search
    expect(_focused(), 'h:voice');
    await _press(tester, LogicalKeyboardKey.arrowRight); // → Customise
    await _press(tester, LogicalKeyboardKey.select);
    await tester.scrollUntilVisible(find.text('Colours'), 120, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colours'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Purple'), 120, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purple'));
    await tester.pumpAndSettle();
    expect(DS.palette.hero, isNot(before2), reason: 'accent recoloured');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_10_colours.png'));
    await tester.tapAt(const Offset(40, 270));
    await tester.pumpAndSettle();
    // Customise → Home screen → Remote hints off: "OK · Hold OK" disappears; Cards → Large.
    expect(find.text('Hold OK'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select); // focus is still on Customise
    expect(find.text('Home screen'), findsOneWidget);
    expect(find.text('Remote & behaviour'), findsOneWidget);
    await tester.tap(find.text('Home screen'));
    await tester.pumpAndSettle();
    expect(find.text('Remote hints (OK · Hold OK)'), findsOneWidget);
    await tester.tap(find.text('Remote hints (OK · Hold OK)'));
    await tester.pumpAndSettle();
    expect(prefs.tvSettings['hints'], false);
    expect(find.text('Hold OK'), findsNothing, reason: 'hints hidden live behind the panel');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_11_customise.png'));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cards & motion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card size'));
    await tester.pumpAndSettle();
    expect(prefs.tvSettings['cardScale'], 1.15, reason: 'Medium → Large');
    await tester.tapAt(const Offset(40, 270));
    await tester.pumpAndSettle();
    await prefs.resetTvSettings();
    await tester.pumpAndSettle();
    expect(find.text('Hold OK'), findsOneWidget, reason: 'Reset brings everything back');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowLeft); // back to Search

    // Search: type → shows & films actions (everywhere / in an app) + matching apps.
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Popular now'), findsOneWidget, reason: 'before typing: the catalog’s most popular');
    expect(find.text('Coastline'), findsWidgets);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_4a_popular.png'));
    await tester.enterText(find.byType(TextField), 'night');
    await tester.pump(const Duration(milliseconds: 500)); // search waits for typing to pause
    await tester.pumpAndSettle();
    expect(find.text('Shows & films'), findsOneWidget);
    expect(find.text('The Long Night'), findsWidgets);
    expect(find.text('Night Shift'), findsWidgets);
    // Google TV first: search it for the words, or voice; posters below.
    expect(find.text('Search Google TV for “night”'), findsOneWidget);
    expect(find.text('Voice search'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<EditableText>()));
    expect(find.text('Search Google TV for “night”'), findsOneWidget);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_4_search.png'));

    // ↓ to the posters (IMDb's pill on each); OK on one → its page: scores, where to watch (WatchHub links into
    // apps on this TV), Open in Nuvio, cast; the sources named at the bottom.
    TvPoster? poster() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvPoster>();
    for (var k = 0; k < 4 && poster() == null; k++) {
      await _press(tester, LogicalKeyboardKey.arrowDown); // through the search pills (they wrap)
    }
    expect(poster()?.title.title, 'Night Shift', reason: 'a title starting with the words leads, then the more popular word match');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(poster()?.title.title, 'The Long Night');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Watch on Netflix'), findsOneWidget);
    expect(find.text('Watch on Hotstar'), findsOneWidget, reason: 'JioHotstar → the Hotstar app');
    expect(find.text('Watch on Prime Video'), findsOneWidget, reason: 'Amazon Video → Prime Video app');
    expect(find.byWidgetPredicate((w) => w is ImdbBadge && w.score == 8.4 && w.size > 11), findsOneWidget, reason: 'IMDb’s pill, big');
    expect(find.byType(RottenTomatoesBadge), findsNothing, reason: 'a series: IMDb only');
    expect(find.text('Reviews · 12'), findsOneWidget);
    expect(find.text('Open in Nuvio'), findsOneWidget, reason: 'an installed app opens stremio:///detail/…');
    expect(find.text('Also on Google Play Movies (rent, buy)'), findsOneWidget, reason: 'no app for it here: listed');
    expect(find.text('Mira Rao'), findsOneWidget);
    expect(find.text('Trailer'), findsOneWidget);
    expect(find.text('Data: Cinemeta · WatchHub · OMDb · TMDB'), findsOneWidget);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_6_title.png'));
  });
}
