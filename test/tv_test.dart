import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main_tv.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tv/tv_apps.dart';
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
    expect(find.text('Your apps'), findsOneWidget);
    // Lands on the first quick action; the title block shows what you were watching.
    expect(_focused(), 'quick:t:inputs');
    // Quick action chips sit above the rows.
    expect(find.text('Inputs'), findsOneWidget);
    expect(find.text('Network'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets); // chip + the Settings app tile
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), 'h:search', reason: 'Search is one ↑ away');
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
    expect(find.text('Final Over'), findsWidgets, reason: 'title block follows focus');
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
    expect(_focused(), startsWith('h:'));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), third);

    // Hold OK → options panel (and letting go doesn't pick the first option).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Watch'), findsNWidgets(2), reason: 'programme options; panel still open after release');
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
    expect(_focused(), 'h:search');

    // Search: type → shows & films actions (everywhere / in an app) + matching apps.
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Trending this week'), findsOneWidget, reason: 'before typing: what’s trending');
    await tester.enterText(find.byType(TextField), 'night');
    await tester.pump(const Duration(milliseconds: 500)); // search waits for typing to pause
    await tester.pumpAndSettle();
    expect(find.text('Shows & films'), findsOneWidget);
    expect(find.text('The Long Night'), findsWidgets);
    expect(find.text('Night Shift'), findsWidgets);
    expect(find.text('Search everywhere for “night”'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<EditableText>()));
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_4_search.png'));

    // OK on a poster → its page: ratings, where to watch (apps on this TV), cast.
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Where to watch'), findsOneWidget);
    expect(find.text('Watch on Netflix'), findsOneWidget);
    expect(find.text('Watch on Hotstar'), findsOneWidget, reason: 'JioHotstar → the Hotstar app');
    expect(find.text('Watch on Prime Video'), findsOneWidget, reason: 'Amazon Video → Prime Video app');
    expect(find.text('8.4 TMDB'), findsOneWidget);
    expect(find.text('Mira Rao'), findsOneWidget);
    expect(find.text('Trailer'), findsOneWidget);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_6_title.png'));
  });
}
