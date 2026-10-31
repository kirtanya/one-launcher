import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/tv/catalog.dart';
import 'package:one_launcher/tv/tv_apps.dart';
import 'package:one_launcher/tv/tv_ds.dart';
import 'package:one_launcher/tv/tv_settings.dart';
import 'package:one_launcher/ui/ds.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
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

ShowTitle _t(String id, String title, {String type = 'movie', int pop = 0, double? rating, String? year}) =>
    ShowTitle(id: id, type: type, title: title, popularity: pop, rating: rating, year: year);

List<String> _names(List<ShowTitle> l) => [for (final t in l) t.title];

/// A Cinemeta-like manifest: Popular (search, skip), New (needs a year), Last videos (special).
const _cinemeta = {
  'id': 'com.linvo.cinemeta',
  'name': 'Cinemeta',
  'resources': ['catalog', 'meta', 'addon_catalog'],
  'types': ['movie', 'series'],
  'idPrefixes': ['tt'],
  'catalogs': [
    {
      'type': 'movie',
      'id': 'top',
      'name': 'Popular',
      'extra': [
        {'name': 'genre'},
        {'name': 'search'},
        {'name': 'skip'},
      ],
    },
    {
      'type': 'movie',
      'id': 'year',
      'name': 'New',
      'extra': [
        {'name': 'genre', 'isRequired': true},
        {'name': 'skip'},
      ],
    },
    {
      'type': 'series',
      'id': 'last-videos',
      'extra': [
        {'name': 'lastVideosIds', 'isRequired': true},
      ],
    },
  ],
};

/// An addon like the user's big one: "skip" required, its own search catalog, a TV-channel catalog,
/// and a stream resource (never used).
const _bigAddon = {
  'id': 'some.big.addon',
  'name': 'Big Addon',
  'resources': [
    'catalog',
    'meta',
    {
      'name': 'stream',
      'types': ['movie', 'series'],
    },
  ],
  'types': ['movie', 'series', 'tv'],
  'idPrefixes': ['tt', 'tmdb'],
  'catalogs': [
    {
      'type': 'movie',
      'id': 'netflix_movies',
      'name': 'Netflix',
      'extra': [
        {'name': 'skip', 'isRequired': true},
      ],
    },
    {
      'type': 'series',
      'id': 'search_series',
      'extra': [
        {'name': 'search', 'isRequired': true},
      ],
    },
    {'type': 'tv', 'id': 'sports'},
  ],
};

void main() {
  group('Sources', () {
    test('parsing: comments, blank lines, inline comments, duplicates, install links', () {
      const file = '''
# My addons
https://v3-cinemeta.strem.io/manifest.json

   https://example.com/abc123/manifest.json   # personal one
# https://commented.out/manifest.json
https://v3-cinemeta.strem.io/manifest.json\r
stremio://watchhub.strem.io/manifest.json
https://no-suffix.example.com/addon/
not a link
''';
      expect(parseSources(file), [
        'https://v3-cinemeta.strem.io/manifest.json',
        'https://example.com/abc123/manifest.json',
        'https://watchhub.strem.io/manifest.json',
        'https://no-suffix.example.com/addon/manifest.json',
      ]);
      // The build passes them space-separated (tool/build_tv.sh).
      expect(parseSources('https://a.example/manifest.json https://b.example/manifest.json'), [
        'https://a.example/manifest.json',
        'https://b.example/manifest.json',
      ]);
      expect(parseSources(''), isEmpty);
      expect(normaliseSource('ftp://x.example/manifest.json'), isNull);
    });

    test('a build adds its new links; ones the user removed stay removed', () {
      // First run: the build's list.
      var (list, seen) = mergeBuildSources(current: null, seen: const [], build: const ['a', 'b']);
      expect(list, ['a', 'b']);
      expect(seen, ['a', 'b']);
      // The user removes b and adds c; the same build again changes nothing.
      (list, seen) = mergeBuildSources(current: const ['a', 'c'], seen: seen, build: const ['a', 'b']);
      expect(list, ['a', 'c']);
      // A later build brings d: added at the end, b still gone.
      (list, seen) = mergeBuildSources(current: list, seen: seen, build: const ['a', 'b', 'd']);
      expect(list, ['a', 'c', 'd']);
      expect(seen, ['a', 'b', 'd']);
    });
  });

  group('Addons', () {
    test('which catalogs an update reads and which answer a search', () {
      final cinemeta = Addon.fromJson('https://v3-cinemeta.strem.io/manifest.json', _cinemeta)!;
      expect(cinemeta.isCinemeta, isTrue);
      expect([for (final c in cinemeta.browsable) c.id], ['top'], reason: 'New needs a year; Last videos needs ids');
      expect([for (final c in cinemeta.searchable) c.id], ['top']);
      final top = cinemeta.catalogs.first;
      expect(cinemeta.catalogUrl(top), 'https://v3-cinemeta.strem.io/catalog/movie/top.json');
      expect(cinemeta.catalogUrl(top, skip: 48), 'https://v3-cinemeta.strem.io/catalog/movie/top/skip=48.json');
      expect(cinemeta.catalogUrl(top, search: 'breaking bad'), 'https://v3-cinemeta.strem.io/catalog/movie/top/search=breaking%20bad.json');
      expect(cinemeta.metaUrl('movie', 'tt0816692'), 'https://v3-cinemeta.strem.io/meta/movie/tt0816692.json');

      final big = Addon.fromJson('https://big.example/token/manifest.json', _bigAddon)!;
      expect([for (final c in big.browsable) c.id], ['netflix_movies'], reason: '"skip" required is fine; TV channels aren’t films');
      expect([for (final c in big.searchable) c.id], ['search_series']);
      expect(big.catalogUrl(big.catalogs.first), 'https://big.example/token/catalog/movie/netflix_movies/skip=0.json');
      expect(big.catalogs.first.service, 'Netflix');
      expect(big.provides('meta', 'movie', 'tt123'), isTrue);
      expect(big.provides('stream', 'movie', 'tt123'), isTrue);
      expect(big.provides('meta', 'movie', 'kitsu:1'), isFalse);
    });

    test('safety: only WatchHub is ever asked for "stream" links', () {
      final big = Addon.fromJson('https://big.example/token/manifest.json', _bigAddon)!;
      expect(big.watchLinksUrl('movie', 'tt0816692'), isNull, reason: 'another addon’s streams: never');
      final hub = Addon.fromJson(Catalog.watchHubUrl, const {
        'id': 'org.stremio.watchhub',
        'name': 'WatchHub',
        'resources': ['stream'],
        'types': ['movie', 'series'],
        'idPrefixes': ['tt'],
        'catalogs': [],
      })!;
      expect(hub.isWatchHub, isTrue);
      expect(hub.watchLinksUrl('series', 'tt4574334:1:1'), 'https://watchhub.strem.io/stream/series/tt4574334%3A1%3A1.json');
    });

    test('safety: an addon copying WatchHub’s id on another host is not WatchHub', () {
      final fake = Addon.fromJson('https://other.example/manifest.json', const {
        'id': 'org.stremio.watchhub',
        'name': 'WatchHub',
        'resources': ['stream'],
        'types': ['movie', 'series'],
        'idPrefixes': ['tt'],
        'catalogs': [],
      })!;
      expect(fake.isWatchHub, isFalse);
      expect(fake.watchLinksUrl('movie', 'tt0816692'), isNull);
    });
  });

  group('Catalog pages', () {
    test('IMDb ids only; year, rating, genres, a short plot; popularity by place', () {
      final body = jsonEncode({
        'metas': [
          {
            'id': 'tt0816692',
            'type': 'movie',
            'name': 'Interstellar',
            'releaseInfo': '2014',
            'imdbRating': '8.7',
            'genres': ['Adventure', 'Sci-Fi'],
            'description': 'x' * 400,
            'poster': 'https://images.metahub.space/poster/small/tt0816692/img',
          },
          {'id': 'tmdb:157336', 'type': 'movie', 'name': 'Not an IMDb id'},
          {'id': 'kitsu:1', 'imdb_id': 'tt9140554', 'type': 'series', 'name': 'Loki', 'year': '2021–2023', 'poster': 'https://image.tmdb.org/t/p/w500/x.jpg'},
          {'id': 'tt1234567', 'name': 'No type: the catalog’s', 'released': '2020-01-01'},
          {'id': 'tt7654321', 'type': 'movie'},
        ],
      });
      final page = parseCatalogPage(body, type: 'movie', offset: 50, service: 'Netflix');
      expect(page.count, 5, reason: 'the next page skips every entry, kept or not');
      expect(_names(page.titles), ['Interstellar', 'Loki', 'No type: the catalog’s']);
      final i = page.titles.first;
      expect((i.year, i.rating), ('2014', 8.7));
      expect(i.genres, ['Adventure', 'Sci-Fi']);
      expect(i.services, ['Netflix']);
      expect(i.overview!.length, lessThanOrEqualTo(220));
      expect(i.popularity, hitScore(50));
      expect(i.posters, ['https://images.metahub.space/poster/medium/tt0816692/img'], reason: 'metahub: one standard link');
      final loki = page.titles[1];
      expect((loki.id, loki.type, loki.year), ('tt9140554', 'series', '2021–2023'));
      expect(loki.posters.last, 'https://image.tmdb.org/t/p/w500/x.jpg', reason: 'the source’s own art is the second choice');
      expect(page.titles[2].type, 'movie');
    });

    test('merge: one entry per title, details filled in, popularity added up, most popular first', () {
      final merged = mergeTitles([
        ShowTitle(id: 'tt1', type: 'movie', title: 'Alpha', popularity: 50, services: const ['Netflix']),
        ShowTitle(id: 'tt2', type: 'movie', title: 'Beta', popularity: 120, rating: 7),
        ShowTitle(id: 'tt1', type: 'movie', title: 'Alpha', year: '2020', rating: 8.1, popularity: 100, services: const ['Prime Video']),
        ShowTitle(id: 'tt3', type: 'series', title: 'Gamma', popularity: 150, rating: 6),
        ShowTitle(id: 'tt4', type: 'series', title: 'Delta', popularity: 150, rating: 9),
      ]);
      expect(_names(merged), ['Delta', 'Alpha', 'Gamma', 'Beta'], reason: '150 (9.0), 50+100 (8.1), 150 (6.0), 120');
      final alpha = merged[1];
      expect((alpha.popularity, alpha.year, alpha.rating), (150, '2020', 8.1));
      expect(alpha.services, ['Netflix', 'Prime Video']);
      expect(mergeTitles(merged, limit: 2).length, 2);
    });

    test('saved and read back', () {
      final file = CatalogFile(
        titles: [
          ShowTitle(id: 'tt1', type: 'series', title: 'Alpha', year: '2020', rating: 8.1, popularity: 7, services: const ['Netflix'], live: true),
        ],
        updated: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        sources: const ['https://v3-cinemeta.strem.io/manifest.json'],
        addons: [Addon.fromJson('https://v3-cinemeta.strem.io/manifest.json', _cinemeta)!],
      );
      final back = CatalogFile.decode(file.encode())!;
      final t = back.titles.single;
      expect((t.id, t.type, t.title, t.year, t.rating, t.popularity, t.live), ('tt1', 'series', 'Alpha', '2020', 8.1, 7, true));
      expect(t.services, ['Netflix']);
      expect(back.updated, file.updated);
      expect(back.addons.single.name, 'Cinemeta');
      expect(back.sources, file.sources);
    });
  });

  group('Search', () {
    final titles = [
      _t('tt1', 'The Dark Knight', pop: 900, rating: 9.0),
      _t('tt2', 'Dark', type: 'series', pop: 300, rating: 8.7),
      _t('tt3', 'Dark Matter', type: 'series', pop: 200),
      _t('tt4', 'Darkest Hour', pop: 250),
      _t('tt5', 'Knight and Day', pop: 100),
      _t('tt6', 'Amélie', pop: 80),
      _t('tt7', 'Spider-Man: Across the Spider-Verse', pop: 500),
      _t('tt8', "Schindler's List", pop: 400),
      _t('tt9', 'Into the Darkness', pop: 50),
      _t('tt10', 'Knight Moves', pop: 10),
    ];

    test('title > starts with > a word starts with > every word > anywhere; ties by popularity', () {
      expect(_names(searchTitles(titles, 'dark')), ['Dark', 'Darkest Hour', 'Dark Matter', 'The Dark Knight', 'Into the Darkness']);
      expect(_names(searchTitles(titles, 'knight dark')), ['The Dark Knight'], reason: 'every word, any order');
      expect(_names(searchTitles(titles, 'ark')), [
        'The Dark Knight',
        'Dark',
        'Darkest Hour',
        'Dark Matter',
        'Into the Darkness',
      ], reason: 'anywhere: by popularity');
      expect(_names(searchTitles(titles, 'knight')).take(2), ['Knight and Day', 'Knight Moves'], reason: 'starts-with beats the more popular word match');
    });

    test('case, accents and punctuation don’t matter', () {
      expect(_names(searchTitles(titles, 'AMELIE')), ['Amélie']);
      expect(_names(searchTitles(titles, 'schindlers')), ["Schindler's List"]);
      expect(_names(searchTitles(titles, 'spiderman')), ['Spider-Man: Across the Spider-Verse']);
      expect(_names(searchTitles(titles, 'spider verse')), ['Spider-Man: Across the Spider-Verse']);
      expect(searchTitles(titles, '  '), isEmpty);
      expect(foldTitle('Amélie: Part II!'), 'amelie part ii');
    });

    test('live results join without repeats; their own fuzzy finds go last', () {
      final local = searchTitles(titles, 'dark');
      final live = [_t('tt2', 'Dark', type: 'series'), _t('tt99', 'Dark Waters', pop: 5), _t('tt98', 'Dirk Gently', pop: 5)];
      final all = combineResults('dark', local, live);
      expect(all.where((t) => t.id == 'tt2').length, 1);
      expect(all.map((t) => t.title), containsAllInOrder(['Dark', 'Dark Matter', 'Dark Waters', 'The Dark Knight']));
      expect(all.last.title, 'Dirk Gently');
    });
  });

  group('Auto-update', () {
    final now = DateTime(2026, 10, 15, 12);
    test('daily, weekly, off; never updated; sources changed; clock went back', () {
      expect(isStale(updated: null, now: now, mode: 'daily'), isTrue);
      expect(isStale(updated: now.subtract(const Duration(hours: 23)), now: now, mode: 'daily'), isFalse);
      expect(isStale(updated: now.subtract(const Duration(hours: 24)), now: now, mode: 'daily'), isTrue);
      expect(isStale(updated: now.subtract(const Duration(days: 3)), now: now, mode: 'weekly'), isFalse);
      expect(isStale(updated: now.subtract(const Duration(days: 7)), now: now, mode: 'weekly'), isTrue);
      expect(isStale(updated: now.subtract(const Duration(days: 30)), now: now, mode: 'off'), isFalse);
      expect(isStale(updated: null, now: now, mode: 'off'), isFalse);
      expect(isStale(updated: now, now: now, mode: 'daily', sourcesChanged: true), isTrue);
      expect(isStale(updated: now.add(const Duration(hours: 2)), now: now, mode: 'daily'), isTrue);
      expect(agoLabel(now.subtract(const Duration(hours: 3)), now), '3 h ago');
      expect(agoLabel(null, now), 'Never');
    });
  });

  group('A title’s page', () {
    test('details: runtime, seasons, cast + director, trailer', () {
      final base = _t('tt0816692', 'Interstellar', pop: 300);
      final meta = {
        'meta': {
          'name': 'Interstellar',
          'description': 'A team of explorers travel through a wormhole.',
          'releaseInfo': '2014',
          'imdbRating': '8.7',
          'runtime': '2h 49min',
          'genres': ['Adventure', 'Drama', 'Sci-Fi'],
          'cast': ['Matthew McConaughey', 'Anne Hathaway'],
          'director': ['Christopher Nolan'],
          'trailers': [
            {'source': 'zSWdZVtXT7E', 'type': 'Trailer'},
          ],
        },
      };
      final d = detailsFromMeta(meta, base, 'Cinemeta')!;
      expect((d.runtime, d.title.rating, d.title.year, d.source, d.trailer), (169, 8.7, '2014', 'Cinemeta', 'zSWdZVtXT7E'));
      expect(d.title.popularity, 300, reason: 'keeps the catalog’s popularity');
      expect(
        [for (final p in d.cast) '${p.name}${p.role == null ? '' : ' (${p.role})'}'],
        ['Matthew McConaughey', 'Anne Hathaway', 'Christopher Nolan (Director)'],
      );
      final show = detailsFromMeta(
        {
          'meta': {
            'name': 'Loki',
            'status': 'Ended',
            'runtime': '49 min',
            'videos': [
              {'season': 0, 'episode': 1},
              {'season': 1, 'episode': 1},
              {'season': 1, 'episode': 2},
              {'season': 2, 'episode': 1},
            ],
            'trailerStreams': [
              {'ytId': 'nW948Va-l10'},
            ],
          },
        },
        _t('tt9140554', 'Loki', type: 'series'),
        'Cinemeta',
      )!;
      expect((show.seasons, show.runtime, show.status, show.trailer), (2, null, 'Ended', 'nW948Va-l10'), reason: 'specials aren’t a season');
      expect(parseRuntime('169 min'), 169);
      expect(detailsFromMeta({'nope': 1}, base, 'Cinemeta'), isNull);
    });

    test('where to watch: official app links only (WatchHub)', () {
      final links = parseWatchLinks({
        'streams': [
          {
            'name': 'Netflix',
            'title': 'Subscription',
            'externalUrl': 'https://www.netflix.com/title/80057281',
            'androidTvUrl': 'intent://www.netflix.com/watch/80057281#Intent;launchFlags=0x00800000;scheme=https;package=com.netflix.ninja;S.source=30;end',
          },
          {
            'name': 'YouTube',
            'title': 'Rent, Buy',
            'externalUrl': 'https://www.youtube.com/results?search_query=x',
            'androidTvUrl': 'intent://www.youtube.com/results#Intent;scheme=https;',
          },
          {'name': 'Torrent', 'infoHash': 'abc', 'externalUrl': 'https://x.example'},
          {'name': 'Magnet', 'externalUrl': 'magnet:?xt=urn:btih:abc'},
          {'name': 'File', 'url': 'https://cdn.example/movie.mp4'},
        ],
      });
      expect([for (final l in links) l.service], ['Netflix', 'YouTube']);
      expect((links.first.package, links.first.kind), ('com.netflix.ninja', 'Subscription'));
      expect(links.last.package, isNull);
      expect(
        packageOfIntent('intent://app.primevideo.com/watch#Intent;package=com.amazon.amazonvideo.livingroom;scheme=https;end'),
        'com.amazon.amazonvideo.livingroom',
      );
      expect(Catalog.detailLink(_t('tt0816692', 'Interstellar')), 'stremio:///detail/movie/tt0816692');
    });
  });

  testWidgets('TV: Customise → Search: update now, last updated, titles, sources (on/off, add)', (tester) async {
    await _loadFonts();
    TvApps.demo = true;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2; // 960×540, a 1080p TV
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    await Catalog.instance.start(prefs);
    expect(prefs.catalogSources, Catalog.publicSources, reason: 'no sources file in tests: the public ones');

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, fontFamily: DS.font),
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: TvDS.canvas,
            body: Center(
              child: TextButton(
                onPressed: () => showTvCustomise(context, prefs: prefs, extras: const {}),
                child: const Text('Customise'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Customise'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Search'), 120, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    for (final row in ['Update catalog now', 'Last updated', 'Just now', 'Titles in catalog', '4', 'Sources', '2 of 2 on', 'Auto-update', 'Daily']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    await tester.tap(find.text('Auto-update'));
    await tester.pumpAndSettle();
    expect(prefs.tvSettings['catalogAuto'], 'weekly');
    expect(find.text('Weekly'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_13_search_settings.png'));

    // Sources: each addon and what it gives; switch WatchHub off.
    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();
    expect(find.text('Cinemeta'), findsOneWidget);
    expect(find.text('Catalogs · Details'), findsOneWidget);
    expect(find.text('Where to watch'), findsOneWidget);
    await tester.tap(find.text('WatchHub'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch off'));
    await tester.pumpAndSettle();
    expect(prefs.catalogSourcesOff, [Catalog.watchHubUrl]);
    expect(find.text('Off'), findsOneWidget, reason: 'back on Sources: WatchHub is off');
    expect(Catalog.instance.watchSourceName, isNull);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_14_sources.png'));

    // Add a source: a wrong link is explained; a manifest link is checked and joins the list.
    await tester.tap(find.text('Add a source'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not a link');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('That isn’t a link'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'stremio://addon.example/abc/manifest.json');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Demo addon'), findsOneWidget, reason: 'back on Sources, with the new one');
    expect(prefs.catalogSources!.last, 'https://addon.example/abc/manifest.json');
    await Catalog.instance.resetSources();
    await tester.pumpAndSettle();
    expect(prefs.catalogSources, Catalog.publicSources);
    expect(prefs.catalogSourcesOff, isEmpty);
  });
}
