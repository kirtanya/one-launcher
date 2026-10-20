import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/main_tv.dart';
import 'package:one_launcher/one_stream.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tiles/tiles_home.dart' show TileSpec;
import 'package:one_launcher/tiles/today_panel.dart';
import 'package:one_launcher/tv/catalog.dart';
import 'package:one_launcher/tv/tv_apps.dart';
import 'package:one_launcher/tv/tv_search.dart';
import 'package:one_launcher/tv/tv_title.dart';
import 'package:one_launcher/ui/ds.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One Stream (the user's streaming app) inside One Launcher: its provider is mocked on the
/// method channel — search, Continue watching, a title's progress — and links open through it.

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

// No picture links: the posters draw their title panel (no network in tests).
final _found = [
  {'key': 'movie:693134', 'type': 'movie', 'tmdb': 693134, 'imdb': 'tt15239678', 'title': 'Dune: Part Two', 'year': 2024, 'rating': 8.5, 'progress': -1.0, 'remaining_min': -1, 'link': 'onestream://title/movie/693134'},
  {'key': 'tv:1399', 'type': 'tv', 'tmdb': 1399, 'imdb': 'tt0944947', 'title': 'Dune: Prophecy', 'year': 2024, 'progress': -1.0, 'remaining_min': -1, 'link': 'onestream://title/tv/1399'},
];
final _continue = [
  {'key': 'abc', 'type': 'tv', 'tmdb': 100, 'title': 'How lighthouses work', 'subtitle': 'S1 · E3', 'progress': .4, 'remaining_min': 18, 'link': 'onestream://resume/abc'},
  {'key': 'def', 'type': 'movie', 'tmdb': 200, 'title': 'Arrival', 'year': 2016, 'progress': .75, 'remaining_min': 29, 'link': 'onestream://resume/def'},
];

/// Answers One Stream's calls like its provider would; [log] gets every call.
Future<Object?>? _oneStream(MethodCall call, List<MethodCall> log, {bool available = true, bool watching = true}) {
  if (!call.method.startsWith('oneStream')) return null;
  log.add(call);
  return Future.value(switch (call.method) {
    'oneStreamAvailable' => available,
    'oneStreamOpen' => true,
    _ => switch ((call.arguments as Map)['path']) {
      '/search' => _found,
      '/continue' => watching ? _continue : const [],
      '/title' => [
        {..._found.first, 'progress': .3, 'remaining_min': 12, 'link': 'onestream://resume/dune'},
      ],
      _ => const [],
    },
  });
}

void main() {
  final calls = <MethodCall>[];
  tearDown(() {
    OneStream.instance.debugReset();
    OneStream.channel = const MethodChannel('one_launcher/apps');
  });

  Future<Prefs> phone(WidgetTester tester, {Map<String, Object> stored = const {}, bool watching = true}) async {
    calls.clear();
    await _loadFonts();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (_oneStream(call, calls, watching: watching) case final r?) return r;
      calls.add(call);
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Slack', 'Paytm', 'Spotify', 'Signal', 'Clock']) {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'favourites': ['com.paytm', 'com.slack'],
      ...stored,
    });
    final prefs = await Prefs.load();
    await OneStream.instance.refresh();
    expect(OneStream.instance.available.value, isTrue);
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('phone search: "Movies & shows" from One Stream after a pause; tap opens it; can be switched off', (tester) async {
    final prefs = await phone(tester);
    await tester.tap(find.byIcon(Icons.search_rounded).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'd');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Movies & shows'), findsNothing, reason: 'one letter: not asked');
    expect(calls.where((c) => c.method == 'oneStream'), isEmpty);

    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls.where((c) => c.method == 'oneStream'), isEmpty, reason: 'waits for typing to pause');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final asked = calls.lastWhere((c) => c.method == 'oneStream').arguments as Map;
    expect(asked['path'], '/search');
    expect((asked['params'] as Map)['q'], 'dune');
    expect(find.text('Movies & shows'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsWidgets);
    expect(find.text('2024'), findsWidgets, reason: 'the year under each poster');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/50_one_stream_search.png'));

    await tester.tap(find.bySemanticsLabel('Dune: Prophecy, 2024'));
    await tester.pump();
    expect(calls.last.method, 'oneStreamOpen');
    expect(calls.last.arguments, {'link': 'onestream://title/tv/1399'});
    await tester.pumpAndSettle();

    // Settings → Search → Search in → Movies & shows off: the row goes.
    await prefs.setSearchIn('onestream', false);
    expect(prefs.searchIn, isNot(contains('onestream')));
    await prefs.setSearchIn('onestream', true);
    expect(prefs.searchIn, contains('onestream'), reason: 'on by default, and back on');
  });

  testWidgets('phone search: nothing from One Stream when it isn’t installed', (tester) async {
    await phone(tester);
    OneStream.instance.debugReset(); // not installed
    await tester.tap(find.byIcon(Icons.search_rounded).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Movies & shows'), findsNothing);
    expect(calls.where((c) => c.method == 'oneStream'), isEmpty);
  });

  Future<void> openToday(WidgetTester tester) async {
    await tester.fling(find.byType(FittedBox).first, const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.byType(TodayPanel), findsOneWidget);
  }

  testWidgets('Today: "Continue watching" — posters, progress, time left; tap resumes; list layout; picker', (tester) async {
    final prefs = await phone(tester);
    await prefs.setTodayTiles([const TileSpec('today:stream', 'w').toJson(), const TileSpec('today:clock', 'm').toJson()]);
    await openToday(tester);
    expect(find.text('How lighthouses work'), findsWidgets, reason: 'wide: the latest one (and its picture’s stand-in)');
    expect(find.text('S1 · E3 · 18 min left'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/51_one_stream_today.png'));
    await tester.tap(find.text('How lighthouses work').last);
    await tester.pump();
    expect(calls.last.method, 'oneStreamOpen');
    expect(calls.last.arguments, {'link': 'onestream://resume/abc'});

    // Large: a row each, tap one.
    await prefs.setTodayTiles([const TileSpec('today:stream', 'l').toJson()]);
    await tester.pumpAndSettle();
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('2016'), findsNothing);
    expect(find.text('29 min left'), findsOneWidget, reason: 'no episode: just what’s left');
    await tester.tap(find.text('Arrival').last);
    await tester.pump();
    expect(calls.last.arguments, {'link': 'onestream://resume/def'});

    // List layout: rows with poster thumbs.
    await prefs.setTodayLook(layout: 'list');
    await tester.pumpAndSettle();
    expect(find.text('Arrival'), findsWidgets);
    expect(find.text('How lighthouses work'), findsWidgets);
    await prefs.setTodayLook(layout: 'tiles');
    await tester.pumpAndSettle();

    // The picker offers it only while One Stream is installed (not on the page now).
    await prefs.setTodayTiles([const TileSpec('today:clock', 'm').toJson()]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    expect(find.text('Continue watching'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    OneStream.instance.debugReset();
    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    expect(find.text('Continue watching'), findsNothing);
  });

  testWidgets('Today: "Continue watching" empty → "Nothing to continue"', (tester) async {
    final prefs = await phone(tester, watching: false);
    await prefs.setTodayTiles([const TileSpec('today:stream', 'w').toJson()]);
    await openToday(tester);
    expect(find.text('Nothing to continue'), findsOneWidget);
  });

  // ---- TV ----

  Future<void> tv(WidgetTester tester) async {
    calls.clear();
    await _loadFonts();
    TvApps.demo = true;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    OneStream.channel = const MethodChannel('one_launcher/tv');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(OneStream.channel, (call) async => _oneStream(call, calls));
    await OneStream.instance.refresh();
  }

  // The title page's backdrop eases in (and a demo title may keep a spinner going): fixed pumps.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Widget tvApp(Widget home) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, fontFamily: DS.font),
    home: home,
  );

  testWidgets('TV search: "In One Stream" posters before "Shows & films"; OK opens the title in One Stream', (tester) async {
    await tv(tester);
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async => Catalog.instance.start(await Prefs.load())); // reads its files for real
    await tester.pumpWidget(tvApp(TvSearch(apps: const [], onLaunch: (_) {})));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('In One Stream'), findsOneWidget);
    expect(find.text('Shows & films'), findsOneWidget);
    expect(tester.getTopLeft(find.text('In One Stream')).dy, lessThan(tester.getTopLeft(find.text('Shows & films')).dy));
    expect(find.text('Dune: Part Two'), findsWidgets);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_15_one_stream_search.png'));
    // ↓ from the box lands on One Stream's first poster; OK opens it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvPoster>()?.title.title, 'Dune: Part Two');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(calls.last.method, 'oneStreamOpen');
    expect(calls.last.arguments, {'link': 'onestream://title/movie/693134'});
  });

  testWidgets('TV title page: "Resume in One Stream · 12 min left" first in Where to watch; else Play', (tester) async {
    await tv(tester);
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async => Catalog.instance.start(await Prefs.load())); // reads its files for real
    final dune = ShowTitle(id: 'tt15239678', type: 'movie', title: 'Dune: Part Two', year: '2024');
    await tester.pumpWidget(tvApp(TvTitlePage(title: dune, apps: const [], searchTargets: const [], onOpenApp: (_) {})));
    await settle(tester);
    final asked = calls.firstWhere((c) => c.method == 'oneStream').arguments as Map;
    expect(asked['path'], '/title');
    expect(asked['params'], {'type': 'movie', 'imdb': 'tt15239678'});
    expect(find.text('Resume in One Stream · 12 min left'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Resume in One Stream · 12 min left')).dx,
      lessThan(tester.getTopLeft(find.text('Search everywhere')).dx),
      reason: 'first in the row',
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_16_one_stream_title.png'));
    await tester.tap(find.text('Resume in One Stream · 12 min left'));
    await tester.pump();
    expect(calls.last.arguments, {'link': 'onestream://resume/dune'});

    // A title One Stream hasn't started: Play, by IMDb id.
    final other = ShowTitle(id: 'tt0000001', type: 'series', title: 'Other');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(OneStream.channel, (call) async {
      if (call.method == 'oneStream') return const [];
      return _oneStream(call, calls);
    });
    await tester.pumpWidget(tvApp(TvTitlePage(key: const ValueKey(2), title: other, apps: const [], searchTargets: const [], onOpenApp: (_) {})));
    await settle(tester);
    await tester.tap(find.text('Play in One Stream'));
    await tester.pump();
    expect(calls.last.arguments, {'link': 'onestream://imdb/tt0000001?type=tv'});

    // Not installed: no button.
    OneStream.instance.debugReset();
    await tester.pumpWidget(tvApp(TvTitlePage(key: const ValueKey(3), title: other, apps: const [], searchTargets: const [], onOpenApp: (_) {})));
    await settle(tester);
    expect(find.text('Play in One Stream'), findsNothing);
  });

  testWidgets('TV home: One Stream’s Continue watching joins the resume row (in the history’s place), OK resumes in One Stream', (tester) async {
    await tv(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncherTv(prefs: prefs));
    await tester.pumpAndSettle();
    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    expect(focused(), 'quick:t:inputs');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(), startsWith('continue:now:'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focused(), startsWith('continue:h:'), reason: 'Midnight City (history)');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focused(), 'continue:os:abc', reason: 'One Stream’s item takes its history entry’s place');
    expect(find.textContaining('ONE STREAM'), findsOneWidget, reason: 'the title block names it');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focused(), 'continue:os:def', reason: 'the rest follow the history');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(calls.last.method, 'oneStreamOpen');
    expect(calls.last.arguments, {'link': 'onestream://resume/def'});
  });
}
