import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import 'catalog.dart';
import 'tv_apps.dart';

/// A title page's critics' scores and reviews, from two optional services. Each needs a key that
/// tool/build_tv.sh builds in (--dart-define, read from the gitignored omdb.key / tmdb.key); without
/// one that part of the page is simply not shown.
///
/// - **Ratings** (OMDb): IMDb, Rotten Tomatoes and Metacritic for an IMDb id. The free key allows
///   1,000 requests a day, so it's only asked when a title page opens — never for posters — and
///   each answer is kept on the TV for a week.
/// - **Reviews** (TMDB): the IMDb id → TMDB's film / series → its user reviews. Kept a week too.
///
/// Everything fails quietly (no connection, a bad key, a slow answer): the page just goes without.
/// Keys never reach a log.
class TitleExtras {
  TitleExtras._();
  static final instance = TitleExtras._();

  static const _omdbKey = String.fromEnvironment('OMDB_KEY');
  static const _tmdbToken = String.fromEnvironment('TMDB_TOKEN'); // a v4 read access token (Bearer)

  /// Tests: keys as if the build had them.
  @visibleForTesting
  static String? debugOmdbKey, debugTmdbToken;

  static String get omdbKey => debugOmdbKey ?? _omdbKey;
  static String get tmdbToken => debugTmdbToken ?? _tmdbToken;

  static const keep = Duration(days: 7); // answers are kept this long
  static const timeout = Duration(seconds: 8);
  static const maxKept = 400; // titles in the saved file (oldest go first)
  static const maxReviews = 10; // per title, each up to [maxReviewChars]
  static const maxReviewChars = 6000;

  final _ratings = <String, Future<TitleRatings?>>{};
  final _reviews = <String, Future<ShowReviews?>>{};
  final _episodes = <String, Future<Map<int, double>?>>{};
  final _seasons = <String, Future<List<ShowEpisode>?>>{};
  final _tmdbIds = <String, Future<int?>>{};

  // The saved answers, each {at, r}: 'o' scores by IMDb id, 'v' reviews by title key, 'e' episode
  // scores by 'tt…:season', 's' TMDB seasons by 'tt…:season', 'i' TMDB ids. Read once, written after a change.
  Map<String, Map<String, Object?>>? _saved;
  Future<void>? _loading;
  Timer? _saveSoon;
  String? _path;

  @visibleForTesting
  void debugReset() {
    _ratings.clear();
    _reviews.clear();
    _episodes.clear();
    _seasons.clear();
    _tmdbIds.clear();
    _saved = null;
    _loading = null;
    _path = null;
    _saveSoon?.cancel();
  }

  /// IMDb / Rotten Tomatoes / Metacritic for [t]; null when there's no key, no IMDb id or no answer.
  Future<TitleRatings?> ratings(ShowTitle t) => _once(_ratings, t.id, () => _ratingsOf(t));

  /// Reviews of [t] (newest TMDB answer, kept a week); null when there's no key or no answer.
  Future<ShowReviews?> reviews(ShowTitle t) => _once(_reviews, t.key, () => _reviewsOf(t));

  /// A series' season: each episode's own IMDb score (episode → score; "N/A" ones left out). One
  /// OMDb request per season, only when that season is shown.
  Future<Map<int, double>?> episodeRatings(ShowTitle t, int season) => _once(_episodes, '${t.id}:$season', () => _episodeRatingsOf(t, season));

  /// A series' season from TMDB: stills, plots, air dates, lengths — for episodes Cinemeta has
  /// no picture or plot for.
  Future<List<ShowEpisode>?> tmdbSeason(ShowTitle t, int season) => _once(_seasons, '${t.id}:$season', () => _tmdbSeasonOf(t, season));

  /// Asked once per session; a failure (null) is asked again next time.
  Future<R?> _once<R>(Map<String, Future<R?>> memo, String key, Future<R?> Function() ask) {
    final hit = memo[key];
    if (hit != null) return hit;
    final f = ask().catchError((Object _) => null);
    memo[key] = f;
    f.then((r) {
      if (r == null && identical(memo[key], f)) memo.remove(key);
    });
    return f;
  }

  Future<TitleRatings?> _ratingsOf(ShowTitle t) async {
    if (TvApps.demo) return demoRatings(t);
    if (omdbKey.isEmpty || !t.id.startsWith('tt')) return null;
    final kept = await _kept('o', t.id);
    if (kept is Map) return TitleRatings.fromJson(kept);
    final (status, body) = await _get('https://www.omdbapi.com/?apikey=${Uri.encodeQueryComponent(omdbKey)}&i=${t.id}');
    if (status != 200) {
      debugPrint('Ratings: OMDb answered $status'); // never the link (it holds the key)
      return null;
    }
    final r = ratingsFromOmdb(jsonDecode(body));
    if (r != null) _keep('o', t.id, r.toJson());
    return r;
  }

  Future<ShowReviews?> _reviewsOf(ShowTitle t) async {
    if (TvApps.demo) return demoReviews(t);
    if (tmdbToken.isEmpty) return null;
    final kept = await _kept('v', t.key);
    if (kept is Map) return ShowReviews.fromJson(kept);
    final id = await _tmdbId(t);
    if (id == null) return null;
    if (id == 0) {
      _keep('v', t.key, const ShowReviews([], 0).toJson()); // TMDB doesn't know it: don't ask again this week
      return const ShowReviews([], 0);
    }
    final (status, body) = await _get('https://api.themoviedb.org/3/${t.isTv ? 'tv' : 'movie'}/$id/reviews', headers: _tmdbHeaders);
    if (status != 200) {
      debugPrint('Reviews: TMDB answered $status');
      return null;
    }
    final r = reviewsFromTmdb(jsonDecode(body));
    _keep('v', t.key, r.toJson());
    return r;
  }

  Map<String, String> get _tmdbHeaders => {'Authorization': 'Bearer $tmdbToken', 'Accept': 'application/json'};

  /// TMDB's own id for [t]: in One Stream's titles already ("tmdb123"), else found from the IMDb id
  /// (kept). 0 = TMDB doesn't know it; null = couldn't ask.
  Future<int?> _tmdbId(ShowTitle t) {
    if (t.id.startsWith('tmdb')) return Future.value(int.tryParse(t.id.substring(4)));
    if (!t.id.startsWith('tt')) return Future.value();
    return _once(_tmdbIds, t.key, () async {
      final kept = await _kept('i', t.key);
      if (kept is int) return kept;
      final (status, body) = await _get('https://api.themoviedb.org/3/find/${t.id}?external_source=imdb_id', headers: _tmdbHeaders);
      if (status != 200) {
        debugPrint('TMDB find answered $status');
        return null;
      }
      final id = tmdbIdFromFind(jsonDecode(body), tv: t.isTv) ?? 0;
      _keep('i', t.key, id);
      return id;
    });
  }

  Future<Map<int, double>?> _episodeRatingsOf(ShowTitle t, int season) async {
    if (TvApps.demo) return demoEpisodeRatings(t, season);
    if (omdbKey.isEmpty || !t.id.startsWith('tt') || !t.isTv) return null;
    final key = '${t.id}:$season';
    final kept = await _kept('e', key);
    if (kept is Map) return {for (final e in kept.entries) int.parse('${e.key}'): (e.value as num).toDouble()};
    final (status, body) = await _get('https://www.omdbapi.com/?apikey=${Uri.encodeQueryComponent(omdbKey)}&i=${t.id}&Season=$season');
    if (status != 200) {
      debugPrint('Episode scores: OMDb answered $status');
      return null;
    }
    final r = episodeRatingsFromOmdb(jsonDecode(body));
    if (r == null) return null;
    _keep('e', key, {for (final e in r.entries) '${e.key}': e.value});
    return r;
  }

  Future<List<ShowEpisode>?> _tmdbSeasonOf(ShowTitle t, int season) async {
    if (TvApps.demo || tmdbToken.isEmpty || !t.isTv) return null;
    final key = '${t.id}:$season';
    final kept = await _kept('s', key);
    if (kept is List) return [...kept.map(episodeFromJson).nonNulls];
    final id = await _tmdbId(t);
    if (id == null || id == 0) return null;
    final (status, body) = await _get('https://api.themoviedb.org/3/tv/$id/season/$season', headers: _tmdbHeaders);
    if (status != 200) {
      debugPrint('TMDB season answered $status');
      return null;
    }
    final r = episodesFromTmdbSeason(jsonDecode(body));
    _keep('s', key, [for (final e in r) episodeToJson(e)]);
    return r;
  }

  Future<(int, String)> _get(String url, {Map<String, String> headers = const {}}) =>
      TvApps.instance.httpGet(url, headers: headers).timeout(timeout, onTimeout: () => (-1, 'timeout'));

  // ---- Kept on the TV ----

  static const _kinds = ['o', 'v', 'e', 's', 'i'];

  Future<Object?> _kept(String kind, String id) async {
    await (_loading ??= _load());
    final e = _saved?[kind]?[id];
    if (e is! Map || e['at'] is! int) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(e['at'] as int);
    return DateTime.now().difference(at) > keep ? null : e['r'];
  }

  Future<void> _load() async {
    _saved = {for (final k in _kinds) k: {}};
    try {
      final dir = await TvApps.instance.filesDir();
      if (dir == null) return;
      _path = '$dir/title_extras.json';
      final f = File(_path!);
      if (!f.existsSync()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      for (final k in _kinds) {
        if (j[k] is Map) _saved![k] = Map<String, Object?>.from(j[k] as Map);
      }
    } catch (e) {
      debugPrint('Ratings: couldn’t read the saved answers (${e.runtimeType})');
    }
  }

  void _keep(String kind, String id, Object? value) {
    final m = (_saved ??= {for (final k in _kinds) k: {}})[kind]!;
    m.remove(id);
    m[id] = {'at': DateTime.now().millisecondsSinceEpoch, 'r': value};
    while (m.length > maxKept) {
      m.remove(m.keys.first); // insertion order: the oldest answer
    }
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    final path = _path, saved = _saved;
    if (path == null || saved == null) return;
    try {
      await File(path).writeAsString(jsonEncode(saved));
    } catch (e) {
      debugPrint('Ratings: couldn’t save (${e.runtimeType})');
    }
  }

  @visibleForTesting
  Future<void> debugSaveNow() async {
    _saveSoon?.cancel();
    await _save();
  }
}

// =====================================================================================
// Models
// =====================================================================================

/// A title's scores. Any of them may be missing (series usually only have IMDb's).
class TitleRatings {
  const TitleRatings({this.imdb, this.rottenTomatoes, this.metascore});
  final double? imdb; // 0–10
  final int? rottenTomatoes; // Tomatometer, 0–100 %
  final int? metascore; // 0–100

  /// Rotten Tomatoes' "Fresh" (the red tomato) from 60 %; below, "Rotten" (the green splat).
  bool get fresh => (rottenTomatoes ?? 0) >= 60;

  bool get isEmpty => imdb == null && rottenTomatoes == null && metascore == null;

  Map<String, Object?> toJson() => {'i': ?imdb, 't': ?rottenTomatoes, 'm': ?metascore};

  static TitleRatings fromJson(Map j) =>
      TitleRatings(imdb: (j['i'] as num?)?.toDouble(), rottenTomatoes: (j['t'] as num?)?.toInt(), metascore: (j['m'] as num?)?.toInt());
}

/// Metacritic's colour for a Metascore: green from 61, yellow 40–60, red below 40.
Color metascoreColour(int score) => score >= 61
    ? const Color(0xFF66CC33)
    : score >= 40
    ? const Color(0xFFFFCC33)
    : const Color(0xFFFF0000);

/// One user review (TMDB).
class ShowReview {
  const ShowReview({required this.author, required this.text, this.rating, this.created});
  final String author;
  final String text; // plain text (TMDB's markdown / HTML taken out)
  final double? rating; // 0–10, often missing
  final DateTime? created;

  Map<String, Object?> toJson() => {'a': author, 'x': text, 'r': ?rating, 'c': ?created?.toIso8601String()};

  static ShowReview? fromJson(Object? j) {
    if (j is! Map || j['a'] is! String || j['x'] is! String) return null;
    return ShowReview(
      author: j['a'] as String,
      text: j['x'] as String,
      rating: (j['r'] as num?)?.toDouble(),
      created: DateTime.tryParse(j['c'] as String? ?? ''),
    );
  }
}

/// A title's reviews: the first page of them, and how many there are in all.
class ShowReviews {
  const ShowReviews(this.list, this.total);
  final List<ShowReview> list;
  final int total;

  Map<String, Object?> toJson() => {
    'l': [for (final r in list) r.toJson()],
    'n': total,
  };

  static ShowReviews fromJson(Map j) {
    final list = [...?(j['l'] as List?)?.map(ShowReview.fromJson).nonNulls];
    return ShowReviews(list, (j['n'] as num?)?.toInt() ?? list.length);
  }
}

// =====================================================================================
// Parsing
// =====================================================================================

/// OMDb's answer → the scores. An empty one for "not found"; null when it isn't OMDb's shape.
TitleRatings? ratingsFromOmdb(Object? j) {
  if (j is! Map) return null;
  if (j['Response'] == 'False') return const TitleRatings();
  int? number(Object? v) => int.tryParse(RegExp(r'\d+').firstMatch('$v')?.group(0) ?? '');
  int? rt, mc;
  for (final r in (j['Ratings'] as List?) ?? const []) {
    if (r is! Map) continue;
    switch (r['Source']) {
      case 'Rotten Tomatoes':
        rt = number(r['Value']); // "86%"
      case 'Metacritic':
        mc = number(r['Value']); // "74/100"
    }
  }
  mc ??= number(j['Metascore']); // "74" or "N/A"
  final imdb = double.tryParse('${j['imdbRating']}'); // "8.8" or "N/A"
  return TitleRatings(imdb: imdb != null && imdb > 0 ? imdb : null, rottenTomatoes: rt, metascore: mc);
}

/// OMDb's season answer → episode number → its IMDb score ("N/A" left out); null when not OMDb's shape.
Map<int, double>? episodeRatingsFromOmdb(Object? j) {
  if (j is! Map) return null;
  if (j['Response'] == 'False') return const {};
  final out = <int, double>{};
  for (final e in (j['Episodes'] as List?) ?? const []) {
    if (e is! Map) continue;
    final n = int.tryParse('${e['Episode']}'), r = double.tryParse('${e['imdbRating']}');
    if (n != null && r != null && r > 0) out[n] = r;
  }
  return out;
}

/// TMDB's /tv/{id}/season/{n} answer → its episodes (stills at a TV-friendly size).
List<ShowEpisode> episodesFromTmdbSeason(Object? j) {
  if (j is! Map) return const [];
  String? str(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
  return [
    for (final e in (j['episodes'] as List?) ?? const [])
      if (e is Map && e['season_number'] is num && e['episode_number'] is num)
        ShowEpisode(
          season: (e['season_number'] as num).toInt(),
          episode: (e['episode_number'] as num).toInt(),
          name: str(e['name']),
          overview: str(e['overview']),
          still: str(e['still_path']) == null ? null : 'https://image.tmdb.org/t/p/w300${e['still_path']}',
          released: DateTime.tryParse('${e['air_date'] ?? ''}'),
          runtime: (e['runtime'] as num?) != null && (e['runtime'] as num) > 0 ? (e['runtime'] as num).toInt() : null,
        ),
  ];
}

Map<String, Object?> episodeToJson(ShowEpisode e) => {
  's': e.season,
  'e': e.episode,
  'n': ?e.name,
  'o': ?e.overview,
  'p': ?e.still,
  'd': ?e.released?.toIso8601String(),
  'r': ?e.runtime,
};

ShowEpisode? episodeFromJson(Object? j) {
  if (j is! Map || j['s'] is! num || j['e'] is! num) return null;
  return ShowEpisode(
    season: (j['s'] as num).toInt(),
    episode: (j['e'] as num).toInt(),
    name: j['n'] as String?,
    overview: j['o'] as String?,
    still: j['p'] as String?,
    released: DateTime.tryParse(j['d'] as String? ?? ''),
    runtime: (j['r'] as num?)?.toInt(),
  );
}

/// TMDB's /find answer → the film's (or series') TMDB id; the other kind when only that matched.
int? tmdbIdFromFind(Object? j, {required bool tv}) {
  if (j is! Map) return null;
  int? first(Object? l) => l is List && l.isNotEmpty && l.first is Map ? ((l.first as Map)['id'] as num?)?.toInt() : null;
  final movie = first(j['movie_results']), series = first(j['tv_results']);
  return tv ? series ?? movie : movie ?? series;
}

/// TMDB's /reviews answer → the reviews (plain text, newest first as TMDB sends them).
ShowReviews reviewsFromTmdb(Object? j) {
  if (j is! Map) return const ShowReviews([], 0);
  final out = <ShowReview>[];
  for (final r in (j['results'] as List?) ?? const []) {
    if (r is! Map) continue;
    var text = plainText('${r['content'] ?? ''}');
    if (text.isEmpty) continue;
    if (text.length > TitleExtras.maxReviewChars) text = '${text.substring(0, TitleExtras.maxReviewChars).trimRight()}…';
    final d = r['author_details'] is Map ? r['author_details'] as Map : const {};
    final name = [r['author'], d['name'], d['username']].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).firstOrNull;
    final rating = (d['rating'] as num?)?.toDouble();
    out.add(
      ShowReview(
        author: name ?? 'Anonymous',
        text: text,
        rating: rating != null && rating > 0 ? rating : null,
        created: DateTime.tryParse('${r['created_at'] ?? ''}'),
      ),
    );
    if (out.length == TitleExtras.maxReviews) break;
  }
  final total = (j['total_results'] as num?)?.toInt() ?? out.length;
  return ShowReviews(out, total < out.length ? out.length : total);
}

/// A review's markdown / HTML as plain text: tags, emphasis and link targets out; entities decoded;
/// paragraphs kept.
String plainText(String s) {
  var t = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  t = t.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  t = t.replaceAll(RegExp(r'</(p|div|h[1-6]|li|blockquote)>', caseSensitive: false), '\n\n');
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  t = t.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ''); // images
  t = t.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!); // [text](link) → text
  t = t.replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m[2]!); // **bold**
  t = t.replaceAllMapped(RegExp(r'(^|[\s(])[*_](\S(?:.*?\S)?)[*_](?=[\s).,!?:;]|$)', multiLine: true), (m) => '${m[1]}${m[2]}'); // *italic*
  t = t.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
  t = t.replaceAll(RegExp(r'^[ \t]{0,3}(#{1,6}|>)[ \t]?', multiLine: true), ''); // headings, quotes
  t = t.replaceAll(RegExp(r'^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$', multiLine: true), ''); // --- rules
  t = _entities(t);
  t = t.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim()).join('\n');
  return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _entities(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
  final e = m[1]!;
  if (e.startsWith('#x') || e.startsWith('#X')) return String.fromCharCode(int.tryParse(e.substring(2), radix: 16) ?? 0x3F);
  if (e.startsWith('#')) return String.fromCharCode(int.tryParse(e.substring(1)) ?? 0x3F);
  return switch (e) {
    'amp' => '&',
    'lt' => '<',
    'gt' => '>',
    'quot' => '"',
    'apos' => "'",
    'nbsp' => ' ',
    'hellip' => '…',
    'mdash' => '—',
    'ndash' => '–',
    'rsquo' => '’',
    'lsquo' => '‘',
    'rdquo' => '”',
    'ldquo' => '“',
    _ => m[0]!,
  };
});

// =====================================================================================
// Sample data (tests / previews: no network)
// =====================================================================================

/// Films: all three scores (Coastline fresh, Final Over rotten); series: IMDb only.
TitleRatings? demoRatings(ShowTitle t) => switch (t.id) {
  'tt9000002' => TitleRatings(imdb: t.rating, rottenTomatoes: 86, metascore: 74),
  'tt9000003' => TitleRatings(imdb: t.rating, rottenTomatoes: 42, metascore: 38),
  'tt9000001' || 'tt9000004' => TitleRatings(imdb: t.rating),
  _ => null,
};

/// The Long Night: season 1 has scores for all but episode 3; season 2 only for episode 1.
Map<int, double>? demoEpisodeRatings(ShowTitle t, int season) =>
    t.id == 'tt9000001' || t.id == 'tt9000004' ? (season == 1 ? const {1: 8.1, 2: 7.9, 4: 9.2} : const {1: 8.4}) : const {};

/// The Long Night and Coastline have reviews; the others none.
ShowReviews? demoReviews(ShowTitle t) => switch (t.id) {
  'tt9000001' || 'tt9000002' => ShowReviews([
    ShowReview(
      author: 'John Chard',
      rating: 9,
      created: DateTime(2024, 11, 3),
      text:
          'Your mind is the scene of the crime. A slow burn that rewards every second of attention, anchored by a score that refuses to let go.\n\n'
          'The second half tightens like a knot: every small kindness early on comes back with weight, and the final hour is as tense as anything on television this year.\n\n'
          'Not everything lands — a subplot about the mill drags — but the performances carry it. Recommended, best watched with the lights off.',
    ),
    ShowReview(
      author: 'msbreviews',
      rating: 8,
      created: DateTime(2024, 10, 21),
      text: 'Rare to see something this ambitious stay this coherent. The cold is almost a character of its own.',
    ),
    ShowReview(author: 'tmdb44006625', rating: 10, created: DateTime(2024, 9, 2), text: 'Watched it three times and still catch new details in the layers.'),
    ShowReview(author: 'Reader', created: DateTime(2024, 8, 14), text: 'Beautiful, patient and a little too long. Worth it for the last episode.'),
  ], 12),
  _ => const ShowReviews([], 0),
};
