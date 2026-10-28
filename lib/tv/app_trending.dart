import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tv_apps.dart';

/// What's popular on a streaming app right now, for the picture behind its tile: from TMDB, the
/// titles on that service in India by subscription that aired (shows) or came out (films) lately,
/// most popular first, each with its wide picture. Kept on the TV for half a day.
///
/// Android shares other apps' own rows only with the TV's built-in launcher, so this is the
/// reliable way to get them. Builds without a TMDB token (the share APKs) show the app's own art.
class AppTrending {
  AppTrending._();
  static final instance = AppTrending._();

  static const _token = String.fromEnvironment('TMDB_TOKEN');

  /// TV app → its TMDB watch provider (India).
  static const providers = {
    'com.netflix.ninja': (8, 'Netflix'),
    'com.amazon.amazonvideo.livingroom': (119, 'Prime Video'),
    'in.startv.hotstar': (2336, 'JioHotstar'),
    'com.apple.atve.androidtv.appletv': (350, 'Apple TV'),
    'com.graymatrix.did': (232, 'ZEE5'),
    'com.sonyliv': (237, 'Sony LIV'),
  };

  static bool has(String package) => _token.isNotEmpty && !TvApps.demo && providers.containsKey(package);

  /// The title whose picture is showing now (the home's title block names it).
  final showing = ValueNotifier<({String package, String title})?>(null);

  final _lists = <String, Future<List<({String title, String image})>>>{};

  /// Up to 16 titles with pictures, shows and films taking turns; empty if none / offline.
  Future<List<({String title, String image})>> titles(String package) {
    if (!has(package)) return Future.value(const []);
    return _lists.putIfAbsent(package, () async {
      final list = await _load(package);
      if (list.isEmpty) _lists.remove(package); // asked again next time
      return list;
    });
  }

  static const _storeKey = 'tvAppTrending';
  static const _fresh = Duration(hours: 12);

  Future<List<({String title, String image})>> _load(String package) async {
    final sp = await SharedPreferences.getInstance();
    final kept = _decode(sp.getString(_storeKey));
    final mine = kept[package];
    if (mine is Map && DateTime.now().millisecondsSinceEpoch - ((mine['at'] as num?) ?? 0) < _fresh.inMilliseconds) {
      final saved = _list(mine['titles']);
      if (saved.isNotEmpty) return saved;
    }
    final fetched = await _fetch(providers[package]!.$1);
    if (fetched.isEmpty) return _list(mine is Map ? mine['titles'] : null); // offline: the older list, if any
    kept[package] = {
      'at': DateTime.now().millisecondsSinceEpoch,
      'titles': [
        for (final t in fetched) {'title': t.title, 'image': t.image},
      ],
    };
    await sp.setString(_storeKey, jsonEncode(kept));
    return fetched;
  }

  Future<List<({String title, String image})>> _fetch(int provider) async {
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    final now = DateTime.now();
    const common = 'watch_region=IN&with_watch_monetization_types=flatrate&sort_by=popularity.desc';
    // Shows with an episode in the last two months (no kids, news or talk shows); films from the
    // last six months.
    final shows = await _get(
      'discover/tv?with_watch_providers=$provider&$common&air_date.gte=${day(now.subtract(const Duration(days: 60)))}'
      '&air_date.lte=${day(now)}&without_genres=10762,10763,10767',
    );
    final films = await _get('discover/movie?with_watch_providers=$provider&$common&primary_release_date.gte=${day(now.subtract(const Duration(days: 180)))}');
    final out = <({String title, String image})>[];
    for (var i = 0; out.length < 16 && (i < shows.length || i < films.length); i++) {
      for (final r in [if (i < shows.length) shows[i], if (i < films.length) films[i]]) {
        final path = r['backdrop_path'];
        final title = (r['name'] ?? r['title']) as String?;
        if (path is String && title != null) out.add((title: title, image: 'https://image.tmdb.org/t/p/w1280$path'));
      }
    }
    return out;
  }

  Future<List<Map>> _get(String path) async {
    final (status, body) = await TvApps.instance.httpGet(
      'https://api.themoviedb.org/3/$path',
      headers: const {'Authorization': 'Bearer $_token', 'Accept': 'application/json'},
    );
    if (status != 200) {
      TvApps.instance.log('app trending: $status from TMDB');
      return const [];
    }
    try {
      return [
        for (final r in (jsonDecode(body) as Map)['results'] as List? ?? const [])
          if (r is Map) r,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Map<String, Object?> _decode(String? raw) {
    try {
      return raw == null ? {} : Map<String, Object?>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static List<({String title, String image})> _list(Object? raw) => [
    for (final t in raw is List ? raw : const [])
      if (t is Map && t['title'] is String && t['image'] is String) (title: t['title'] as String, image: t['image'] as String),
  ];
}
