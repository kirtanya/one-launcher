import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/home.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tiles/tiles_home.dart';
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
      ];
    }
    return null;
  });
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await Prefs.load();
  await tester.pumpWidget(OneLauncher(prefs: prefs));
  await tester.pumpAndSettle();
  return prefs;
}

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
