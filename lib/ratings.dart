import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'tv/catalog.dart';
import 'tv/tv_apps.dart';

/// A title page's critics' scores and reviews (phone and TV), from two optional services. Each
/// needs a key that the build scripts build in (tool/build_tv.sh, tool/build_release.sh:
/// --dart-define, read from the gitignored omdb.key / tmdb.key); without one that part of the page
/// is simply not shown.
///
/// - **Ratings** (OMDb): IMDb, Rotten Tomatoes and Metacritic for an IMDb id. The free key allows
///   1,000 requests a day, so it's only asked when a title page opens — never for posters — and
///   each answer is kept on the device for a week (posters show an IMDb score only once it's known).
/// - **Reviews** (TMDB): the IMDb id → TMDB's film / series → its user reviews. Kept a week too.
///
/// Everything fails quietly (no connection, a bad key, a slow answer): the page just goes without.
/// Keys never reach a log.
///
/// Network and storage: the TV's own Android stack and files folder ([useTv], main_tv.dart); on the
/// phone, dart:io and the app's preferences (the default).
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

  /// GET → (status, body); status -1 = no answer.
  static Future<(int, String)> Function(String url, Map<String, String> headers) transport = _ioGet;

  /// Reads / writes the saved answers (JSON).
  static Future<String?> Function() readSaved = _prefsRead;
  static Future<void> Function(String json) writeSaved = _prefsWrite;

  /// The TV: requests through Android (TvApps.httpGet), answers in a file in its files folder.
  static void useTv() {
    transport = (url, headers) => TvApps.instance.httpGet(url, headers: headers);
    readSaved = () async {
      final dir = await TvApps.instance.filesDir();
      if (dir == null) return null;
      final f = File('$dir/title_extras.json');
      return f.existsSync() ? f.readAsString() : null;
    };
    writeSaved = (json) async {
      final dir = await TvApps.instance.filesDir();
      if (dir != null) await File('$dir/title_extras.json').writeAsString(json);
    };
  }

  /// The phone (the default): dart:io, the app's preferences.
  static void usePhone() {
    transport = _ioGet;
    readSaved = _prefsRead;
    writeSaved = _prefsWrite;
  }

  static Future<(int, String)> _ioGet(String url, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach(req.headers.set);
      final res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    } catch (e) {
      return (-1, e.runtimeType.toString());
    } finally {
      client.close();
    }
  }

  static const _prefsKey = 'titleExtras';
  static Future<String?> _prefsRead() async => (await SharedPreferences.getInstance()).getString(_prefsKey);
  static Future<void> _prefsWrite(String json) async => (await SharedPreferences.getInstance()).setString(_prefsKey, json);

  /// Tests / previews: the sample answers (also whenever [TvApps.demo]).
  static bool demo = false;
  static bool get _demo => demo || TvApps.demo;

  /// Bumped when saved answers arrive (posters showing a known IMDb score rebuild).
  final changed = ValueNotifier<int>(0);

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
  final _imdbIds = <String, Future<String?>>{};

  // The saved answers, each {at, r}: 'o' scores by IMDb id, 'v' reviews by title key, 'e' episode
  // scores by 'tt…:season', 's' TMDB seasons by 'tt…:season', 'i' TMDB ids. Read once, written after a change.
  Map<String, Map<String, Object?>>? _saved;
  Future<void>? _loading;
  Timer? _saveSoon;

  @visibleForTesting
  void debugReset() {
    _ratings.clear();
    _reviews.clear();
    _episodes.clear();
    _seasons.clear();
    _tmdbIds.clear();
    _imdbIds.clear();
    _saved = null;
    _loading = null;
    _saveSoon?.cancel();
  }

  /// Reads the saved answers now (so [imdbNow] knows them); posters rebuild through [changed].
  void warm() => _loading ??= _load();

  /// The IMDb score already known for an IMDb id (from a page opened in the last week), else null.
  /// Never asks the network: posters use this.
  double? imdbNow(String? imdb) {
    if (imdb == null) return null;
    if (_demo) return demoImdb[imdb];
    warm();
    final e = _saved?['o']?[imdb];
    if (e is! Map || e['at'] is! int || e['r'] is! Map) return null;
    if (DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(e['at'] as int)) > keep) return null;
    return ((e['r'] as Map)['i'] as num?)?.toDouble();
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
    if (_demo) return demoRatings(t);
    if (omdbKey.isEmpty) return null;
    final imdb = await _imdbId(t);
    if (imdb == null) return null;
    final kept = await _kept('o', imdb);
    if (kept is Map) return TitleRatings.fromJson(kept);
    final (status, body) = await _get('https://www.omdbapi.com/?apikey=${Uri.encodeQueryComponent(omdbKey)}&i=$imdb');
    if (status != 200) {
      debugPrint('Ratings: OMDb answered $status'); // never the link (it holds the key)
      return null;
    }
    final r = ratingsFromOmdb(jsonDecode(body));
    if (r != null) {
      _keep('o', imdb, r.toJson());
      changed.value++;
    }
    return r;
  }

  Future<ShowReviews?> _reviewsOf(ShowTitle t) async {
    if (_demo) return demoReviews(t);
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

  /// The IMDb id for [t]: its own, or (One Stream's TMDB-only titles) TMDB's external ids (kept).
  Future<String?> _imdbId(ShowTitle t) {
    if (t.id.startsWith('tt')) return Future.value(t.id);
    final tmdb = t.id.startsWith('tmdb') ? int.tryParse(t.id.substring(4)) : null;
    if (tmdb == null || tmdbToken.isEmpty) return Future.value();
    return _once(_imdbIds, t.key, () async {
      final kept = await _kept('x', t.key);
      if (kept is String) return kept.isEmpty ? null : kept;
      final (status, body) = await _get('https://api.themoviedb.org/3/${t.isTv ? 'tv' : 'movie'}/$tmdb/external_ids', headers: _tmdbHeaders);
      if (status != 200) return null;
      final j = jsonDecode(body);
      final id = j is Map && j['imdb_id'] is String && (j['imdb_id'] as String).startsWith('tt') ? j['imdb_id'] as String : '';
      _keep('x', t.key, id);
      return id.isEmpty ? null : id;
    });
  }

  Future<Map<int, double>?> _episodeRatingsOf(ShowTitle t, int season) async {
    if (_demo) return demoEpisodeRatings(t, season);
    if (omdbKey.isEmpty || !t.isTv) return null;
    final imdb = await _imdbId(t);
    if (imdb == null) return null;
    final key = '$imdb:$season';
    final kept = await _kept('e', key);
    if (kept is Map) return {for (final e in kept.entries) int.parse('${e.key}'): (e.value as num).toDouble()};
    final (status, body) = await _get('https://www.omdbapi.com/?apikey=${Uri.encodeQueryComponent(omdbKey)}&i=$imdb&Season=$season');
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
    if (_demo || tmdbToken.isEmpty || !t.isTv) return null;
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
      transport(url, headers).timeout(timeout, onTimeout: () => (-1, 'timeout')).catchError((Object _) => (-1, 'error'));

  // ---- Kept on the device ----

  static const _kinds = ['o', 'v', 'e', 's', 'i', 'x'];

  Future<Object?> _kept(String kind, String id) async {
    await (_loading ??= _load());
    final e = _saved?[kind]?[id];
    if (e is! Map || e['at'] is! int) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(e['at'] as int);
    return DateTime.now().difference(at) > keep ? null : e['r'];
  }

  Future<void> _load() async {
    _saved = {for (final k in _kinds) k: {}};
    if (_demo) return;
    try {
      final raw = await readSaved();
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      for (final k in _kinds) {
        if (j[k] is Map) _saved![k] = Map<String, Object?>.from(j[k] as Map);
      }
      changed.value++;
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
    final saved = _saved;
    if (saved == null || _demo) return;
    try {
      await writeSaved(jsonEncode(saved));
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

/// Sample IMDb scores already known (posters).
const demoImdb = {'tt9000001': 8.4, 'tt9000002': 7.6, 'tt9000003': 7.1, 'tt9000004': 6.9};

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
