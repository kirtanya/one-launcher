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

Future<void> _press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

Future<void> _hold(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.select);
  await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
  await t.pumpAndSettle();
  await t.sendKeyUpEvent(LogicalKeyboardKey.select);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('TV Tiles: Metro Start, remote editing, look settings, back to Cinematic', (tester) async {
    await _loadFonts();
    TvApps.demo = true;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'homeView': 'tiles'});
    final prefs = await Prefs.load();

    await tester.pumpWidget(OneLauncherTv(prefs: prefs));
    await tester.pumpAndSettle();
    expect(find.text('start'), findsOneWidget, reason: 'Metro Start');
    // Top to bottom: quick actions → every resume item → the tiles. Lands on the first quick action.
    expect(_focused(), 'tile:q:t:inputs', reason: 'lands on the first quick action');
    expect(find.text('inputs'), findsOneWidget);
    expect(find.text('The Long Night'), findsWidgets, reason: 'playing / paused');
    expect(find.text('Midnight City'), findsWidgets, reason: 'watch history');
    expect(find.text('Coastline'), findsWidgets, reason: 'apps’ Watch Next');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_1_start.png'));

    // ↓ Resume row, → along it, ↓ into the tiles (the page scrolls down to them).
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'tile:r:now:com.netflix.ninja');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(), startsWith('tile:r:h:'));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'tile:clock');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_1b_tiles.png'));
    // ↑ back up: Resume (same card), quick actions, then the top bar.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), startsWith('tile:r:h:'));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), 'tile:q:t:inputs');
    // Hold OK on a quick action → Move right / Move left: one place along, focus stays on it.
    await _hold(tester);
    await tester.tap(find.text('Move right'));
    await tester.pumpAndSettle();
    expect(prefs.tvQuickActions.take(2), ['t:assistant', 't:inputs']);
    expect(_focused(), 'tile:q:t:inputs');
    await _hold(tester);
    await tester.tap(find.text('Move left'));
    await tester.pumpAndSettle();
    expect(prefs.tvQuickActions.first, 't:inputs');
    expect(_focused(), 'tile:q:t:inputs');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), startsWith('h:'));
    // ↓ ↓ back to the Resume card it was on; Hold OK → Remove: focus moves to the next card.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), startsWith('tile:r:h:com.spotify'));
    await _hold(tester);
    await tester.tap(find.text('Remove from Continue watching'));
    await tester.pumpAndSettle();
    expect(find.text('Midnight City'), findsNothing);
    expect(_focused(), startsWith('tile:r:'), reason: 'the remote keeps focus in the Resume row');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'tile:clock');

    // Hold OK on the clock → Bigger; and a colour.
    await _hold(tester);
    expect(find.text('Bigger'), findsOneWidget);
    expect(find.text('Unpin from Start'), findsOneWidget);
    await tester.tap(find.text('Bigger'));
    await tester.pumpAndSettle();
    expect(prefs.tiles!.firstWhere((t) => t['id'] == 'clock')['size'], 'w');
    await _hold(tester);
    await tester.tap(find.text('Colour'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Red'), 120, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Red'));
    await tester.pumpAndSettle();
    expect(prefs.tiles!.firstWhere((t) => t['id'] == 'clock')['colour'], 'ffc62828');
    await tester.tapAt(const Offset(40, 270));
    await tester.pumpAndSettle();

    // Customise → Tiles: glass, round corners, banners.
    await prefs.setGlass(style: 'glass');
    await prefs.setTileLook(radius: 16);
    await prefs.setTvSetting('tileBg', 'glow');
    await tester.pumpAndSettle();
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_2_glass.png'));
    // ↑ ↑ ↑ clock → Resume → quick actions → the top bar; → along it to Customise.
    for (final _ in [1, 2, 3]) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_focused(), startsWith('h:'));
    // Bounded: a bare while loop never ends (and no timeout can fire) if focus misses the target.
    for (var i = 0; i < 5 && _focused() != 'h:customise'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(_focused(), 'h:customise');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Home view'), findsOneWidget);
    await tester.tap(find.text('Tiles').last); // the section (the first is Home view's value)
    await tester.pumpAndSettle();
    expect(find.text('Rows of tiles'), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_3_settings.png'));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Home view → Cinematic: the rows are back.
    await tester.tap(find.text('Home view'));
    await tester.pumpAndSettle();
    expect(prefs.homeView, 'classic');
    await tester.tapAt(const Offset(40, 270));
    await tester.pumpAndSettle();
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('start'), findsNothing);
  });
}
