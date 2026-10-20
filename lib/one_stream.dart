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

  Future<List<OneStreamTitle>> _query(String path, Map<String, Object> params, {int timeoutMs = 3000}) async {
    if (!available.value) return const [];
    try {
      final rows = await channel.invokeListMethod<Map>('oneStream', {'path': path, 'params': params, 'timeoutMs': timeoutMs}) ?? const [];
      return [
        for (final r in rows)
          if (OneStreamTitle.fromMap(r) case final t when t.title.isNotEmpty) t,
      ];
    } catch (_) {
      return const [];
    }
  }

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
