import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/main_tv.dart';
import 'package:one_launcher/one_stream.dart';
import 'package:one_launcher/one_stream_sheet.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tiles/tiles_home.dart' show TileSpec;
import 'package:one_launcher/tiles/today_panel.dart';
import 'package:one_launcher/tv/catalog.dart';
import 'package:one_launcher/tv/tv_apps.dart';
import 'package:one_launcher/tv/tv_one_stream.dart';
import 'package:one_launcher/tv/tv_search.dart';
import 'package:one_launcher/tv/tv_title.dart';
import 'package:one_launcher/tv_cast.dart';
import 'package:one_launcher/tv_remote.dart';
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

Map _details(Map p) => p['type'] == 'tv'
    ? {
        ..._found[1],
        'overview': 'Ten thousand years before Paul, the sisterhood takes shape.',
        'genres': 'Drama, Sci-Fi',
        'seasons': 2,
        'status': 'Returning',
        'in_watchlist': 0,
      }
    : {
        ..._found.first,
        'overview': 'Paul unites with the Fremen while on a path of revenge.',
        'genres': 'Sci-Fi, Adventure',
        'runtime_min': 167,
        'in_watchlist': 0,
        'resume_key': 'dune',
        'resume_progress': .3,
      };

List<Map> _episodes(Map p) => [
  for (var e = 1; e <= 4; e++)
    {
      'season': p['season'],
      'episode': e,
      'name': ['The Hidden Hand', 'Two Wolves', 'Sisterhood Above All', 'Twice Born'][e - 1],
      'air_date': '2024-11-${e + 10}',
      'aired': e < 4 ? 1 : 0,
      'progress': e == 1 ? 1.0 : (e == 2 ? .5 : -1.0),
      'link': 'onestream://resume/s${p['season']}e$e',
    },
];

List<Map> _sources(Map p) => [
  {'token': 'tok-best', 'name': 'Dune.2160p', 'provider': 'Torrentio', 'quality': '2160p', 'size_bytes': 12400000000, 'seeds': 812, 'kind': 'torrent', 'best': 1, 'downloadable': 1, 'hash': 'a1b2c3', 'file': 2, 'url': null},
  {'token': 'tok-1080', 'name': 'Dune.1080p', 'provider': 'Torrentio', 'quality': '1080p', 'size_bytes': 2100000000, 'seeds': 340, 'kind': 'torrent', 'best': 0, 'downloadable': 1, 'hash': null, 'file': -1, 'url': null},
  {'token': 'tok-web', 'name': 'Web', 'provider': 'Direct', 'quality': '720p', 'kind': 'stream', 'best': 0, 'downloadable': 0, 'url': 'https://cdn.example/dune 720.m3u8?a=1&b=2'},
];

final _dl = [
  {'key': 'dl1', 'title': 'Dune: Part Two', 'progress': .45, 'state': 'downloading', 'size_bytes': 2100000000},
  {'key': 'dl2', 'title': 'Arrival', 'progress': 1.0, 'state': 'done', 'size_bytes': 1500000000, 'play_link': 'onestream://play?source=local-dl2'},
];

/// While set, /sources waits for it (the loading state).
Completer<void>? _sourcesGate;

/// One Stream's answers to actions ({ok, message}), like its provider's call().
Map _act(String method) => switch (method) {
  'watchlist_add' => {'ok': true, 'message': 'Added to your watchlist'},
  'watchlist_remove' => {'ok': true, 'message': 'Removed from your watchlist'},
  'download' => {'ok': true, 'message': 'Download started'},
  'prepare' => {'ok': false, 'message': 'No peers right now — try another source'},
  _ => {'ok': true},
};

/// Answers One Stream's calls like its provider would; [log] gets every call.
Future<Object?>? _oneStream(MethodCall call, List<MethodCall> log, {bool available = true, bool watching = true}) {
  if (!call.method.startsWith('oneStream')) return null;
  log.add(call);
  final args = call.arguments is Map ? call.arguments as Map : const {};
  final params = args['params'] as Map? ?? const {};
  if (args['path'] == '/sources' && _sourcesGate != null) return _sourcesGate!.future.then((_) => _sources(params));
  return Future.value(switch (call.method) {
    'oneStreamAvailable' => available,
    'oneStreamOpen' => true,
    'oneStreamCall' => _act(args['method'] as String),
    _ => switch (args['path']) {
      '/details' => [_details(params)],
      '/episodes' => _episodes(params),
      '/sources' => _sources(params),
      '/downloads' => _dl,
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
    TvRemote.instance.status.value = TvStatus.idle;
    TvRemote.instance.power.value = null;
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

    // Tap → its sheet here in One Launcher (One Stream isn't opened).
    await tester.tap(find.bySemanticsLabel('Dune: Prophecy, 2024'));
    await tester.pumpAndSettle();
    expect(find.byType(OneStreamTitleSheet), findsOneWidget);
    expect(calls.where((c) => c.method == 'oneStreamOpen'), isEmpty);
    await tester.binding.handlePopRoute();
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
    await tester.pumpAndSettle();
    expect(find.byType(OneStreamTitleSheet), findsOneWidget, reason: 'its sheet (Resume first)');
    expect((calls.lastWhere((c) => c.method == 'oneStream' && (c.arguments as Map)['path'] == '/details').arguments as Map)['params'], {'type': 'tv', 'tmdb': 100});
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Large: a row each, tap one.
    await prefs.setTodayTiles([const TileSpec('today:stream', 'l').toJson()]);
    await tester.pumpAndSettle();
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('2016'), findsNothing);
    expect(find.text('29 min left'), findsOneWidget, reason: 'no episode: just what’s left');
    await tester.tap(find.text('Arrival').last);
    await tester.pumpAndSettle();
    expect(find.byType(OneStreamTitleSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

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
    expect(find.byType(TvOneStreamPage), findsOneWidget, reason: 'its page here, not One Stream');
    expect(calls.where((c) => c.method == 'oneStreamOpen'), isEmpty);
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
    // "More in One Stream": its page here (from /title's tmdb).
    await tester.tap(find.text('More in One Stream'));
    await settle(tester);
    expect(find.byType(TvOneStreamPage), findsOneWidget);
    expect((calls.firstWhere((c) => c.method == 'oneStream' && (c.arguments as Map)['path'] == '/details').arguments as Map)['params'], {'type': 'movie', 'tmdb': 693134});
    await tester.binding.handlePopRoute();
    await settle(tester);

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

  testWidgets('TV home: One Stream’s Continue watching joins the resume row (in the history’s place), OK opens its page', (tester) async {
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
    expect(find.byType(TvOneStreamPage), findsOneWidget, reason: 'its page (Resume first)');
    expect(find.text('Resume'), findsOneWidget, reason: 'started in One Stream');
  });

  // ---- Part 2: One Stream's title, inside One Launcher ----

  OneStreamTitle movie() => OneStreamTitle.fromMap(_found.first);
  OneStreamTitle series() => OneStreamTitle.fromMap(_found[1]);

  /// Opens the sheet on the home screen (the same call search and Today make).
  Future<void> sheet(WidgetTester tester, OneStreamTitle t, {bool loading = false}) async {
    showOneStreamTitle(tester.element(find.byType(Scaffold).first), t);
    if (!loading) {
      await tester.pumpAndSettle();
      return;
    }
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300)); // a spinner keeps going: no settling
    }
  }

  Map lastAct(String method) => Map.of(calls.lastWhere((c) => c.method == 'oneStreamCall' && (c.arguments as Map)['method'] == method).arguments as Map);

  testWidgets('phone sheet (film): story, Resume, watchlist live, sources → Play / Download, Prepare’s message, downloads', (tester) async {
    await phone(tester);
    await sheet(tester, movie());
    expect(find.text('Dune: Part Two'), findsWidgets);
    expect(find.text('2024 · 2 h 47 min · 8.5/10'), findsOneWidget);
    expect(find.text('Sci-Fi, Adventure'), findsOneWidget);
    expect(find.textContaining('Paul unites'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget, reason: 'started in One Stream');
    expect(find.text('2160p · Best'), findsOneWidget);
    expect(find.text('12.4 GB · 812 seeds · Torrentio'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/52_one_stream_sheet.png'));

    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(calls.last.arguments, {'link': 'onestream://resume/dune'});

    // Watchlist: toggles at once, One Stream's words under the buttons.
    await tester.tap(find.text('Watchlist'));
    await tester.pumpAndSettle();
    expect(lastAct('watchlist_add')['extras'], {'type': 'movie', 'tmdb': 693134});
    expect(find.text('In watchlist'), findsOneWidget);
    expect(find.text('Added to your watchlist'), findsOneWidget);
    await tester.tap(find.text('In watchlist'));
    await tester.pumpAndSettle();
    expect(lastAct('watchlist_remove')['extras'], {'type': 'movie', 'tmdb': 693134});
    expect(find.text('Watchlist'), findsOneWidget);

    // Download (the best downloadable source) and Prepare (its answer, even when it fails).
    await tester.tap(find.text('Download').first);
    await tester.pumpAndSettle();
    expect(lastAct('download')['extras'], {'token': 'tok-best'});
    expect(find.text('Download started'), findsOneWidget);
    await tester.tap(find.text('Prepare'));
    await tester.pumpAndSettle();
    expect(lastAct('prepare')['extras'], {'token': 'tok-best'});
    expect(find.text('No peers right now — try another source'), findsOneWidget);

    // A source → its menu → Play (its play link) / Download.
    await tester.scrollUntilVisible(find.text('1080p'), 120, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('1080p'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare to stream'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(calls.lastWhere((c) => c.method == 'oneStreamOpen').arguments, {'link': 'onestream://play?source=tok-1080&type=movie&tmdb=693134'});
    await tester.tap(find.text('720p'));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsOneWidget, reason: 'the sheet’s button only: this source can’t be downloaded');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // This title's download, with its progress.
    await tester.scrollUntilVisible(find.text('45% · 2.1 GB'), 120, scrollable: find.byType(Scrollable).last);
    expect(find.text('Downloads'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel download'));
    await tester.pumpAndSettle();
    expect(lastAct('cancel_download')['extras'], {'key': 'dl1'});
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('phone sheet (series): seasons, the episode in progress picked, its sources (loading → list), another episode', (tester) async {
    await phone(tester);
    _sourcesGate = Completer();
    addTearDown(() => _sourcesGate = null);
    await sheet(tester, series(), loading: true);
    expect(find.text('Season 2'), findsOneWidget);
    expect(find.text('Two Wolves'), findsOneWidget);
    expect(find.text('Play E2'), findsOneWidget, reason: 'the episode in the middle of watching');
    expect(find.text('Looking for sources… this can take a few seconds'), findsOneWidget);
    var asked = calls.lastWhere((c) => (c.arguments as Map?)?['path'] == '/sources').arguments as Map;
    expect(asked['params'], {'type': 'tv', 'tmdb': 1399, 'season': 1, 'episode': 2});
    expect(asked['timeoutMs'], 30000);
    // Play while it's still looking: waits for the best source, then plays it.
    await tester.tap(find.text('Play E2'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Finding the best source…'), findsOneWidget);
    _sourcesGate!.complete();
    await tester.pumpAndSettle();
    expect(calls.lastWhere((c) => c.method == 'oneStreamOpen').arguments, {'link': 'onestream://play?source=tok-best&type=tv&tmdb=1399&season=1&episode=2'});
    expect(find.text('Sources · S1 E2'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/53_one_stream_series.png'));

    _sourcesGate = null;
    await tester.tap(find.text('Sisterhood Above All'));
    await tester.pumpAndSettle();
    asked = calls.lastWhere((c) => (c.arguments as Map?)?['path'] == '/sources').arguments as Map;
    expect(asked['params'], {'type': 'tv', 'tmdb': 1399, 'season': 1, 'episode': 3});
    expect(find.text('Play E3'), findsOneWidget);
    await tester.tap(find.text('Season 2'));
    await tester.pumpAndSettle();
    expect((calls.lastWhere((c) => (c.arguments as Map?)?['path'] == '/episodes').arguments as Map)['params'], {'tmdb': 1399, 'season': 2});
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('phone sheet in the Tiles view speaks Metro (flat, lowercase); no sources → says so', (tester) async {
    await phone(tester, stored: {'homeView': 'tiles'});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'oneStream' && (call.arguments as Map)['path'] == '/sources') return const [];
      return _oneStream(call, calls);
    });
    await sheet(tester, movie());
    expect(find.text('resume'), findsOneWidget, reason: 'Metro: lowercase');
    expect(find.text('no sources found'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/54_one_stream_sheet_metro.png'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('Today: "Downloads" widget — progress and ready ones; tap a ready one plays it', (tester) async {
    final prefs = await phone(tester);
    await prefs.setTodayTiles([const TileSpec('today:downloads', 'w').toJson()]);
    await openToday(tester);
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('45% · 2.1 GB'), findsOneWidget);
    expect(find.text('Ready · 1.5 GB'), findsOneWidget);
    await tester.tap(find.text('Arrival'));
    await tester.pump();
    expect(calls.last.arguments, {'link': 'onestream://play?source=local-dl2'});
  });

  testWidgets('TV page (series): seasons, episodes, sources → panel → Download; watchlist; Metro-free look', (tester) async {
    await tv(tester);
    await tester.pumpWidget(tvApp(TvOneStreamPage(title: series())));
    await settle(tester);
    expect(find.text('SERIES · ONE STREAM'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    expect(find.text('E2 · Two Wolves'), findsOneWidget);
    expect(find.text('Play S1 E2'), findsOneWidget);
    expect(find.text('2160p · Best'), findsOneWidget);
    expect(find.text('Coming 2024-11-14'), findsOneWidget, reason: 'not out yet');
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_17_one_stream_page.png'));
    // OK on a source → the side panel → Download.
    await tester.ensureVisible(find.text('1080p'));
    await settle(tester);
    await tester.tap(find.text('1080p'));
    await settle(tester);
    await tester.tap(find.text('Download').last);
    await settle(tester);
    expect(lastAct('download')['extras'], {'token': 'tok-1080'});
    expect(find.text('Download started'), findsOneWidget);
    await tester.tap(find.text('Add to watchlist'));
    await settle(tester);
    expect(find.text('In watchlist'), findsOneWidget);
    expect(lastAct('watchlist_add')['extras'], {'type': 'tv', 'tmdb': 1399});
    // Play (with the remote: it starts focused).
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);
    await tester.tap(find.text('Play S1 E2'));
    await settle(tester);
    expect(calls.lastWhere((c) => c.method == 'oneStreamOpen').arguments, {'link': 'onestream://play?source=tok-best&type=tv&tmdb=1399&season=1&episode=2'});
  });

  // ---- Part 3: play / download it on the paired TV (the phone remote) ----

  const tvPrefs = <String, Object>{'tvHost': '192.168.1.40', 'tvName': 'Kame TV'};

  /// The TV's side of the remote channel: [reachable] answers tvConnect (then says it's
  /// connected and whether its screen is on: [screenOn]); links and keys go through.
  void tvAnswers(WidgetTester tester, {required bool Function() reachable, bool? Function()? screenOn, bool wakes = true}) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (_oneStream(call, calls) case final r?) return r;
      calls.add(call);
      switch (call.method) {
        case 'tvConnect':
          if (!reachable()) throw PlatformException(code: 'tv', message: 'Connection refused');
          TvRemote.instance.onEvent({'state': 'connected'});
          if (screenOn?.call() case final on?) TvRemote.instance.onEvent({'state': 'power', 'on': on});
          return true;
        case 'tvKey':
          // The wake key turns a sleeping TV's screen on (if it [wakes]).
          if (wakes && (call.arguments as Map)['code'] == TvKey.wakeup) TvRemote.instance.onEvent({'state': 'power', 'on': true});
          return true;
        case 'tvAppLink':
          return true;
      }
      return null;
    });
  }

  List<String> links() => [for (final c in calls.where((c) => c.method == 'tvAppLink')) (c.arguments as Map)['link'] as String];

  testWidgets('phone sheet: no TV paired → no "On TV" buttons, none in a source’s menu', (tester) async {
    await phone(tester);
    await sheet(tester, movie());
    expect(find.byKey(const ValueKey('on-tv')), findsNothing);
    expect(find.text('Play on TV'), findsNothing);
    await tester.scrollUntilVisible(find.text('1080p'), 120, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('1080p'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare to stream'), findsOneWidget);
    expect(find.text('Play on TV'), findsNothing);
    expect(find.text('Download on TV'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('phone sheet (film), TV paired: "On Kame TV" → Play / Download on TV send cast links with the source hint', (tester) async {
    await phone(tester, stored: tvPrefs);
    tvAnswers(tester, reachable: () => true, screenOn: () => true);
    await sheet(tester, movie());
    expect(find.text('On Kame TV'), findsOneWidget);
    expect(find.text('Play on TV'), findsOneWidget);
    expect(find.text('Download on TV'), findsOneWidget);

    await tester.tap(find.text('Play on TV'));
    await tester.pumpAndSettle();
    expect(calls.firstWhere((c) => c.method == 'tvConnect').arguments, {'host': '192.168.1.40'});
    expect(links().last, 'onestream://cast/play?type=movie&tmdb=693134&hash=a1b2c3&file=2', reason: 'the best source as the hint');
    expect((calls.lastWhere((c) => c.method == 'tvKey').arguments as Map)['code'], TvKey.wakeup, reason: 'the wake key always goes first (never power)');
    expect(find.text('Playing on Kame TV'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/55_one_stream_on_tv.png'));

    // Already connected: no second connect.
    await tester.tap(find.text('Download on TV'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'tvConnect').length, 1);
    expect(links().last, 'onestream://cast/download?type=movie&tmdb=693134&hash=a1b2c3&file=2');
    expect(find.text('Downloading on Kame TV'), findsOneWidget);

    // A source's menu: its own hint — a direct link, encoded; it can't be downloaded.
    await tester.scrollUntilVisible(find.text('720p'), 120, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('720p'));
    await tester.pumpAndSettle();
    expect(find.text('Download on TV'), findsOneWidget, reason: 'the sheet’s button only');
    await tester.tap(find.text('Play on TV').last);
    await tester.pumpAndSettle();
    expect(links().last, 'onestream://cast/play?type=movie&tmdb=693134&url=https%3A%2F%2Fcdn.example%2Fdune+720.m3u8%3Fa%3D1%26b%3D2');
    // A torrent with no hint from One Stream: just the title.
    await tester.tap(find.text('1080p'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download on TV').last);
    await tester.pumpAndSettle();
    expect(links().last, 'onestream://cast/download?type=movie&tmdb=693134');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('phone sheet (series), TV asleep: wakes it, then plays the picked episode on it; Metro', (tester) async {
    await phone(tester, stored: {...tvPrefs, 'homeView': 'tiles'});
    tvAnswers(tester, reachable: () => true, screenOn: () => false);
    await sheet(tester, series());
    expect(find.text('on kame tv'), findsOneWidget, reason: 'Metro: lowercase');
    await tester.tap(find.byKey(const ValueKey('tv-play')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('sending to kame tv…'), findsOneWidget);
    expect((calls.lastWhere((c) => c.method == 'tvKey').arguments as Map)['code'], TvKey.wakeup, reason: 'the wake key, never power');
    expect(links(), isEmpty, reason: 'the TV gets time to wake and settle');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(links().single, 'onestream://cast/play?type=tv&tmdb=1399&season=1&episode=2&hash=a1b2c3&file=2');
    expect(find.text('playing on kame tv'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/56_one_stream_on_tv_metro.png'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('phone sheet, TV off / away: "Couldn’t reach Kame TV — is it on?" with Retry, which sends it', (tester) async {
    await phone(tester, stored: tvPrefs);
    var reachable = false;
    tvAnswers(tester, reachable: () => reachable, wakes: false);
    await sheet(tester, movie());
    await tester.tap(find.text('Download on TV'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t reach Kame TV — is it on?'), findsOneWidget);
    expect(links(), isEmpty);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/57_one_stream_on_tv_failed.png'));
    reachable = true; // power never reported (standby): wake anyway, wait, wake again, then send
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(seconds: 2));
    expect(links(), isEmpty, reason: 'still waking');
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(links().single, 'onestream://cast/download?type=movie&tmdb=693134&hash=a1b2c3&file=2');
    expect(calls.where((c) => c.method == 'tvKey' && (c.arguments as Map)['code'] == TvKey.wakeup).length, 2, reason: 'woke twice');
    expect(find.text('Downloading on Kame TV'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  test('cast link: encodes every value; drops a phone-only (local) url; no file without a hash', () {
    final t = OneStreamTitle.fromMap(const {'type': 'tv', 'tmdb': 7, 'title': 'X'});
    final local = OneStreamSource(const {'token': 't', 'url': 'http://127.0.0.1:8080/stream/1', 'file': 3});
    expect(TvCast.link('play', t, season: 1, episode: 10, source: local), 'onestream://cast/play?type=tv&tmdb=7&season=1&episode=10');
    final odd = OneStreamSource(const {'token': 't', 'hash': 'a b&c', 'file': 0});
    expect(TvCast.link('download', t, source: odd), 'onestream://cast/download?type=tv&tmdb=7&hash=a+b%26c&file=0');
  });
}
