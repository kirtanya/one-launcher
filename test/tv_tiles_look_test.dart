import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/main_tv.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tiles/landing.dart' show Landed;
import 'package:one_launcher/tiles/tiles_home.dart' show TileSurface;
import 'package:one_launcher/tv/tv_apps.dart';
import 'package:one_launcher/tv/tv_metro.dart';
import 'package:one_launcher/tv/tv_settings.dart';
import 'package:one_launcher/tv/tv_tiles.dart';
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

Future<Prefs> _start(WidgetTester tester, [Map<String, Object> initial = const {}]) async {
  await _loadFonts();
  TvApps.demo = true;
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2; // 960×540, a 1080p TV
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'homeView': 'tiles', ...initial});
  final prefs = await Prefs.load();
  await tester.pumpWidget(OneLauncherTv(prefs: prefs));
  await tester.pumpAndSettle();
  return prefs;
}

/// The whole screen as text (layout, paint settings, words): changes when anything visible does.
String _screen() => RendererBinding.instance.renderViews.first.toStringDeep();

/// Fills of every tile-shaped surface on screen (tiles, quick actions, resume cards, top bar).
Set<int> _fills(WidgetTester t) => {for (final s in t.widgetList<TileSurface>(find.byType(TileSurface))) s.colour.withValues(alpha: 1).toARGB32()};

/// Anything drawn with rounded corners or as a circle (Tiles with square corners: there must be none).
List<String> _rounded(WidgetTester tester) {
  final out = <String>[];
  bool round(BorderRadiusGeometry? r) => r != null && r.resolve(TextDirection.ltr) != BorderRadius.zero;
  void visit(RenderObject o) {
    if (o is RenderDecoratedBox && o.decoration is BoxDecoration) {
      final d = o.decoration as BoxDecoration;
      if (d.shape == BoxShape.circle || round(d.borderRadius)) out.add('${o.runtimeType} ${d.borderRadius ?? d.shape}');
    }
    if (o is RenderClipRRect && round(o.borderRadius)) out.add('ClipRRect ${o.borderRadius}');
    if (o is RenderPhysicalShape && o.clipper is ShapeBorderClipper) {
      final shape = (o.clipper as ShapeBorderClipper).shape;
      if (shape is RoundedRectangleBorder && round(shape.borderRadius)) out.add('PhysicalShape ${shape.borderRadius}');
      if (shape is CircleBorder || shape is StadiumBorder) out.add('PhysicalShape $shape');
    }
    o.visitChildren(visit);
  }

  RendererBinding.instance.renderViews.forEach(visit);
  for (final f in tester.widgetList<TextField>(find.byType(TextField))) {
    for (final b in [f.decoration?.border, f.decoration?.focusedBorder]) {
      if (b is OutlineInputBorder && round(b.borderRadius)) out.add('TextField ${b.borderRadius}');
    }
  }
  return out;
}

/// A round coloured icon as PNG bytes (so icons, glyph and banner options have something to draw).
Future<MemoryImage> _png(Color c, {int w = 64, int h = 64, bool round = true}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final paint = Paint()..color = c;
  round ? canvas.drawCircle(Offset(w / 2, h / 2), w / 2.4, paint) : canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), paint);
  final img = await rec.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return MemoryImage(bytes!.buffer.asUint8List());
}

Future<void> _openCustomise(WidgetTester tester) async {
  for (var i = 0; i < 4 && !(_focused() ?? '').startsWith('h:'); i++) {
    await _press(tester, LogicalKeyboardKey.arrowUp);
  }
  for (var i = 0; i < 5 && _focused() != 'h:customise'; i++) {
    await _press(tester, LogicalKeyboardKey.arrowRight);
  }
  expect(_focused(), 'h:customise');
  await _press(tester, LogicalKeyboardKey.select);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) {
    for (final dy in [120.0, -120.0]) {
      try {
        await tester.scrollUntilVisible(f, dy, scrollable: find.byType(Scrollable).last, maxScrolls: 30);
        break;
      } catch (_) {}
    }
  }
  await tester.ensureVisible(f.last);
  await tester.pumpAndSettle();
  await tester.tap(f.last);
  await tester.pumpAndSettle();
}

Future<void> _set(Prefs prefs, TvOption o, Object v) => o.write != null ? o.write!(prefs, v) : prefs.setTvSetting(o.key, v);

void main() {
  testWidgets('Tiles: Customise → Colours recolours every tile, button, card and glow — each choice its own accent', (tester) async {
    final prefs = await _start(tester);
    final start = _fills(tester);
    expect(start, hasLength(1), reason: 'one accent across tiles, quick actions, resume cards, top bar');
    expect(start.single, DS.hero.toARGB32());

    await _openCustomise(tester);
    await _tapText(tester, 'colours');
    final accents = <String, int>{};
    for (final name in ['blue', 'teal', 'green', 'yellow', 'orange', 'red', 'pink', 'purple', 'one original']) {
      await _tapText(tester, name);
      final f = _fills(tester);
      expect(f, hasLength(1), reason: '$name: every tile surface follows');
      expect(f.single, DS.hero.toARGB32());
      accents[name] = f.single;
      if (name == 'blue') await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_look_1_colours.png'));
    }
    expect(accents.values.toSet(), hasLength(accents.length), reason: 'no two colours give the same accent: $accents');
    expect(accents['blue'], isNot(accents['purple']));

    // Styles: each one looks different (Mono is grey, Neutral muted, Vibrant full).
    await _tapText(tester, 'red');
    final styles = <String, int>{};
    for (final s in ['tonal', 'vibrant', 'expressive', 'neutral', 'mono']) {
      await _tapText(tester, 'style: $s');
      styles[s] = _fills(tester).single;
    }
    expect(styles.values.toSet(), hasLength(5), reason: 'every style its own accent: $styles');
    final mono = HSLColor.fromColor(Color(styles['mono']!));
    expect(mono.saturation, lessThan(.05), reason: 'Mono is grey, not tinted');

    // The swatch in the panel is the colour Start gets.
    expect(prefs.themeStyle, 'monochrome');
    await _tapText(tester, 'style: tonal');
    final swatchRed = tester.widgetList<Container>(find.byType(Container)).map((c) => c.decoration).whereType<BoxDecoration>().map((d) => d.color?.toARGB32());
    expect(swatchRed, contains(_fills(tester).single), reason: 'the red swatch shows the accent Start has');

    // The glow background follows the accent too.
    await tester.tapAt(const Offset(40, 270));
    await tester.pumpAndSettle();
    await prefs.setTvSetting('tileBg', 'glow');
    await tester.pumpAndSettle();
    final glow = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<RadialGradient>()
        .first;
    expect(glow.colors.first.withValues(alpha: 1).toARGB32(), DS.hero.toARGB32());

    // Back to Cinematic: the classic palette is back (the Metro accent is Tiles' own).
    await prefs.setHomeView('classic');
    await tester.pumpAndSettle();
    expect(DS.metro, isFalse);
    expect(DS.palette.card, isNot(const Color(0xFF1B1B1B)));
  });

  testWidgets('Tiles: every option in Customise → Tiles visibly changes Start', (tester) async {
    final netflix = await tester.runAsync(() => _png(const Color(0xFFE50914)));
    final banner = await tester.runAsync(() => _png(const Color(0xFF3A6EA5), w: 160, h: 90, round: false));
    TvApps.instance.debugSeed(
      icons: {'com.netflix.ninja': netflix!, 'com.google.android.youtube.tv': netflix},
      art: {'com.netflix.ninja': TvArt(banner!, banner: true)},
      colours: {'com.netflix.ninja': const Color(0xFFE50914), 'com.google.android.youtube.tv': const Color(0xFFFF0000)},
    );
    final prefs = await _start(tester);
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(TvTilesStart));
      await precacheImage(netflix, ctx);
      await precacheImage(banner, ctx);
    });
    // Focus on a tile (clock), so focus / tilt options have something to show.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'tile:clock');

    // Shown only over time / on an action — proved in the next test.
    const elsewhere = {'tileNewSize', 'tileAnim', 'fx.turnstile', 'fx.live', 'tileFlip', 'clock24'};
    const glassOnly = {'glassBlur', 'glassTint', 'glassEdge', 'glassSheen'};
    final checked = <String>[];
    for (final (_, _, opts) in tvTilesGroups) {
      for (final o in opts) {
        if (elsewhere.contains(o.key)) continue;
        if (glassOnly.contains(o.key)) await prefs.setGlass(style: 'glass');
        await tester.pumpAndSettle();
        final base = _screen();
        final current = o.read?.call(prefs) ?? TvLook.get<Object>(o.key);
        for (final (v, label) in o.choices) {
          if (v == current) continue;
          // Medium clock: "Bigger tiles" and "Never" both leave the date off.
          if (o.key == 'tileClockDate' && v == 'off') continue;
          await _set(prefs, o, v);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(_screen(), isNot(base), reason: '${o.label} → $label shows on Start');
        }
        // (A clock style that's no preset — "Custom" — goes back to the first one.)
        await _set(prefs, o, o.choices.any((c) => c.$1 == current) ? current : o.choices.first.$1);
        if (glassOnly.contains(o.key)) await prefs.setGlass(style: 'solid');
        await tester.pumpAndSettle();
        checked.add(o.key);
      }
    }
    expect(checked.length, greaterThanOrEqualTo(25));

    // A few looks together (golden): headings, rainbow, tight, names on top & large, shadow,
    // icon-only quick actions, greeting, glow focus in the accent, white glyph icons.
    await prefs.setTileColours('rainbow');
    await prefs.setTileLook(radius: 8);
    for (final (k, v) in [
      ('tileHeadings', 'accent'),
      ('tileGap', 4.0),
      ('tileLabelPos', 'top'),
      ('tileLabelSize', 16.0),
      ('tileShadow', true),
      ('tileQuickStyle', 'icon'),
      ('tileTitle', 'home'),
      ('tileFocus', 'glow'),
      ('tileFocusColour', 'accent'),
      ('tileIconStyle', 'white'),
      ('tileResumeSize', 120.0),
    ]) {
      await prefs.setTvSetting(k, v);
    }
    await tester.pumpAndSettle();
    expect(find.text('quick actions'), findsOneWidget);
    expect(find.text('resume'), findsWidgets);
    expect(find.text('home'), findsOneWidget);
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_look_2_options.png'));

    await prefs.resetTvSettings();
    await prefs.setTileColours('dark');
    await prefs.setTvSetting('tileBg', 'gradient');
    await prefs.setTvSetting('tileQuickRow', false);
    await prefs.setTvSetting('tileFace', 'banner');
    await prefs.setTvSetting('tileCase', 'as');
    await tester.pumpAndSettle();
    expect(find.text('Inputs'), findsNothing, reason: 'quick actions row hidden');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_look_3_dark.png'));
  });

  testWidgets('Tiles: features — move, resize, colour, unpin, pin, add, reset, new tile size, landing, turnstile, clock', (tester) async {
    final prefs = await _start(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'tile:clock');

    // Start animation: the tiles land in the chosen style.
    await prefs.setLandingAnims(tiles: 'zoom');
    await tester.pumpAndSettle();
    expect(tester.widgetList<Landed>(find.byType(Landed)).every((l) => l.style == 'zoom'), isTrue);

    // Move: Hold OK → move → → (one place later) → OK.
    final before = tvTiles(prefs, await TvApps.instance.list()).map((t) => t.id).toList();
    await _hold(tester);
    await tester.tap(find.text('move'));
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.select);
    final after = prefs.tiles!.map((t) => t['id']).toList();
    expect(after.indexOf('clock'), 1, reason: 'moved: $before → $after');

    // Resize: bigger, then smaller.
    await _hold(tester);
    await tester.tap(find.text('bigger'));
    await tester.pumpAndSettle();
    expect(prefs.tiles!.firstWhere((t) => t['id'] == 'clock')['size'], 'w');
    await _hold(tester);
    await tester.tap(find.text('smaller'));
    await tester.pumpAndSettle();
    expect(prefs.tiles!.firstWhere((t) => t['id'] == 'clock')['size'], 'm');

    // Colour: a swatch, then back to the default.
    await _hold(tester);
    await tester.tap(find.text('colour'));
    await tester.pumpAndSettle();
    await _tapText(tester, 'teal');
    expect(prefs.tiles!.firstWhere((t) => t['id'] == 'clock')['colour'], 'ff0097a7');
    expect(_fills(tester), contains(0xFF0097A7));
    await _tapText(tester, 'start default');
    expect(prefs.tiles!.firstWhere((t) => t['id'] == 'clock')['colour'], isNull);
    await tester.tapAt(const Offset(40, 270));
    await tester.pumpAndSettle();

    // Clock: 24-hour / 12-hour, date always.
    await prefs.setTvSetting('clock24', '24');
    await prefs.setTvSetting('tileClockDate', 'on');
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(find.text('${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'), findsOneWidget);
    const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    expect(find.textContaining(days[now.weekday - 1]), findsOneWidget, reason: 'date on the medium clock');

    // Unpin, then Add a tile brings it back; Reset Start returns the defaults.
    await _hold(tester);
    await tester.tap(find.text('unpin from start'));
    await tester.pumpAndSettle();
    expect(prefs.tiles!.any((t) => t['id'] == 'clock'), isFalse);
    await _openCustomise(tester);
    await _tapText(tester, 'tiles');
    await _tapText(tester, 'add a tile');
    await _tapText(tester, 'clock');
    expect(prefs.tiles!.any((t) => t['id'] == 'clock'), isTrue);
    await _openCustomise(tester);
    await _tapText(tester, 'tiles');
    await _tapText(tester, 'reset start');
    expect(prefs.tiles, isNotNull, reason: 'asks first');
    await _tapText(tester, 'reset (tiles, sizes and colours back to the start)');
    expect(prefs.tiles, isNull);

    // New tiles: All apps → Hold OK → Pin to Start, at the chosen size.
    await prefs.setTvSetting('tileNewSize', 'w');
    final apps = await TvApps.instance.list();
    await tvTogglePin(prefs, apps, 'com.android.chrome');
    expect(prefs.tiles!.last, {'id': 'app:com.android.chrome', 'size': 'w'});
    await tvTogglePin(prefs, apps, 'com.android.chrome');
    expect(prefs.tiles!.any((t) => t['id'] == 'app:com.android.chrome'), isFalse, reason: 'unpinned');
    await tester.pumpAndSettle();

    // Start on (Remote & behaviour): Home lands there in Tiles too.
    for (final (v, want) in [('resume', 'tile:r:'), ('app', 'tile:'), ('search', 'h:search'), ('quick', 'tile:q:')]) {
      await prefs.setTvSetting('landing', v);
      await tester.pumpAndSettle();
      TvApps.instance.onHomePressed!();
      await tester.pumpAndSettle();
      expect(_focused(), startsWith(want), reason: 'Start on $v');
      if (v == 'app') expect(_focused(), isNot(startsWith('tile:q:')));
    }

    // Turnstile on launch: the app opens after the swing; off: at once.
    for (final on in [true, false]) {
      await prefs.setFx('turnstile', on);
      await prefs.setTiles([
        {'id': 'app:com.netflix.ninja', 'size': 'm'},
      ]);
      await prefs.setTvSetting('landing', 'app'); // Home → straight to the tiles
      await tester.pumpAndSettle();
      TvApps.instance.onHomePressed!();
      await tester.pumpAndSettle();
      final first = _focused()!;
      expect(first, 'tile:app:com.netflix.ninja');
      await prefs.noteTvLaunch('x'); // a known first recent
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 50));
      final opened = prefs.tvRecents.first != 'x';
      expect(opened, !on, reason: 'turnstile ${on ? 'on: waits for the swing' : 'off: opens at once'} ($first)');
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Tiles: live tiles flip at the chosen speed; off: they stay', (tester) async {
    await _loadFonts();
    TvApps.demo = true;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final art = await tester.runAsync(() => _png(const Color(0xFF884422), w: 160, h: 90, round: false));
    for (final (speed, live, flipsBy4s) in [(3.0, true, true), (9.0, true, false), (3.0, false, false)]) {
      SharedPreferences.setMockInitialValues({
        'homeView': 'tiles',
        'tvSettings': '{"tileFlip": $speed}',
        'tileFx': [if (live) 'live'],
      });
      final prefs = await Prefs.load();
      TvLook.read(prefs);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvTilesStart(
              prefs: prefs,
              apps: const [AppEntry(package: 'a', label: 'A')],
              header: const SizedBox(),
              resume: null,
              onLaunch: (_) {},
              onResume: () {},
              onAllApps: () {},
              onTop: () {},
              resumeCards: [
                TvResumeCard(
                  key: 'k',
                  info: TvResumeInfo(title: 'Show', app: 'App', art: art, playing: true),
                  onSelect: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      // Front: the artwork (an Image); back: just the details.
      final before = find.byType(Image).evaluate().length;
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      final flipped = find.byType(Image).evaluate().length != before;
      expect(flipped, flipsBy4s, reason: 'speed $speed s, live $live');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Tiles: search, a title’s page, All apps, panels and Add a source speak Metro, square corners', (tester) async {
    final prefs = await _start(tester);
    expect(prefs.tileRadius, 0);
    expect(_rounded(tester), isEmpty, reason: 'Start');

    // Search: big light "search", a flat square field, accent lowercase headers, tile buttons.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), 'h:search');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('search'), findsOneWidget);
    expect(find.text('popular now'), findsOneWidget);
    expect(tester.widget<Text>(find.text('popular now')).style?.color, TvMetro.accentText);
    expect(_rounded(tester), isEmpty, reason: 'search, before typing');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_look_4_search.png'));
    await tester.enterText(find.byType(TextField), 'night');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('shows & films'), findsOneWidget);
    expect(find.text('more ways to search'), findsOneWidget);
    expect(find.text('search google tv for “night”'), findsOneWidget, reason: 'Metro tile button, lowercase');
    expect(_rounded(tester), isEmpty, reason: 'search results');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_look_5_results.png'));

    // A title's page.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    for (var k = 0; k < 6 && !(_focused() ?? '').startsWith('poster'); k++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused(), 'poster');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('season 1'), findsOneWidget, reason: 'season tabs in Metro case');
    expect(find.text('cast'), findsOneWidget);
    expect(find.text('watch on netflix'), findsOneWidget);
    expect(_rounded(tester), isEmpty, reason: 'title page: pills, chips, cast, clips');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_look_6_title.png'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // All apps: "all apps", letter tiles, square app tiles.
    await tester.ensureVisible(find.text('all apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('all apps'));
    await tester.pumpAndSettle();
    expect(find.text('all apps'), findsWidgets);
    expect(find.text('n'), findsOneWidget, reason: 'letter tile');
    expect(_rounded(tester), isEmpty, reason: 'all apps');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_look_7_all_apps.png'));
    // Hold OK on an app: its panel (Metro rows, lowercase, square).
    await _hold(tester);
    expect(find.text('pin to start'), findsOneWidget);
    expect(_rounded(tester), isEmpty, reason: 'app options panel');
    await tester.tapAt(const Offset(40, 270));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Customise, its sections, the quick actions editor, Colours, Search → Sources, Add a source.
    await _openCustomise(tester);
    expect(find.text('customise'), findsOneWidget);
    expect(_rounded(tester), isEmpty, reason: 'customise');
    await _tapText(tester, 'tiles');
    await _tapText(tester, 'names & icons');
    expect(_rounded(tester), isEmpty, reason: 'a tiles section');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_look_8_customise.png'));
    await _tapText(tester, 'back');
    await _tapText(tester, 'back');
    await _tapText(tester, 'edit quick actions');
    expect(find.text('quick actions'), findsOneWidget);
    expect(_rounded(tester), isEmpty, reason: 'quick actions editor');
    await tester.tapAt(const Offset(40, 270));
    await tester.pumpAndSettle();
    await _openCustomise(tester);
    await _tapText(tester, 'search');
    await _tapText(tester, 'sources');
    expect(_rounded(tester), isEmpty, reason: 'sources');
    await _tapText(tester, 'add a source');
    expect(find.text('add a source'), findsOneWidget);
    expect(_rounded(tester), isEmpty, reason: 'add a source');
    await expectLater(find.byType(OneLauncherTv), matchesGoldenFile('shots/tv_tiles_look_9_add_source.png'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Round corners: everything follows the tile corner setting.
    await prefs.setTileLook(radius: 16);
    await tester.pumpAndSettle();
    expect(_rounded(tester), isNotEmpty);
  });
}
