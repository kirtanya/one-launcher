import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Artwork for an episode when the app that plays it shares only "S4 E9 Greatness Achieved"
/// (JioHotstar: no picture, no show name).
///
/// 1. Wikidata knows which show an episode name belongs to ("episode of Prison Break").
/// 2. Cinemeta (the TV search's own catalog) finds that show and lists its episodes.
/// 3. Only if season, episode *and* name all match is that episode's still used — so a show
///    never gets someone else's picture. Nothing found: no picture (the soft glow stays).
class EpisodeArt {
  EpisodeArt._();
  static final instance = EpisodeArt._();

  static final _pattern = RegExp(r'^\s*S(\d+)\W*E(\d+)\W+(.+?)\s*$', caseSensitive: false);

  /// "S4 E9 Greatness Achieved" → (4, 9, "Greatness Achieved"); anything else → null.
  static ({int season, int episode, String name})? parse(String title) {
    final m = _pattern.firstMatch(title);
    if (m == null) return null;
    return (season: int.parse(m[1]!), episode: int.parse(m[2]!), name: m[3]!);
  }

  static String fold(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// The show names Wikidata gives for an episode name: "episode of Prison Break",
  /// "episode of M*A*S*H (S7 E18)", "8th episode of the third season of Star Trek: …".
  static List<String> showsFrom(List<String?> descriptions) {
    final out = <String>[];
    for (final d in descriptions.nonNulls) {
      final m = RegExp(r'episode of (.+)$', caseSensitive: false).firstMatch(d);
      if (m == null) continue;
      final show = m[1]!
          .replaceFirst(RegExp(r'^the \w+ season of ', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^the (\w+ )*(television|tv) series ', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*\(S\d+.*\)$'), '')
          .trim();
      if (show.isNotEmpty && !out.contains(show)) out.add(show);
    }
    return out;
  }

  final _found = <String, Future<String?>>{};

  /// The episode's picture link (or the show's backdrop), or null. Looked up once per title.
  Future<String?> find(String title) => _found.putIfAbsent(title, () => _find(title).catchError((_) => null));

  Future<String?> _find(String title) async {
    final p = parse(title);
    if (p == null) return null;
    final wiki = await _json(
      Uri.https('www.wikidata.org', '/w/api.php', {
        'action': 'wbsearchentities',
        'search': p.name,
        'language': 'en',
        'type': 'item',
        'limit': '10',
        'format': 'json',
      }),
    );
    final hits = wiki is Map ? (wiki['search'] as List? ?? const []) : const [];
    final shows = showsFrom([
      for (final h in hits)
        if (h is Map && fold('${h['label']}') == fold(p.name)) h['description'] as String?,
    ]);
    for (final show in shows.take(4)) {
      final found = await _json(Uri.parse('https://v3-cinemeta.strem.io/catalog/series/top/search=${Uri.encodeComponent(show)}.json'));
      final ids = [
        for (final m in (found is Map ? found['metas'] as List? : null) ?? const [])
          if (m is Map && fold('${m['name']}') == fold(show) && m['id'] is String) m['id'] as String,
      ];
      for (final id in ids.take(3)) {
        final meta = await _json(Uri.parse('https://v3-cinemeta.strem.io/meta/series/$id.json'));
        final videos = (meta is Map && meta['meta'] is Map ? meta['meta']['videos'] as List? : null) ?? const [];
        for (final v in videos) {
          if (v is! Map || v['season'] != p.season || v['episode'] != p.episode) continue;
          if (fold('${v['name'] ?? v['title']}') != fold(p.name)) continue;
          final still = v['thumbnail'];
          return still is String && still.startsWith('http') ? still : 'https://images.metahub.space/background/medium/$id/img';
        }
      }
    }
    return null;
  }

  static Future<Object?> _json(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, 'OneLauncherTV/1.0 (personal launcher)');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return jsonDecode(await res.transform(utf8.decoder).join());
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
