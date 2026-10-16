import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/home.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/quick_chips.dart';
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

// The Tiles view speaks Metro (lowercase labels and titles): match text regardless of case.
Finder ci(String text) => find.byWidgetPredicate((w) => w is Text && w.data != null && w.data!.toLowerCase() == text.toLowerCase(), description: 'text "$text" (any case)');
Finder ciContains(String text) =>
    find.byWidgetPredicate((w) => w is Text && w.data != null && w.data!.toLowerCase().contains(text.toLowerCase()), description: 'text containing "$text" (any case)');

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
    expect(ci('Amazon'), findsOneWidget, reason: 'medium tile shows its name');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/30_tiles_start.png'));

    // Long-press a tile → edit mode with its controls.
    await tester.longPress(ci('Amazon'));
    await tester.pumpAndSettle();
    expect(ci('Done'), findsOneWidget);
    await tester.tap(find.byTooltip('Bigger'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).firstWhere((t) => t.id == 'app:com.amazon').size, 'w', reason: 'medium → wide');
    // And one size back down (no need to go round through large).
    await tester.tap(find.byTooltip('Smaller'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).firstWhere((t) => t.id == 'app:com.amazon').size, 'm', reason: 'wide → medium');
    await tester.tap(find.byTooltip('Bigger'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tile colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Accent'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).firstWhere((t) => t.id == 'app:com.amazon').colour, 'accent');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/31_tiles_edit.png'));
    await tester.tap(find.byTooltip('Unpin'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).any((t) => t.id == 'app:com.amazon'), isFalse);
    await tester.tap(ci('Done'));
    await tester.pumpAndSettle();
    expect(ci('Done'), findsNothing);

    // The arrow → all apps, A–Z with letter tiles; long-press → Pin to Start.
    await tester.tap(find.byTooltip('All apps'));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget, reason: 'letter tile');
    expect(find.byIcon(Icons.work_rounded), findsOneWidget, reason: 'work app’s glyph badged (full-colour icons carry Android’s badge)');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/32_tiles_all_apps.png'));
    await tester.longPress(ci('Amazon'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Pin to Start'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).last.id, 'app:com.amazon', reason: 'pinned at the end of Start');
    // Letter tile → A–Z jump grid.
    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();
    expect(find.text('q'), findsOneWidget, reason: 'jump grid open (q: no apps, only in the grid)');
    await tester.tap(find.text('n').last);
    await tester.pumpAndSettle();
    expect(find.text('q'), findsNothing, reason: 'closed after jumping');

    // Settings → Home view: a full-screen editor — the home screen live in the middle,
    // tabs of controls below.
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Home view'));
    await tester.pumpAndSettle();
    expect(ci('Home screen'), findsOneWidget, reason: 'the editor');
    expect(find.byWidgetPredicate((w) => w is TilesHome && w.preview), findsOneWidget, reason: 'live preview of Start');
    Future<void> tab(String name) async {
      await tester.ensureVisible(ci(name).last); // the tab bar scrolls sideways
      await tester.pumpAndSettle();
      await tester.tap(ci(name).last);
      await tester.pumpAndSettle();
    }

    // View: themed icons.
    await tester.tap(ci('Themed icons'));
    await tester.pumpAndSettle();
    expect(prefs.themedIcons, isTrue);
    expect(AppIcon.themed, isTrue);
    // Layout: corner roundness, columns.
    await tab('Layout');
    await tester.ensureVisible(ci('Corner roundness'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(prefs.tileRadius, greaterThan(8));
    await tester.ensureVisible(ci('6 · more tiles'));
    await tester.pumpAndSettle();
    await tester.tap(ci('6 · more tiles'));
    await tester.pumpAndSettle();
    expect(prefs.tileColumns, 6);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/33_home_view_settings.png'));
    // Look: colours.
    await tab('Look');
    await tester.ensureVisible(ci('Each app’s colour'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Each app’s colour'));
    await tester.pumpAndSettle();
    expect(prefs.tileColours, 'colourful');
    // Motion: the Start animation.
    await tab('Motion');
    await tester.tap(ci('Zoom').first); // the Start animation's (All apps has one too)
    await tester.pumpAndSettle();
    expect(prefs.tileAnim, 'zoom');
    // Clock: the clock tile's own font (the classic one keeps its own).
    await tab('Clock');
    // The presets scroll sideways (Classic first): bring Bubble into view.
    await tester.scrollUntilVisible(ci('Bubble'), 120, scrollable: find.ancestor(of: ci('Classic'), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(ci('Bubble'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Bubble'));
    await tester.pumpAndSettle();
    expect(prefs.tileClockWeight, 900);
    expect(prefs.clockWeight, 300, reason: 'the classic clock keeps its own style');
    // Layout → Reset Start.
    await tab('Layout');
    await tester.ensureVisible(ci('Reset Start'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Reset Start'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs)[2].id, 'app:com.amazon', reason: 'starting tiles again (Amazon back after the clock + chips, not last)');
    // View → Classic: the preview switches, and so does home.
    await tab('View');
    await tester.tap(ci('Classic'));
    await tester.pumpAndSettle();
    expect(prefs.homeView, 'classic');
    expect(find.byWidgetPredicate((w) => w is HomeScreen && w.preview), findsOneWidget, reason: 'preview follows');
    expect(ci('Layout'), findsNothing, reason: 'tile tabs only for Tiles');
    await tester.tap(ci('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(TilesHome), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Tiles: long-press and drag a tile to a new spot; quick-action tile; pull down on Start → search', (tester) async {
    final calls = <MethodCall>[];
    final prefs = await _setUp(tester, {'homeView': 'tiles'}, calls: calls);
    final before = [for (final t in _tiles(prefs)) t.id];
    expect(before.take(3), ['clock', 'chips', 'app:com.amazon']);
    // Pick Amazon (medium, top-left under the clock) up and drop it at the bottom right.
    final g = await tester.startGesture(tester.getCenter(ci('Amazon')));
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
    expect(ci('Done'), findsOneWidget, reason: 'dragging enters edit mode');
    // Back leaves edit mode — and the tile's controls go with it (they used to linger).
    expect(find.byTooltip('Bigger'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(ci('Done'), findsNothing);
    expect(find.byTooltip('Bigger'), findsNothing, reason: 'no edit controls outside edit mode');
    await tester.longPress(ci('Amazon'));
    await tester.pumpAndSettle();
    // Edit mode → Add tile → a quick action as a small tile; tapping it runs the action.
    await tester.tap(ci('Add tile'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Flashlight').last); // the picker's (the chips row has one too)
    await tester.pumpAndSettle();
    expect(_tiles(prefs).last.id, 'qa:b:torch');
    expect(_tiles(prefs).last.size, 's');
    await tester.tap(ci('Done'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/34_tiles_action.png'));
    calls.clear();
    await tester.tap(find.byIcon(Icons.flashlight_on_outlined).last);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'quickAction' && (c.arguments as Map)['id'] == 'b:torch'), isNotEmpty);
    // Our own TV remote as a tile: opens the remote sheet (not a phone action).
    await tester.longPress(ci('Amazon'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Add tile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(ci('TV remote'));
    await tester.tap(ci('TV remote'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Done'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).last.id, 'qa:b:remote');
    calls.clear();
    await tester.tap(find.byIcon(Icons.settings_remote_rounded).last);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'quickAction'), isEmpty);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'remote sheet open');
    Navigator.of(tester.element(find.byType(BottomSheet)), rootNavigator: true).pop();
    await tester.pumpAndSettle();

    // Pull down past the top → the search bar comes down from the top, focused; no results yet.
    expect(find.byType(TextField), findsNothing, reason: 'no search bar until searching');
    await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus, isTrue, reason: 'search focused');
    expect(ci('Search 7 apps & more'), findsOneWidget, reason: 'the classic home’s search pill');
    expect(ci('Search the web'), findsNothing, reason: 'results only once typing');
    await tester.enterText(find.byType(TextField), 'ma'); // several matches (one would just open)
    await tester.pumpAndSettle();
    // The classic home's results: best match with Open, the other apps in a row, then the web.
    expect(ci('Open'), findsOneWidget, reason: 'best match: Maps');
    expect(ci('Maps'), findsWidgets);
    expect(ci('Search the web'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/36_tiles_search.png'));
    // ✕ clears; ✕ again (empty) closes.
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(ci('Search the web'), findsNothing);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'closed');
    // Back closes it too; and going to all apps does.
    await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    // The close button above the keyboard closes it.
    await tester.tap(ci('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'close button');
    await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'Back closes search');
    // All apps: just a search icon; it opens the same bar.
    await tester.tap(find.byTooltip('All apps'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Search apps'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Tiles: the quick-actions row is one full-width group — no box, moves as one, customise inside', (tester) async {
    final calls = <MethodCall>[];
    final prefs = await _setUp(tester, {'homeView': 'tiles'}, calls: calls);
    expect(find.byType(QuickChip), findsNothing, reason: 'drawn as tiles, not classic chips');
    expect(ci('Set timer'), findsOneWidget);
    // Each chip is a tile filling the row's height — no extra space above or below.
    final timer = tester.getRect(find.ancestor(of: ci('Set timer'), matching: find.byType(Material)).first);
    final amazon = tester.getRect(find.ancestor(of: ci('Amazon'), matching: find.byType(Material)).first);
    final smallTile = amazon.height / 2 - 3; // a medium tile is two rows
    expect(timer.height, lessThan(smallTile * .7), reason: 'chips are shorter than app tiles');
    expect(timer.height, greaterThanOrEqualTo(44), reason: 'still easy to tap');
    // Tap a chip → runs it.
    await tester.tap(ci('Set timer'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'quickAction' && (c.arguments as Map)['id'] == 'b:timer'), isNotEmpty);

    // Long-press the row (on a chip) and drag it down past the apps → the whole group moves.
    final g = await tester.startGesture(tester.getCenter(ci('Flashlight')));
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 0; i < 14; i++) {
      await g.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 260));
    }
    await g.up();
    await tester.pumpAndSettle();
    final ids = [for (final t in _tiles(prefs)) t.id];
    expect(ids.indexOf('chips'), greaterThan(2), reason: 'row moved down: $ids');
    expect(ci('Set timer'), findsOneWidget, reason: 'still one row with its chips');
    // Edit mode: the row offers Customise (arrange / add inside), not resize or colour.
    expect(find.byTooltip('Customise quick actions'), findsWidgets);
    expect(find.byTooltip('Bigger'), findsNothing);
    await tester.tap(find.byTooltip('Customise quick actions').first);
    await tester.pumpAndSettle();
    expect(ci('Quick actions'), findsWidgets, reason: 'the same customise sheet as the classic view');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/35_tiles_chips_customise.png'));
  });

  testWidgets('Tiles interactions: folders, badges + live tile, turnstile launch, shortcuts, double-tap lock, wallpaper through tiles', (tester) async {
    final calls = <MethodCall>[];
    final prefs = await _setUp(tester, {'homeView': 'tiles', 'tileFx': ['tilt', 'live', 'turnstile', 'folders', 'badges', 'shortcuts', 'lock']}, calls: calls);
    Apps.instance.init();
    Future<void> push(String method, Object args) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage('one_launcher/apps', const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (_) {});

    // Folders: hold Camera over the middle of Maps → a folder of the two.
    final from = tester.getCenter(find.byType(TileGlyph).at(1)); // Camera (small, right of Amazon)
    final to = tester.getCenter(find.byType(TileGlyph).at(2)); // Maps
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 6)!);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 500)); // hold
    await g.moveBy(const Offset(1, 1));
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await tester.pumpAndSettle();
    final folder = _tiles(prefs).where((t) => t.isFolder).single;
    expect(folder.items.toSet(), {'com.maps', 'com.camera'});
    expect(_tiles(prefs).any((t) => t.id == 'app:com.camera' || t.id == 'app:com.maps'), isFalse);
    await tester.tap(ci('Done'));
    await tester.pumpAndSettle();
    // Tap → opens inline (its apps as small tiles); long-press one → move it out → folder of one = app tile again.
    final before = find.byType(TileGlyph).evaluate().length;
    await tester.tap(ci('Folder'));
    await tester.pumpAndSettle();
    expect(find.byType(TileGlyph).evaluate().length, before + 2, reason: 'folder open inline');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/37_tiles_folder_open.png'));
    final panel = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_FolderPanel');
    await tester.longPress(find.descendant(of: panel, matching: find.byType(TileGlyph)).first); // first app inside
    await tester.pumpAndSettle();
    await tester.tap(ci('Move out of folder'));
    await tester.pumpAndSettle();
    expect(_tiles(prefs).any((t) => t.isFolder), isFalse, reason: 'one app left → back to a tile');

    // Badges + live tile: Amazon gets 3 notifications → a badge, and its tile flips to them.
    await push('notifCounts', {'com.amazon': 3});
    await tester.pumpAndSettle();
    expect(ci('3'), findsWidgets, reason: 'badge');
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(ci('new notifications'), findsOneWidget, reason: 'live tile flipped');
    await tester.pump(const Duration(seconds: 10)); // flips back
    await tester.pump(const Duration(seconds: 1));

    // Turnstile: tap Amazon → Start swings away, then the app opens.
    calls.clear();
    await tester.tap(ci('Amazon'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.where((c) => c.method == 'launch'), isEmpty, reason: 'not yet — tiles swinging away');
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls.where((c) => c.method == 'launch'), isNotEmpty);
    await tester.pump(const Duration(seconds: 2)); // nothing opened (test) → Start comes back
    await tester.pumpAndSettle();

    // Double-tap empty space → lock; not allowed yet → explains + opens Accessibility settings.
    final empty = tester.getBottomLeft(find.byType(SingleChildScrollView).first) + const Offset(30, -60);
    await tester.tapAt(empty);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(empty);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'lockScreen'), isNotEmpty);
    expect(ci('Open Accessibility settings'), findsOneWidget);
    await tester.tap(ci('Open Accessibility settings'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'openAccessibility'), isNotEmpty);

    // Wallpaper through tiles (switch on) → black around the tiles.
    await prefs.setFx('window', true);
    await tester.pumpAndSettle();
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/38_tiles_window.png'));
  });

  testWidgets('Tiles: glass look — frosted tiles tinted with their colour; frost / tint / edge / sheen', (tester) async {
    final prefs = await _setUp(tester, {'homeView': 'tiles'});
    expect(find.byType(BackdropFilter), findsNothing, reason: 'solid by default');
    await tester.tap(find.byTooltip('All apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Home view'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Look').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(ci('Glass'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Glass'));
    await tester.pumpAndSettle();
    expect(prefs.tileStyle, 'glass');
    expect(find.byType(BackdropFilter), findsWidgets, reason: 'tiles frost what is behind them');
    await tester.ensureVisible(ci('Sheen'));
    await tester.pumpAndSettle();
    await tester.tap(ci('Sheen'));
    await tester.pumpAndSettle();
    expect(prefs.glassSheen, isFalse);
    await tester.ensureVisible(ci('Tint'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).at(1), const Offset(-400, 0)); // tint → none
    await tester.pumpAndSettle();
    expect(prefs.glassTint, lessThan(.05));
    await tester.drag(find.byType(Slider).at(1), const Offset(120, 0));
    await tester.pumpAndSettle();
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/39_tiles_glass.png'));
  });

  testWidgets('each view keeps its own look settings; Tiles chip look = size + what to show', (tester) async {
    final prefs = await _setUp(tester, {'homeView': 'classic', 'glassTint': .1, 'themedIcons': false});
    // Tiles starts from Classic's values…
    await prefs.setHomeView('tiles');
    await tester.pumpAndSettle();
    expect(prefs.glassTint, .1);
    // …then changes only its own.
    await prefs.setGlass(tint: .6);
    await prefs.setThemedIcons(true);
    await prefs.setChipLook({'size': 'large', 'content': 'icon'});
    await tester.pumpAndSettle();
    expect(find.text('Set timer'), findsNothing, reason: 'Tiles chips: icon only');
    await prefs.setHomeView('classic');
    await tester.pumpAndSettle();
    expect(prefs.glassTint, .1, reason: 'Classic kept its glass');
    expect(prefs.themedIcons, isFalse);
    expect(prefs.chipLook['content'], isNull, reason: 'Classic chips untouched');
    await prefs.setHomeView('tiles');
    await tester.pumpAndSettle();
    expect(prefs.glassTint, .6);
    expect(prefs.themedIcons, isTrue);
  });

  testWidgets('app menu: actions always on top; shortcuts show four, then "show all"', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') return [{'package': 'com.whatsapp', 'label': 'WhatsApp', 'system': false, 'category': -1, 'installed': 0}];
      if (call.method == 'listShortcuts') {
        return {
          'allowed': true,
          'shortcuts': [
            for (var i = 1; i <= 12; i++) {'id': 's:com.whatsapp|c$i|0', 'label': 'Contact $i', 'app': 'WhatsApp', 'package': 'com.whatsapp', 'work': false},
          ],
        };
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({'homeView': 'tiles'});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('All apps'));
    await tester.pumpAndSettle();
    await tester.longPress(ci('WhatsApp').last); // the list row (Start has a tile too)
    await tester.pumpAndSettle();
    // The main actions come first, then four shortcuts and a way to see the rest.
    expect(tester.getTopLeft(ci('Unpin from Start')).dy, lessThan(tester.getTopLeft(find.text('Contact 1')).dy));
    expect(find.text('Contact 4'), findsOneWidget);
    expect(find.text('Contact 5'), findsNothing);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/41_app_menu_tiles.png'));
    await tester.tap(ci('Show all (8 more)'));
    await tester.pumpAndSettle();
    expect(find.text('Contact 12', skipOffstage: false), findsOneWidget);
    expect(ci('Uninstall'), findsOneWidget, reason: 'still right there at the top');
  });

  testWidgets('long-press the remote button → hide it (back on in Settings)', (tester) async {
    final prefs = await _setUp(tester, {'remoteButton': true});
    await tester.longPress(find.byTooltip('TV remote'));
    await tester.pumpAndSettle();
    expect(ci('Turn it back on in Settings → TV remote'), findsOneWidget);
    await tester.tap(ci('Hide remote button'));
    await tester.pumpAndSettle();
    expect(prefs.remoteButton, isFalse);
    expect(find.byTooltip('TV remote'), findsNothing);
  });
}
