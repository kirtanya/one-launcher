import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A movie or show from One Stream (the user's own streaming app): a row of its provider.
class OneStreamTitle {
  const OneStreamTitle({
    required this.key,
    required this.type,
    required this.title,
    required this.link,
    this.tmdb,
    this.imdb,
    this.subtitle,
    this.year,
    this.rating,
    this.poster,
    this.backdrop,
    this.progress = -1,
    this.remainingMin = -1,
  });

  factory OneStreamTitle.fromMap(Map m) {
    String? s(String k) => switch (m[k]) {
      final String v when v.isNotEmpty => v,
      _ => null,
    };
    final type = s('type') ?? 'movie';
    final tmdb = (m['tmdb'] as num?)?.toInt();
    return OneStreamTitle(
      key: s('key') ?? '$type:${tmdb ?? s('imdb') ?? s('title')}',
      type: type,
      title: s('title') ?? '',
      link: s('link') ?? (tmdb != null ? 'onestream://title/$type/$tmdb' : ''),
      tmdb: tmdb,
      imdb: s('imdb'),
      subtitle: s('subtitle'),
      year: (m['year'] as num?)?.toInt(),
      rating: (m['rating'] as num?)?.toDouble(),
      poster: s('poster'),
      backdrop: s('backdrop'),
      progress: (m['progress'] as num?)?.toDouble() ?? -1,
      remainingMin: (m['remaining_min'] as num?)?.toInt() ?? -1,
    );
  }

  final String key, type, title, link; // type: 'movie' | 'tv'
  final int? tmdb;
  final String? imdb, subtitle;
  final int? year;
  final double? rating;
  final String? poster, backdrop; // https links
  final double progress; // 0..1, -1 = none
  final int remainingMin; // -1 = unknown

  bool get isTv => type == 'tv';
  bool get hasProgress => progress >= 0;

  /// The line under the title: "S2 · E4" (One Stream's own), else the year.
  String get caption => subtitle ?? year?.toString() ?? (isTv ? 'Series' : 'Film');

  /// "12 min left" when known.
  String? get left => remainingMin > 0 ? '$remainingMin min left' : null;
}

String? _s(Map m, String k) => switch (m[k]) {
  final String v when v.isNotEmpty => v,
  _ => null,
};
int? _i(Map m, String k) => (m[k] as num?)?.toInt();
double _p(Map m, String k) => (m[k] as num?)?.toDouble() ?? -1;
bool _b(Map m, String k) => m[k] == true || m[k] == 1;

/// "1.4 GB" / "700 MB".
String sizeLabel(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  return '${(bytes / 1e6).round()} MB';
}

/// A title's page in One Stream (/details): the row's fields plus the story and your state.
class OneStreamDetails {
  OneStreamDetails(Map m)
    : title = OneStreamTitle.fromMap(m),
      overview = _s(m, 'overview'),
      genres = _s(m, 'genres'),
      runtimeMin = _i(m, 'runtime_min'),
      seasons = _i(m, 'seasons'),
      status = _s(m, 'status'),
      inWatchlist = _b(m, 'in_watchlist'),
      resumeKey = _s(m, 'resume_key'),
      resumeProgress = _p(m, 'resume_progress');
  final OneStreamTitle title;
  final String? overview, genres, status; // genres: "Drama, Sci-Fi"
  final int? runtimeMin, seasons;
  final bool inWatchlist;
  final String? resumeKey; // started: onestream://resume/<key>
  final double resumeProgress;

  String? get resumeLink => resumeKey == null ? null : 'onestream://resume/$resumeKey';

  /// "2024 · 2 h 46 min · 8.5/10"
  String get meta => [
    ?title.year?.toString(),
    if ((runtimeMin ?? 0) > 0) runtimeMin! >= 60 ? '${runtimeMin! ~/ 60} h ${runtimeMin! % 60} min' : '$runtimeMin min',
    if ((seasons ?? 0) > 0) '$seasons ${seasons == 1 ? 'season' : 'seasons'}',
    if (title.rating != null && title.rating! > 0) '${title.rating!.toStringAsFixed(1)}/10',
  ].join(' · ');
}

/// One episode of a season (/episodes).
class OneStreamEpisode {
  OneStreamEpisode(Map m)
    : season = _i(m, 'season') ?? 1,
      episode = _i(m, 'episode') ?? 0,
      name = _s(m, 'name') ?? 'Episode ${_i(m, 'episode') ?? ''}',
      overview = _s(m, 'overview'),
      still = _s(m, 'still'),
      airDate = _s(m, 'air_date'),
      aired = m['aired'] == null || _b(m, 'aired'),
      progress = _p(m, 'progress'),
      link = _s(m, 'link');
  final int season, episode;
  final String name;
  final String? overview, still, airDate, link;
  final bool aired;
  final double progress; // 0..1, -1 = not started

  String get code => 'E$episode';
}

/// A way to play it (/sources): quality, size, seeds, provider; play / download / prepare.
class OneStreamSource {
  OneStreamSource(Map m)
    : token = _s(m, 'token') ?? '',
      name = _s(m, 'name') ?? '',
      provider = _s(m, 'provider'),
      quality = _s(m, 'quality'),
      sizeBytes = _i(m, 'size_bytes'),
      seeds = _i(m, 'seeds'),
      kind = _s(m, 'kind'),
      languages = _s(m, 'languages'),
      best = _b(m, 'best'),
      playLink = _s(m, 'play_link'),
      downloadable = _b(m, 'downloadable');
  final String token, name;
  final String? provider, quality, kind, languages, playLink;
  final int? sizeBytes, seeds;
  final bool best, downloadable;

  /// "1080p" (else its name).
  String get label => quality ?? (name.isEmpty ? 'Source' : name);

  /// "2.1 GB · 340 seeds · Provider"
  String get detail => [
    if (sizeBytes != null && sizeBytes! > 0) sizeLabel(sizeBytes),
    if (seeds != null && seeds! >= 0) '$seeds seeds',
    ?provider,
    ?languages,
  ].join(' · ');
}

/// A download in One Stream (/downloads).
class OneStreamDownload {
  OneStreamDownload(Map m)
    : key = _s(m, 'key') ?? '',
      title = _s(m, 'title') ?? '',
      subtitle = _s(m, 'subtitle'),
      progress = _p(m, 'progress'),
      state = _s(m, 'state') ?? '',
      sizeBytes = _i(m, 'size_bytes'),
      playLink = _s(m, 'play_link');
  final String key, title, state; // state: e.g. downloading, paused, done, failed
  final String? subtitle, playLink;
  final double progress;
  final int? sizeBytes;

  bool get done => state == 'done' || state == 'completed' || progress >= 1;

  /// "45% · 1.2 GB" / "Ready · 1.2 GB"
  String get detail => [
    done ? 'Ready' : (progress >= 0 ? '${(progress * 100).round()}%' : (state.isEmpty ? 'Waiting' : state[0].toUpperCase() + state.substring(1))),
    if (sizeBytes != null && sizeBytes! > 0) sizeLabel(sizeBytes),
  ].join(' · ');
}

/// One Stream's answer to an action: did it work, and what it says ("Download started").
typedef OneStreamReply = ({bool ok, String? message});

/// One Stream, read locally from its ContentProvider (OneStream.kt) — no cloud. Every feature
/// that uses it hides while [available] is false (not installed, or it doesn't answer us).
class OneStream {
  OneStream._();
  static final instance = OneStream._();
  static const package = 'com.kirtanya.reel';

  /// The phone's channel; the TV app points this at "one_launcher/tv" (main_tv.dart).
  static MethodChannel channel = const MethodChannel('one_launcher/apps');

  final available = ValueNotifier<bool>(false);

  AppLifecycleListener? _life;

  /// Check now, then again whenever the launcher comes back (One Stream may have been installed).
  void init() {
    if (_life != null || kIsWeb) return;
    _life = AppLifecycleListener(onResume: refresh);
    refresh();
  }

  Future<void> refresh() async {
    try {
      available.value = await channel.invokeMethod<bool>('oneStreamAvailable') == true;
    } catch (_) {
      available.value = false;
    }
    if (!available.value) _searches.clear();
  }

  Future<List<Map>> _rows(String path, Map<String, Object> params, {int timeoutMs = 3000}) async {
    if (!available.value) return const [];
    try {
      return await channel.invokeListMethod<Map>('oneStream', {'path': path, 'params': params, 'timeoutMs': timeoutMs}) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<OneStreamTitle>> _query(String path, Map<String, Object> params, {int timeoutMs = 3000}) async => [
    for (final r in await _rows(path, params, timeoutMs: timeoutMs))
      if (OneStreamTitle.fromMap(r) case final t when t.title.isNotEmpty) t,
  ];

  // Recent searches (typing back and forth, results rebuilt) aren't asked again.
  final _searches = <String, Future<List<OneStreamTitle>>>{};

  /// One Stream's search (it goes to the network: can take a few seconds; can be empty).
  Future<List<OneStreamTitle>> search(String q, {int limit = 12}) {
    final key = q.trim().toLowerCase();
    if (key.length < 2 || !available.value) return Future.value(const []);
    if (_searches.length > 20) _searches.remove(_searches.keys.first);
    return _searches[key] ??= _query('/search', {'q': q.trim(), 'limit': limit}, timeoutMs: 10000).then((r) {
      if (r.isEmpty) _searches.remove(key); // ask again next time (may have been offline)
      return r;
    });
  }

  Future<List<OneStreamTitle>> continueWatching({int limit = 6}) => _query('/continue', {'limit': limit});
  Future<List<OneStreamTitle>> watchlist({int limit = 12}) => _query('/watchlist', {'limit': limit});

  /// One Stream's row for an IMDb title ([type]: 'movie' | 'tv'), with its progress if any.
  Future<OneStreamTitle?> titleFor(String imdb, String type) async => (await _query('/title', {'type': type, 'imdb': imdb})).firstOrNull;

  /// A title's page: story, runtime, your watchlist / progress. Null when One Stream doesn't know it.
  Future<OneStreamDetails?> details(String type, int tmdb) async =>
      [for (final r in await _rows('/details', {'type': type, 'tmdb': tmdb}, timeoutMs: 8000)) OneStreamDetails(r)].firstOrNull;

  Future<List<OneStreamEpisode>> episodes(int tmdb, int season) async => [
    for (final r in await _rows('/episodes', {'tmdb': tmdb, 'season': season}, timeoutMs: 8000)) OneStreamEpisode(r),
  ];

  /// Ways to play it (One Stream searches the network: up to ~25 s). Episode for a series.
  Future<List<OneStreamSource>> sources(String type, int tmdb, {int? season, int? episode}) async => [
    for (final r in await _rows('/sources', {'type': type, 'tmdb': tmdb, 'season': ?season, 'episode': ?episode}, timeoutMs: 30000))
      if (OneStreamSource(r) case final s when s.token.isNotEmpty) s,
  ];

  Future<List<OneStreamDownload>> downloads() async => [for (final r in await _rows('/downloads', const {})) OneStreamDownload(r)];

  /// An action in One Stream and its answer; [fallback] when it says nothing.
  Future<OneStreamReply> _act(String method, Map<String, Object> extras) async {
    if (!available.value) return (ok: false, message: 'One Stream isn’t installed');
    try {
      final m = await channel.invokeMapMethod<String, Object?>('oneStreamCall', {'method': method, 'extras': extras});
      return (ok: m?['ok'] == true || m?['ok'] == 1, message: m?['message'] as String?);
    } catch (_) {
      return (ok: false, message: null);
    }
  }

  Future<OneStreamReply> setWatchlist(bool add, String type, int tmdb) => _act(add ? 'watchlist_add' : 'watchlist_remove', {'type': type, 'tmdb': tmdb});
  Future<OneStreamReply> download(String token) => _act('download', {'token': token});
  Future<OneStreamReply> prepare(String token) => _act('prepare', {'token': token});
  Future<OneStreamReply> cancelDownload(String key) => _act('cancel_download', {'key': key});

  /// Plays a source in One Stream's player.
  static String playLink(OneStreamSource s, String type, int tmdb, {int? season, int? episode}) =>
      s.playLink ??
      'onestream://play?source=${Uri.encodeQueryComponent(s.token)}&type=$type&tmdb=$tmdb${season != null ? '&season=$season' : ''}${episode != null ? '&episode=$episode' : ''}';

  /// Opens a onestream:// link in One Stream.
  Future<bool> open(String link) async {
    if (link.isEmpty) return false;
    try {
      return await channel.invokeMethod<bool>('oneStreamOpen', {'link': link}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// A title's page in One Stream from its IMDb id ([type]: 'movie' | 'tv').
  static String imdbLink(String imdb, String type) => 'onestream://imdb/$imdb?type=$type';

  @visibleForTesting
  void debugReset({bool available = false}) {
    this.available.value = available;
    _searches.clear();
  }
}
