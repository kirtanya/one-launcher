import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/home.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tiles/tiles_home.dart';
import 'package:one_launcher/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _apps = ['Slack', 'Maps', 'Camera', 'Zoom', 'Amazon', 'Notes'];

Future<Prefs> _setUp(WidgetTester tester, Map<String, Object> initial, {List<MethodCall>? calls}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.88;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
    calls?.add(call);
    if (call.method == 'getApps') {
      return [
        for (final l in _apps) {'package': 'com.${l.toLowerCase()}', 'label': l, 'system': false, 'category': -1, 'installed': 0},
        {'package': 'com.teams@10', 'label': 'Teams', 'system': false, 'category': -1, 'installed': 0, 'work': true},
      ];
    }
    // Slack and the work Teams have one-colour (themed) glyphs.
    if (call.method == 'getMonoIcon' && {'com.slack', 'com.teams@10'}.contains((call.arguments as Map)['package'])) return _png;
    return null;
  });
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await Prefs.load();
  await tester.pumpWidget(OneLauncher(prefs: prefs));
  await tester.pumpAndSettle();
  return prefs;
}

// 1×1 white PNG.
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 11, 73, 68, 65, 84, //
  120, 156, 99, 248, 15, 4, 0, 9, 251, 3, 253, 251, 94, 107, 43, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

List<TileSpec> _tiles(Prefs p) => [for (final m in p.tiles!) TileSpec.fromJson(m)];

void main() {
  test('tiles pack first-fit into the grid like Start', () {
    final placed = packTiles(const [TileSpec('clock', 'w'), TileSpec('app:a', 'm'), TileSpec('app:b', 's'), TileSpec('app:c', 's'), TileSpec('app:d', 's'), TileSpec('app:e', 's'), TileSpec('app:f', 'm')]);
    final at = {for (final (t, c, r) in placed) t.id: (c, r)};
    expect(at['clock'], (0, 0), reason: 'wide: full row pair');
    expect(at['app:a'], (0, 2));
    expect(at['app:b'], (2, 2), reason: 'smalls fill the gap beside a medium');
    expect(at['app:e'], (3, 3));
    expect(at['app:f'], (0, 4));
    // 6 columns: the medium sits next to the wide.
    final six = {for (final (t, c, r) in packTiles(const [TileSpec('clock', 'w'), TileSpec('app:a', 'm')], cols: 6)) t.id: (c, r)};
    expect(six['app:a'], (4, 0));
  });

  testWidgets('Tiles view: Start tiles, edit (resize, colour, unpin), all apps A–Z + pin, back to Classic in Settings', (tester) async {
    final prefs = await _setUp(tester, {'homeView': 'tiles'});
    expect(find.byType(TilesHome), findsOneWidget);
    expect(prefs.tiles, isNotNull, reason: 'starting tiles laid out on first open');
    expect(_tiles(prefs).first.id, 'clock');
    expect(find.text('Amazon'), findsOneWidget, reason: 'medium tile shows its name');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/30_tiles_start.png'));

    // Long-press a tile → edit mode with its controls.
    await tester.longPress(find.text('Amazon'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.byTooltip('Resize'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).firstWhere((t) => t.id == 'app:com.amazon').size, 'w', reason: 'medium → wide');
    await tester.tap(find.byTooltip('Tile colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Accent'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).firstWhere((t) => t.id == 'app:com.amazon').colour, 'accent');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/31_tiles_edit.png'));
    await tester.tap(find.byTooltip('Unpin'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).any((t) => t.id == 'app:com.amazon'), isFalse);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);

    // The arrow → all apps, A–Z with letter tiles; long-press → Pin to Start.
    await tester.tap(find.byTooltip('All apps'));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget, reason: 'letter tile');
    expect(find.byIcon(Icons.work_rounded), findsOneWidget, reason: 'work app’s glyph badged (full-colour icons carry Android’s badge)');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/32_tiles_all_apps.png'));
    await tester.longPress(find.text('Amazon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin to Start'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).last.id, 'app:com.amazon', reason: 'pinned at the end of Start');
    // Letter tile → A–Z jump grid.
    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();
    expect(find.text('q'), findsOneWidget, reason: 'jump grid open (q: no apps, only in the grid)');
    await tester.tap(find.text('n').last);
    await tester.pumpAndSettle();
    expect(find.text('q'), findsNothing, reason: 'closed after jumping');

    // Settings → Home view → Classic.
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home view'));
    await tester.pumpAndSettle();
    expect(find.text('Tile colours'), findsOneWidget, reason: 'tile options while on Tiles');
    expect(find.text('Each app’s colour'), findsOneWidget, reason: 'its own short sheet over Start');
    await tester.ensureVisible(find.text('Corner roundness'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).last, const Offset(200, 0)); // corner roundness
    await tester.pumpAndSettle();
    expect(prefs.tileRadius, greaterThan(8));
    await tester.ensureVisible(find.text('Themed icons'));
    await tester.tap(find.text('Themed icons'));
    await tester.pumpAndSettle();
    expect(prefs.themedIcons, isTrue);
    expect(AppIcon.themed, isTrue);
    // Landing animations + the clock tile's own font.
    await tester.ensureVisible(find.text('Start animation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zoom').first);
    await tester.pumpAndSettle();
    expect(prefs.tileAnim, 'zoom');
    await tester.ensureVisible(find.text('Clock tile style'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clock tile style'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bubble'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bubble'));
    await tester.pumpAndSettle();
    expect(prefs.tileClockWeight, 900);
    expect(prefs.clockWeight, 300, reason: 'the classic clock keeps its own style');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Each app’s colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Each app’s colour'));
    await tester.tap(find.text('6 · more tiles'));
    await tester.pumpAndSettle();
    expect(prefs.tileColours, 'colourful');
    expect(prefs.tileColumns, 6);
    await tester.ensureVisible(find.text('Reset Start'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/33_home_view_settings.png'));
    await tester.tap(find.text('Reset Start'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs)[1].id, 'app:com.amazon', reason: 'starting tiles again (Amazon back in 2nd place, not last)');
    await tester.ensureVisible(find.text('Classic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    expect(prefs.homeView, 'classic');
    expect(find.text('Tile colours'), findsNothing);
    Navigator.of(tester.element(find.text('Classic')), rootNavigator: true).pop();
    await tester.pumpAndSettle();
    expect(find.byType(TilesHome), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Tiles: long-press and drag a tile to a new spot; quick-action tile; pull down on Start → search', (tester) async {
    final calls = <MethodCall>[];
    final prefs = await _setUp(tester, {'homeView': 'tiles'}, calls: calls);
    final before = [for (final t in _tiles(prefs)) t.id];
    expect(before.take(3), ['clock', 'app:com.amazon', 'app:com.camera']);
    // Pick Amazon (medium, top-left under the clock) up and drop it at the bottom right.
    final g = await tester.startGesture(tester.getCenter(find.text('Amazon')));
    await tester.pump(const Duration(milliseconds: 700)); // long-press picks it up
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(30, 40));
      await tester.pump(const Duration(milliseconds: 260));
    }
    await g.up();
    await tester.pumpAndSettle();
    final after = [for (final t in _tiles(prefs)) t.id];
    expect(after.indexOf('app:com.amazon'), greaterThan(1), reason: 'moved later on Start: $after');
    expect(after.toSet(), before.toSet(), reason: 'same tiles, new order');
    expect(find.text('Done'), findsOneWidget, reason: 'dragging enters edit mode');
    // Edit mode → Add tile → a quick action as a small tile; tapping it runs the action.
    await tester.tap(find.text('Add tile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flashlight'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).last.id, 'qa:b:torch');
    expect(_tiles(prefs).last.size, 's');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/34_tiles_action.png'));
    calls.clear();
    await tester.tap(find.byIcon(Icons.flashlight_on_outlined));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'quickAction' && (c.arguments as Map)['id'] == 'b:torch'), isNotEmpty);

    // Pull down past the top → all apps with the search box focused.
    await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue, reason: 'search focused');
    expect(find.text('Search 7 apps'), findsOneWidget);
  });

  testWidgets('long-press the remote button → hide it (back on in Settings)', (tester) async {
    final prefs = await _setUp(tester, {'remoteButton': true});
    await tester.longPress(find.byTooltip('TV remote'));
    await tester.pumpAndSettle();
    expect(find.text('Turn it back on in Settings → TV remote'), findsOneWidget);
    await tester.tap(find.text('Hide remote button'));
    await tester.pumpAndSettle();
    expect(prefs.remoteButton, isFalse);
    expect(find.byTooltip('TV remote'), findsNothing);
  });
}
