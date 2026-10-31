import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'tv_apps.dart';

/// A YouTube video in search results.
class YtVideo {
  const YtVideo({required this.id, required this.title, required this.channel, this.length, this.views, required this.thumb, this.live = false});
  final String id;
  final String title, channel;
  final String? length; // "12:34"; none for live streams
  final String? views; // "1.2M views"
  final String thumb; // the largest 16:9 thumbnail
  final bool live;

  /// Opens in the YouTube app on the TV.
  String get link => 'https://www.youtube.com/watch?v=$id';
}

/// YouTube search with no API key: the same search endpoint youtube.com itself calls (the one
/// NewPipe and other clients use), videos only. Unofficial — if YouTube changes it, search here
/// just shows no YouTube row; nothing else depends on it.
class YouTubeSearch {
  YouTubeSearch._();
  static final instance = YouTubeSearch._();

  /// The YouTube app on Android TV / Google TV.
  static const tvPackage = 'com.google.android.youtube.tv';

  static const _url = 'https://www.youtube.com/youtubei/v1/search?prettyPrint=false';
  static const _videosOnly = 'EgIQAQ%3D%3D';

  final _cache = <String, List<YtVideo>>{}; // this session's searches, newest last
  static const _keep = 20;

  /// Up to ~20 videos for [query]; empty when offline or YouTube said no.
  Future<List<YtVideo>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    if (_cache[q] case final hit?) return hit;
    if (TvApps.demo) return _demo(q);
    final body = jsonEncode({
      'context': {
        'client': {'clientName': 'WEB', 'clientVersion': '2.20241101.00.00', 'hl': 'en', 'gl': 'IN'},
      },
      'query': q,
      'params': Uri.decodeComponent(_videosOnly),
    });
    final (status, text) = await TvApps.instance.httpPost(_url, body, headers: const {'Content-Type': 'application/json'});
    if (status != 200) {
      TvApps.instance.log('youtube search: $status');
      return const [];
    }
    final out = await compute(parseYouTube, text);
    _cache[q] = out;
    if (_cache.length > _keep) _cache.remove(_cache.keys.first);
    return out;
  }

  static List<YtVideo> _demo(String q) => [
    for (var i = 0; i < 8; i++)
      YtVideo(id: 'demo$i', title: '$q — video ${i + 1}', channel: 'Channel ${i + 1}', length: '${3 + i}:2$i', views: '${i + 1}.2M views', thumb: ''),
  ];
}

/// The response → videos (every `videoRenderer`, in order). Runs off the UI thread.
List<YtVideo> parseYouTube(String text) {
  final out = <YtVideo>[];
  final Object? root;
  try {
    root = jsonDecode(text);
  } catch (_) {
    return out;
  }
  String? runs(Object? o) {
    if (o is! Map) return null;
    if (o['simpleText'] case final String s) return s;
    final r = o['runs'];
    if (r is List) return r.map((x) => x is Map ? (x['text'] ?? '') : '').join();
    return null;
  }

  void walk(Object? o) {
    if (out.length >= 24) return;
    if (o is Map) {
      final v = o['videoRenderer'];
      if (v is Map && v['videoId'] is String) {
        final thumbs = (v['thumbnail'] as Map?)?['thumbnails'];
        final thumb = thumbs is List && thumbs.isNotEmpty ? (thumbs.last as Map)['url'] as String? : null;
        final badges = '${v['badges'] ?? ''} ${v['thumbnailOverlays'] ?? ''}';
        out.add(
          YtVideo(
            id: v['videoId'] as String,
            title: runs(v['title']) ?? '',
            channel: runs(v['ownerText']) ?? runs(v['longBylineText']) ?? '',
            length: runs(v['lengthText']),
            views: runs(v['shortViewCountText']) ?? runs(v['viewCountText']),
            thumb: (thumb ?? 'https://i.ytimg.com/vi/${v['videoId']}/hqdefault.jpg').split('?').first,
            live: badges.contains('LIVE'),
          ),
        );
        return;
      }
      for (final x in o.values) {
        walk(x);
      }
    } else if (o is List) {
      for (final x in o) {
        walk(x);
      }
    }
  }

  walk(root);
  return out;
}
