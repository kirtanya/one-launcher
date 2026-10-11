import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'tv_apps.dart';

/// Shows & films from TMDB (themoviedb.org): search, trending, details, cast, ratings and
/// where to watch (per country, data by JustWatch).
///
/// The key is built in, never stored in git: put it in `tmdb.key` at the repo root and
/// tool/build_release.sh passes it as `--dart-define=TMDB_KEY=…`. Both TMDB key kinds work:
/// the short "API key" (v3) and the long "Read Access Token" (v4, sent as a Bearer token).
class Tmdb {
  Tmdb._();
  static final instance = Tmdb._();

  static const _key = String.fromEnvironment('TMDB_KEY');
  static bool get enabled => _key.isNotEmpty || TvApps.demo;

  /// Where-to-watch country: the TV's region, India by default.
  static String get region => WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? 'IN';

  static String image(String path, {String size = 'w500'}) => 'https://image.tmdb.org/t/p/$size$path';

  final _cache = <String, Object?>{};

  Future<List<TmdbTitle>> trending() async {
    if (TvApps.demo) return _demoTitles;
    final j = await _get('/trending/all/week', {});
    return _titles(j);
  }

  Future<List<TmdbTitle>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    if (TvApps.demo) return _demoTitles.where((t) => t.title.toLowerCase().contains(query.toLowerCase())).toList();
    final j = await _get('/search/multi', {'query': query, 'include_adult': 'false'});
    return _titles(j);
  }

  Future<TmdbDetails> details(TmdbTitle t) async {
    if (TvApps.demo) return _demoDetails(t);
    final append = t.isTv ? 'credits,watch/providers,videos,content_ratings' : 'credits,watch/providers,videos,release_dates';
    final j = await _get('/${t.type}/${t.id}', {'append_to_response': append}) as Map;
    return TmdbDetails.fromJson(t, j);
  }

  // ---- Plumbing ----

  List<TmdbTitle> _titles(Object? j) => [
    for (final r in ((j as Map?)?['results'] as List? ?? const []).cast<Map>())
      if (r['media_type'] != 'person') ?TmdbTitle.fromJson(r),
  ];

  Future<Object?> _get(String path, Map<String, String> params) async {
    final bearer = _key.length > 40; // v4 read-access token (a long JWT)
    final uri = Uri.https('api.themoviedb.org', '/3$path', {...params, 'language': 'en-US', if (!bearer) 'api_key': _key});
    final cacheKey = uri.toString();
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearer) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_key');
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw TmdbException(res.statusCode);
      return _cache[cacheKey] = jsonDecode(body);
    } finally {
      client.close();
    }
  }

  // ---- Sample data (tests / previews, no network) ----

  static const _demoTitles = [
    TmdbTitle(id: 1, type: 'tv', title: 'The Long Night', year: '2024', rating: 8.4, overview: 'A frontier town braces for a winter that never ends.'),
    TmdbTitle(id: 2, type: 'movie', title: 'Coastline', year: '2025', rating: 7.6, overview: 'Two sisters inherit a lighthouse and its secrets.'),
    TmdbTitle(id: 3, type: 'movie', title: 'Final Over', year: '2023', rating: 7.1, overview: 'Six balls. One team. A whole country watching.'),
    TmdbTitle(id: 4, type: 'tv', title: 'Night Shift', year: '2022', rating: 6.9, overview: 'The ER after midnight.'),
  ];

  static TmdbDetails _demoDetails(TmdbTitle t) => TmdbDetails(
    title: t,
    genres: const ['Drama', 'Mystery'],
    runtime: t.isTv ? null : 128,
    seasons: t.isTv ? 2 : null,
    certification: 'U/A 16+',
    tagline: 'Some nights never end.',
    votes: 1840,
    cast: const [
      TmdbPerson('Aarav Mehta', 'Kabir'),
      TmdbPerson('Mira Rao', 'Anaya'),
      TmdbPerson('Dev Iyer', 'Sheriff Rao'),
      TmdbPerson('Lena Ortiz', 'Dr. Vega'),
    ],
    providers: const [TmdbProvider('Netflix', 'stream'), TmdbProvider('JioHotstar', 'stream'), TmdbProvider('Amazon Video', 'rent')],
    trailer: 'demo',
  );
}

class TmdbException implements Exception {
  const TmdbException(this.status);
  final int status;
  @override
  String toString() => status == 401 ? 'The TMDB key was not accepted' : 'TMDB error $status';
}

/// A show or film in a list (search, trending).
class TmdbTitle {
  const TmdbTitle({required this.id, required this.type, required this.title, this.year, this.poster, this.backdrop, this.rating, this.overview});
  final int id;
  final String type; // 'movie' | 'tv'
  final String title;
  final String? year;
  final String? poster, backdrop; // TMDB image paths
  final double? rating; // 0–10
  final String? overview;

  bool get isTv => type == 'tv';
  String get key => '$type:$id';

  static TmdbTitle? fromJson(Map r) {
    final type = r['media_type'] as String? ?? (r['first_air_date'] != null ? 'tv' : 'movie');
    final title = (r['title'] ?? r['name']) as String?;
    if (title == null || (type != 'movie' && type != 'tv')) return null;
    final date = (r['release_date'] ?? r['first_air_date']) as String?;
    final vote = (r['vote_average'] as num?)?.toDouble();
    return TmdbTitle(
      id: (r['id'] as num).toInt(),
      type: type,
      title: title,
      year: date != null && date.length >= 4 ? date.substring(0, 4) : null,
      poster: r['poster_path'] as String?,
      backdrop: r['backdrop_path'] as String?,
      rating: vote != null && vote > 0 ? vote : null,
      overview: (r['overview'] as String?)?.trim().isEmpty ?? true ? null : r['overview'] as String,
    );
  }
}

class TmdbPerson {
  const TmdbPerson(this.name, this.character, {this.photo});
  final String name;
  final String? character;
  final String? photo;
}

/// One way to watch: a service and how (stream / free / ads / rent / buy).
class TmdbProvider {
  const TmdbProvider(this.name, this.kind, {this.logo, this.id});
  final String name;
  final String kind;
  final String? logo;
  final int? id;
}

class TmdbDetails {
  const TmdbDetails({
    required this.title,
    this.genres = const [],
    this.runtime,
    this.seasons,
    this.certification,
    this.tagline,
    this.votes,
    this.cast = const [],
    this.providers = const [],
    this.trailer,
  });
  final TmdbTitle title;
  final List<String> genres;
  final int? runtime; // minutes (films)
  final int? seasons; // shows
  final String? certification; // e.g. U/A 13+
  final String? tagline;
  final int? votes;
  final List<TmdbPerson> cast;
  final List<TmdbProvider> providers; // where to watch here, streaming first
  final String? trailer; // YouTube video key

  factory TmdbDetails.fromJson(TmdbTitle t, Map j) {
    final region = Tmdb.region;
    // Where to watch, in this country: streaming first, then free / with ads, then rent and buy.
    final wp = ((j['watch/providers'] as Map?)?['results'] as Map?)?[region] as Map?;
    final providers = <TmdbProvider>[];
    final seen = <String>{};
    for (final (field, kind) in [('flatrate', 'stream'), ('free', 'free'), ('ads', 'ads'), ('rent', 'rent'), ('buy', 'buy')]) {
      for (final p in ((wp?[field] as List?) ?? const []).cast<Map>()) {
        final name = p['provider_name'] as String? ?? '';
        if (name.isEmpty || !seen.add(name)) continue;
        providers.add(TmdbProvider(name, kind, logo: p['logo_path'] as String?, id: (p['provider_id'] as num?)?.toInt()));
      }
    }
    // Age rating for this country (falls back to the US one).
    String? cert;
    if (t.isTv) {
      final list = ((j['content_ratings'] as Map?)?['results'] as List? ?? const []).cast<Map>();
      Map? pick(String c) => list.where((r) => r['iso_3166_1'] == c).firstOrNull;
      cert = (pick(region) ?? pick('US'))?['rating'] as String?;
    } else {
      final list = ((j['release_dates'] as Map?)?['results'] as List? ?? const []).cast<Map>();
      String? of(String c) => ((list.where((r) => r['iso_3166_1'] == c).firstOrNull?['release_dates'] as List?) ?? const [])
          .cast<Map>()
          .map((d) => d['certification'] as String?)
          .firstWhere((x) => x != null && x.isNotEmpty, orElse: () => null);
      cert = of(region) ?? of('US');
    }
    final videos = ((j['videos'] as Map?)?['results'] as List? ?? const []).cast<Map>();
    final trailer =
        (videos.where((v) => v['site'] == 'YouTube' && v['type'] == 'Trailer' && v['official'] == true).firstOrNull ??
                videos.where((v) => v['site'] == 'YouTube' && (v['type'] == 'Trailer' || v['type'] == 'Teaser')).firstOrNull)?['key']
            as String?;
    final rawRuntime = j['runtime'] ?? ((j['episode_run_time'] as List?)?.firstOrNull);
    return TmdbDetails(
      title: TmdbTitle(
        id: t.id,
        type: t.type,
        title: t.title,
        year: t.year,
        poster: (j['poster_path'] as String?) ?? t.poster,
        backdrop: (j['backdrop_path'] as String?) ?? t.backdrop,
        rating: t.rating ?? (j['vote_average'] as num?)?.toDouble(),
        overview: (j['overview'] as String?)?.isNotEmpty ?? false ? j['overview'] as String : t.overview,
      ),
      genres: [for (final g in (j['genres'] as List? ?? const []).cast<Map>()) g['name'] as String],
      runtime: t.isTv ? null : (rawRuntime as num?)?.toInt(),
      seasons: t.isTv ? (j['number_of_seasons'] as num?)?.toInt() : null,
      certification: cert?.isEmpty ?? true ? null : cert,
      tagline: (j['tagline'] as String?)?.isEmpty ?? true ? null : j['tagline'] as String,
      votes: (j['vote_count'] as num?)?.toInt(),
      cast: [
        for (final c in ((j['credits'] as Map?)?['cast'] as List? ?? const []).cast<Map>().take(15))
          TmdbPerson(c['name'] as String? ?? '', c['character'] as String?, photo: c['profile_path'] as String?),
      ],
      providers: providers,
      trailer: trailer,
    );
  }
}
