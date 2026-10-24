import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/tv/catalog.dart';
import 'package:one_launcher/tv/ratings.dart';
import 'package:one_launcher/tv/tv_apps.dart';
import 'package:one_launcher/tv/tv_parts.dart';
import 'package:one_launcher/tv/tv_ratings.dart';
import 'package:one_launcher/tv/tv_title.dart';
import 'package:one_launcher/ui/ds.dart';

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

Future<void> _tv(WidgetTester tester) async {
  await _loadFonts();
  TvApps.demo = true;
  TitleExtras.instance.debugReset();
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(brightness: Brightness.dark, fontFamily: DS.font),
  home: home,
);

Widget _page(ShowTitle t) => _app(TvTitlePage(key: ValueKey(t.id), title: t, apps: const [], searchTargets: const [], onOpenApp: (_) {}));

// The backdrop eases in over 2.2 s: fixed pumps rather than settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyEvent(k);
  await _settle(tester);
}

ShowTitle _demo(String title) => demoTitles().firstWhere((t) => t.title == title);

T? _focusedOf<T extends Widget>() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<T>();

void main() {
  group('OMDb', () {
    test('a film: IMDb, Rotten Tomatoes and Metacritic', () {
      final r = ratingsFromOmdb({
        'Title': 'Inception',
        'imdbRating': '8.8',
        'Metascore': '74',
        'Ratings': [
          {'Source': 'Internet Movie Database', 'Value': '8.8/10'},
          {'Source': 'Rotten Tomatoes', 'Value': '87%'},
          {'Source': 'Metacritic', 'Value': '74/100'},
        ],
        'Response': 'True',
      })!;
      expect((r.imdb, r.rottenTomatoes, r.metascore, r.fresh), (8.8, 87, 74, true));
    });

    test('a series: IMDb only ("N/A" elsewhere); not found: empty; not OMDb: null', () {
      final r = ratingsFromOmdb({
        'imdbRating': '8.3',
        'Metascore': 'N/A',
        'Ratings': [
          {'Source': 'Internet Movie Database', 'Value': '8.3/10'},
        ],
        'Response': 'True',
      })!;
      expect((r.imdb, r.rottenTomatoes, r.metascore), (8.3, null, null));
      expect(ratingsFromOmdb({'Response': 'False', 'Error': 'Incorrect IMDb ID.'})!.isEmpty, isTrue);
      expect(ratingsFromOmdb({'imdbRating': 'N/A', 'Response': 'True'})!.imdb, isNull);
      expect(ratingsFromOmdb('nope'), isNull);
      // Metascore without the Ratings entry still counts.
      expect(ratingsFromOmdb({'Metascore': '55', 'Response': 'True'})!.metascore, 55);
    });

    test('Fresh from 60 %, Rotten below; Metascore colours 61+ / 40–60 / below 40', () {
      expect(const TitleRatings(rottenTomatoes: 60).fresh, isTrue);
      expect(const TitleRatings(rottenTomatoes: 59).fresh, isFalse);
      expect(const TitleRatings().fresh, isFalse);
      const green = Color(0xFF66CC33), yellow = Color(0xFFFFCC33), red = Color(0xFFFF0000);
      expect(
        [
          for (final s in [100, 61, 60, 40, 39, 0]) metascoreColour(s),
        ],
        [green, green, yellow, yellow, red, red],
      );
    });

    test('kept as JSON and read back', () {
      const r = TitleRatings(imdb: 7.4, rottenTomatoes: 42, metascore: 38);
      final back = TitleRatings.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map);
      expect((back.imdb, back.rottenTomatoes, back.metascore), (7.4, 42, 38));
    });
  });

  group('TMDB', () {
    test('find: the film, or the series; the other kind when only that matched', () {
      final j = {
        'movie_results': [
          {'id': 27205},
        ],
        'tv_results': <Object>[],
      };
      expect(tmdbIdFromFind(j, tv: false), 27205);
      expect(tmdbIdFromFind(j, tv: true), 27205, reason: 'only a film matched');
      expect(
        tmdbIdFromFind({
          'movie_results': <Object>[],
          'tv_results': [
            {'id': 1399},
          ],
        }, tv: true),
        1399,
      );
      expect(tmdbIdFromFind({'movie_results': <Object>[], 'tv_results': <Object>[]}, tv: false), isNull);
    });

    test('reviews: author, score (may be missing), date; markdown / HTML out; total', () {
      final r = reviewsFromTmdb({
        'id': 27205,
        'page': 1,
        'results': [
          {
            'author': 'John Chard',
            'author_details': {'name': '', 'username': 'John Chard', 'rating': 9.0},
            'content': '**Your mind is the scene of the crime.**<br/><br/>A _maze_ of a film &amp; a [score](https://example.com) that won&#39;t let go.',
            'created_at': '2021-06-23T15:58:44.512Z',
          },
          {
            'author': '',
            'author_details': {'name': '', 'username': 'msbreviews', 'rating': null},
            'content': '<p>Rare.</p><p>Ambitious &mdash; and coherent.</p>',
            'created_at': 'bad date',
          },
          {
            'author': 'Empty',
            'author_details': {'rating': 0},
            'content': '   ',
          },
        ],
        'total_results': 14,
      });
      expect(r.total, 14);
      expect([for (final x in r.list) x.author], ['John Chard', 'msbreviews'], reason: 'an empty review is left out; username when no author');
      expect(r.list.first.text, 'Your mind is the scene of the crime.\n\nA maze of a film & a score that won\'t let go.');
      expect(r.list.first.rating, 9);
      expect(r.list.first.created, DateTime.utc(2021, 6, 23, 15, 58, 44, 512));
      expect(r.list.last.text, 'Rare.\n\nAmbitious — and coherent.');
      expect((r.list.last.rating, r.list.last.created), (null, null));
      expect(reviewsFromTmdb('nope').list, isEmpty);
    });

    test('plain text: headings, quotes, lists of links, entities, extra blank lines', () {
      expect(plainText('# Verdict\n\n> A *great* film\n\n\n\n![poster](x.jpg)\n---\n`8/10` &hellip;'), 'Verdict\n\nA great film\n\n8/10 …');
      expect(plainText('snake_case_words and 2*3*4 stay'), 'snake_case_words and 2*3*4 stay');
      expect(plainText('<i>Dune</i>&nbsp;&#x2014; part&nbsp;two'), 'Dune — part two');
    });

    test('kept as JSON and read back', () {
      final r = ShowReviews([ShowReview(author: 'A', text: 'B', rating: 7, created: DateTime.utc(2024, 1, 2))], 3);
      final back = ShowReviews.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map);
      expect(
        (back.total, back.list.single.author, back.list.single.text, back.list.single.rating, back.list.single.created),
        (3, 'A', 'B', 7.0, DateTime.utc(2024, 1, 2)),
      );
    });
  });

  group('Asking and keeping', () {
    late Directory dir;
    late List<MethodCall> calls;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('extras');
      calls = [];
      TvApps.demo = false;
      TitleExtras.debugOmdbKey = 'omdb-test';
      TitleExtras.debugTmdbToken = 'tmdb-test';
      TitleExtras.instance.debugReset();
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/tv'), (call) async {
        calls.add(call);
        if (call.method == 'filesDir') return dir.path;
        if (call.method != 'httpGet') return null;
        final url = (call.arguments as Map)['url'] as String;
        if (url.startsWith('https://www.omdbapi.com/')) {
          return {
            'status': 200,
            'body': jsonEncode({
              'imdbRating': '8.8',
              'Ratings': [
                {'Source': 'Rotten Tomatoes', 'Value': '87%'},
                {'Source': 'Metacritic', 'Value': '74/100'},
              ],
              'Response': 'True',
            }),
          };
        }
        if (url.contains('/find/')) {
          return {
            'status': 200,
            'body': jsonEncode({
              'movie_results': [
                {'id': 27205},
              ],
            }),
          };
        }
        if (url.endsWith('/movie/27205/reviews')) {
          return {
            'status': 200,
            'body': jsonEncode({
              'results': [
                {
                  'author': 'A',
                  'content': 'Good.',
                  'author_details': {'rating': 8},
                },
              ],
              'total_results': 1,
            }),
          };
        }
        return {'status': 404, 'body': ''};
      });
    });

    tearDown(() {
      TvApps.demo = true;
      TitleExtras.debugOmdbKey = TitleExtras.debugTmdbToken = null;
      TitleExtras.instance.debugReset();
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/tv'), null);
      dir.deleteSync(recursive: true);
    });

    final inception = ShowTitle(id: 'tt1375666', type: 'movie', title: 'Inception');
    List<String> urls() => [for (final c in calls.where((c) => c.method == 'httpGet')) (c.arguments as Map)['url'] as String];

    test('once per title; kept on the TV for a week (asked again after)', () async {
      final r = (await TitleExtras.instance.ratings(inception))!;
      final v = (await TitleExtras.instance.reviews(inception))!;
      expect((r.rottenTomatoes, r.metascore, v.list.single.author, v.total), (87, 74, 'A', 1));
      expect(urls(), [
        'https://www.omdbapi.com/?apikey=omdb-test&i=tt1375666',
        'https://api.themoviedb.org/3/find/tt1375666?external_source=imdb_id',
        'https://api.themoviedb.org/3/movie/27205/reviews',
      ]);
      expect(
        ((calls.firstWhere((c) => (c.arguments as Map?)?['url'].toString().contains('themoviedb') ?? false).arguments as Map)['headers']
            as Map)['Authorization'],
        'Bearer tmdb-test',
      );
      await TitleExtras.instance.ratings(inception);
      expect(urls().length, 3, reason: 'the same page again: no new request');

      // A new session (the app restarted): read from the TV, no request.
      await TitleExtras.instance.debugSaveNow();
      TitleExtras.instance.debugReset();
      calls.clear();
      expect((await TitleExtras.instance.ratings(inception))!.metascore, 74);
      expect((await TitleExtras.instance.reviews(inception))!.list.single.text, 'Good.');
      expect(urls(), isEmpty);

      // Older than a week: asked again.
      final f = File('${dir.path}/title_extras.json');
      final j = jsonDecode(f.readAsStringSync()) as Map;
      final old = DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch;
      for (final k in ['o', 'v']) {
        for (final e in (j[k] as Map).values) {
          (e as Map)['at'] = old;
        }
      }
      f.writeAsStringSync(jsonEncode(j));
      TitleExtras.instance.debugReset();
      await TitleExtras.instance.ratings(inception);
      expect(urls(), ['https://www.omdbapi.com/?apikey=omdb-test&i=tt1375666']);
    });

    test('no key, not an IMDb id, or a failed answer: nothing (and nothing kept)', () async {
      TitleExtras.debugOmdbKey = '';
      TitleExtras.debugTmdbToken = '';
      expect(await TitleExtras.instance.ratings(inception), isNull);
      expect(await TitleExtras.instance.reviews(inception), isNull);
      expect(urls(), isEmpty);
      TitleExtras.debugOmdbKey = 'omdb-test';
      TitleExtras.debugTmdbToken = 'tmdb-test';
      expect(
        await TitleExtras.instance.ratings(ShowTitle(id: 'tmdb42', type: 'movie', title: 'X')),
        isNull,
        reason: 'OMDb needs an IMDb id',
      );
      final unknown = ShowTitle(id: 'tt0000009', type: 'series', title: 'Y');
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/tv'), (call) async {
        calls.add(call);
        if (call.method == 'filesDir') return dir.path;
        return {'status': -1, 'body': 'offline'};
      });
      expect(await TitleExtras.instance.ratings(unknown), isNull);
      expect(await TitleExtras.instance.reviews(unknown), isNull);
      // Asked again on the next visit (a failure isn't remembered).
      final before = urls().length;
      await TitleExtras.instance.ratings(unknown);
      expect(urls().length, before + 1);
    });
  });

  testWidgets('Posters: IMDb’s yellow pill, top left', (tester) async {
    await _tv(tester);
    final titles = demoTitles().take(3).toList();
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(48),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in titles)
                  Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: TvPoster(title: t, onSelect: () {}),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ImdbBadge), findsNWidgets(3));
    expect(find.text('IMDb'), findsNWidgets(3));
    expect(find.text('8.4'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNothing, reason: 'the old star badge is gone');
    final poster = tester.getTopLeft(find.byType(TvPoster).first), badge = tester.getTopLeft(find.byType(ImdbBadge).first);
    expect((badge.dx - poster.dx, badge.dy - poster.dy), (8, 8), reason: 'top left, 8 in');
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_18_poster_imdb.png'));
  });

  testWidgets('Title page, a film: IMDb · Rotten Tomatoes (fresh) · Metascore; reviews; ↓ from the buttons to them; OK opens one', (tester) async {
    await _tv(tester);
    await tester.pumpWidget(_page(_demo('Coastline')));
    await _settle(tester);
    expect(find.text('FILM · 2025 · 2h 8m · DRAMA'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is ImdbBadge && w.score == 7.6), findsOneWidget);
    expect(find.byKey(const ValueKey('rt:fresh')), findsOneWidget);
    expect(find.text('86%'), findsOneWidget);
    expect(find.text('74'), findsOneWidget);
    expect(find.text('Metascore'), findsOneWidget);
    final square = tester.widget<Container>(find.byKey(const ValueKey('mc:square')));
    expect((square.decoration! as BoxDecoration).color, const Color(0xFF66CC33));
    // The scores sit in one line under the title, above the plot.
    final imdbY = tester.getCenter(find.byType(ImdbBadge)).dy;
    expect(tester.getCenter(find.text('86%')).dy, moreOrLessEquals(imdbY, epsilon: 2));
    expect(tester.getCenter(find.byKey(const ValueKey('mc:square'))).dy, moreOrLessEquals(imdbY, epsilon: 2));
    expect(imdbY, greaterThan(tester.getBottomLeft(find.text('Coastline')).dy));
    expect(imdbY, lessThan(tester.getTopLeft(find.text('Two sisters inherit a lighthouse and its secrets.')).dy));
    // Reviews: a heading with the count, a card each.
    expect(find.text('Reviews · 12'), findsOneWidget);
    expect(find.byType(TvReviewCard), findsNWidgets(4));
    expect(
      find.descendant(of: find.byType(TvReviewCard).first, matching: find.text('9')),
      findsOneWidget,
      reason: '★ 9',
    );
    expect(find.textContaining(RegExp(r'^Data: Cinemeta.* · OMDb · TMDB$')), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_19_title_film.png'));

    // ↓ from the buttons lands on the first review (scrolled into view, focus shown).
    expect(_focusedOf<TvReviewCard>(), isNull);
    for (var k = 0; k < 5 && _focusedOf<TvReviewCard>() == null; k++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focusedOf<TvReviewCard>()?.review.author, 'John Chard');
    final card = tester.getRect(find.byType(TvReviewCard).first);
    expect(card.bottom, lessThanOrEqualTo(540), reason: 'scrolled into view');
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_20_title_reviews_focus.png'));
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedOf<TvReviewCard>()?.review.author, 'msbreviews');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    // ↑ goes back to the buttons.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focusedOf<TvReviewCard>(), isNull);
    expect(_focusedOf<TvActionPill>(), isNotNull);
    for (var k = 0; k < 5 && _focusedOf<TvReviewCard>() == null; k++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }

    // OK: the review, whole; ↓ scrolls it; Back closes.
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(TvReviewPage), findsOneWidget);
    expect(find.text('REVIEW · COASTLINE'), findsOneWidget);
    expect(find.text('3 Nov 2024'), findsOneWidget);
    expect(find.textContaining('Recommended, best watched with the lights off.'), findsOneWidget, reason: 'the whole text, not 4 lines');
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_21_review.png'));
    final scroll = tester.state<ScrollableState>(find.descendant(of: find.byType(TvReviewPage), matching: find.byType(Scrollable)));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(scroll.position.pixels, scroll.position.maxScrollExtent > 0 ? greaterThan(0) : 0);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(TvReviewPage), findsNothing);
    expect(_focusedOf<TvReviewCard>()?.review.author, 'John Chard', reason: 'back on the card it opened');
  });

  testWidgets('Title page: a rotten film (splat, red Metascore) and no reviews row; a series: IMDb only', (tester) async {
    await _tv(tester);
    await tester.pumpWidget(_page(_demo('Final Over')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('rt:rotten')), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect((tester.widget<Container>(find.byKey(const ValueKey('mc:square'))).decoration! as BoxDecoration).color, const Color(0xFFFF0000));
    expect(find.textContaining('Reviews'), findsNothing, reason: 'none: no row, no placeholder');
    expect(find.byType(TvReviewCard), findsNothing);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_22_title_rotten.png'));

    await tester.pumpWidget(_page(_demo('Night Shift')));
    await _settle(tester);
    expect(find.byWidgetPredicate((w) => w is ImdbBadge && w.size == 16), findsOneWidget, reason: 'the show’s own pill (episodes have small ones)');
    expect(find.byType(RottenTomatoesBadge), findsNothing);
    expect(find.byType(MetacriticBadge), findsNothing);
    expect(find.text('SERIES · 2022 · 2 SEASONS · DRAMA'), findsOneWidget);
    expect(find.text('Continuing'), findsOneWidget, reason: 'the status stays, after the scores');
    expect(find.textContaining('Reviews'), findsNothing);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_23_title_series.png'));
  });

  testWidgets('Title page, a series: overview + scores → actions → season tabs + episodes (own IMDb scores) → reviews', (tester) async {
    await _tv(tester);
    await tester.pumpWidget(_page(_demo('The Long Night')));
    await _settle(tester);
    expect(find.text('SERIES · 2024 · 2 SEASONS · DRAMA, MYSTERY'), findsOneWidget);
    expect(find.byType(TvSeasonTab), findsNWidgets(2));
    expect(tester.widget<TvSeasonTab>(find.byType(TvSeasonTab).first).selected, isTrue, reason: 'season 1 first');
    expect(find.byType(TvEpisodeCard), findsNWidgets(4));
    expect(find.text('E4 · Greatness Achieved'), findsOneWidget);
    expect(find.text('1h 1m · 9 Sep 2024'), findsOneWidget, reason: 'its own length, its air date');
    expect(find.text('48m · 6 Mar 2024'), findsOneWidget, reason: 'no length of its own: the show’s');
    // Each episode's own IMDb pill; none where IMDb has no score (E3).
    double? pill(int e) =>
        tester.widgetList<ImdbBadge>(find.descendant(of: find.byKey(ValueKey('episode:1:$e')), matching: find.byType(ImdbBadge))).firstOrNull?.score;
    expect(
      [
        for (final e in [1, 2, 3, 4]) pill(e),
      ],
      [8.1, 7.9, null, 9.2],
    );
    // Order: actions → seasons → episodes → reviews → cast.
    double y(Finder f) => tester.getTopLeft(f).dy;
    expect(y(find.text('Search everywhere')), lessThan(y(find.byType(TvSeasonTab).first)));
    expect(y(find.byType(TvSeasonTab).first), lessThan(y(find.byType(TvEpisodeCard).first)));
    expect(y(find.byType(TvEpisodeCard).first), lessThan(y(find.text('Reviews · 12'))));
    expect(y(find.text('Reviews · 12')), lessThan(y(find.text('Cast'))));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_24_title_series_episodes.png'));

    // ↓ from the buttons: the season tabs, then the episodes; → along them; ↓ again: reviews.
    for (var k = 0; k < 5 && _focusedOf<TvSeasonTab>() == null; k++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focusedOf<TvSeasonTab>()?.label, 'Season 1');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedOf<TvSeasonTab>()?.label, 'Season 2');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(TvEpisodeCard), findsNWidgets(3), reason: 'OK shows season 2');
    expect(find.text('E1 · Thaw'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('episode:2:1')), matching: find.byType(ImdbBadge)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('episode:2:2')), matching: find.byType(ImdbBadge)), findsNothing);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedOf<TvEpisodeCard>()?.episode.episode, isNotNull);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedOf<TvEpisodeCard>(), isNotNull);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/tv_25_title_episode_focus.png'));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedOf<TvReviewCard>(), isNotNull, reason: 'episodes ↓ reviews');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focusedOf<TvEpisodeCard>(), isNotNull, reason: 'reviews ↑ episodes');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focusedOf<TvSeasonTab>(), isNotNull, reason: 'episodes ↑ season tabs');
  });

  test('Cinemeta series meta → episodes (no specials); TMDB season fills the gaps', () {
    final d = detailsFromMeta(
      {
        'meta': {
          'name': 'Prison Break',
          'runtime': '44 min',
          'videos': [
            {'season': 0, 'episode': 1, 'name': 'Special'},
            {
              'season': 4,
              'episode': 9,
              'name': 'Greatness Achieved',
              'thumbnail': 'https://x/9.jpg',
              'released': '2008-11-03T00:00:00.000Z',
              'overview': 'Plot.',
            },
            {'season': 4, 'episode': 10, 'title': 'The Legend', 'description': 'Desc.'},
            {'season': 1, 'number': 1, 'name': 'Pilot'},
          ],
        },
      },
      ShowTitle(id: 'tt0455275', type: 'series', title: 'Prison Break'),
      'Cinemeta',
    )!;
    expect(d.seasonNumbers, [1, 4]);
    expect(d.episodeRuntime, 44);
    final s4 = d.episodesOf(4);
    expect([for (final e in s4) '${e.episode} ${e.name} ${e.overview} ${e.still}'], ['9 Greatness Achieved Plot. https://x/9.jpg', '10 The Legend Desc. null']);
    expect(s4.first.released, DateTime.utc(2008, 11, 3));
    final tmdb = episodesFromTmdbSeason({
      'episodes': [
        {
          'season_number': 4,
          'episode_number': 10,
          'name': 'The Legend',
          'overview': 'TMDB plot',
          'still_path': '/s.jpg',
          'air_date': '2008-11-10',
          'runtime': 43,
        },
      ],
    });
    final filled = s4.last.filledFrom(tmdb.single);
    expect((filled.overview, filled.still, filled.runtime), ('Desc.', 'https://image.tmdb.org/t/p/w300/s.jpg', 43), reason: 'Cinemeta’s own plot wins');
    expect(
      episodeRatingsFromOmdb({
        'Episodes': [
          {'Episode': '1', 'imdbRating': '8.1'},
          {'Episode': '2', 'imdbRating': 'N/A'},
        ],
        'Response': 'True',
      }),
      {1: 8.1},
    );
    expect(episodeRatingsFromOmdb({'Response': 'False'}), isEmpty);
  });
}
