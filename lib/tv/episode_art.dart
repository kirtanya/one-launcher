import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Artwork for an episode when the app that plays it shares only "S4 E9 Greatness Achieved"
/// (JioHotstar: no picture, no show name).
///
/// 1. Wikidata knows which show an episode name belongs to ("episode of Prison Break"): TV
///    episodes of that name first (a common word like "Free" drowns in a general search), and a
///    name many shows use ("Pilot") gets no picture rather than a guess.
/// 2. Cinemeta (the TV search's own catalog) finds that show and lists its episodes.
/// 3. That episode's still: season, episode and name matching, else the name alone within that
///    show (apps and catalogs number finales and specials differently: JioHotstar's S4 E24 "Free"
///    is Cinemeta's special "Free (2)"). Only one show fits but no episode does: the show's
///    backdrop. Nothing found: no picture (the soft glow stays).
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
  /// "episode of M*A*S*H (S7 E18)", "8th episode of the third season of Star Trek: …". With a
  /// [season] and [episode], a description naming other numbers is left out.
  static List<String> showsFrom(List<String?> descriptions, {int? season, int? episode}) {
    final out = <String>[];
    for (final d in descriptions.nonNulls) {
      final m = RegExp(r'episode of (.+)$', caseSensitive: false).firstMatch(d);
      if (m == null) continue;
      final se = RegExp(r'\(S(\d+)\s*E(\d+)\)').firstMatch(d);
      if (se != null && season != null && (int.parse(se[1]!) != season || int.parse(se[2]!) != episode)) continue;
      final show = m[1]!
          .replaceFirst(RegExp(r'^the \w+ season of ', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^the (\w+ )*(television|tv) series ', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*\(S\d+.*\)$'), '')
          .trim();
      if (show.isNotEmpty && !out.contains(show)) out.add(show);
    }
    return out;
  }

  /// An episode name without a part number: "Free (2)", "Free, Part 2" → "free".
  static String foldName(String s) => fold(s.replaceFirst(RegExp(r'\s*(\(\d+\)|,?\s*(part|pt\.?)\s*\d+)\s*$', caseSensitive: false), ''));

  /// The still of the episode in a show's catalog [videos]: season, episode and name matching,
  /// else the only episode with that name (other numbering). Null if none or several.
  static String? stillFor(List videos, int season, int episode, String name) {
    final want = foldName(name);
    String? still(Map v) => v['thumbnail'] is String && (v['thumbnail'] as String).startsWith('http') ? v['thumbnail'] as String : null;
    final named = [
      for (final v in videos)
        if (v is Map && foldName('${v['name'] ?? v['title']}') == want) v,
    ];
    for (final v in named) {
      if (v['season'] == season && v['episode'] == episode) return still(v);
    }
    return named.length == 1 ? still(named.single) : null;
  }

  final _found = <String, Future<String?>>{};

  /// The episode's picture link (or the show's backdrop), or null. Looked up once per title.
  /// When a lookup couldn't reach the internet, the next call tries again.
  Future<String?> find(String title) => _found.putIfAbsent(
    title,
    () => _find(title).catchError((_) {
      _found.remove(title);
      return null;
    }),
  );

  Future<String?> _find(String title) async {
    final p = parse(title);
    if (p == null) return null;
    // Every TV episode with that name (so a name many shows use is seen as such), else the
    // general search (episodes Wikidata hasn't marked as TV episodes).
    var shows = await _episodeShows(p.name, p.season, p.episode);
    if (shows.isEmpty) {
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
      shows = showsFrom(
        [
          for (final h in hits)
            if (h is Map && fold('${h['label']}') == fold(p.name)) h['description'] as String?,
        ],
        season: p.season,
        episode: p.episode,
      );
    }
    // A name many shows use ("Pilot"): no way to tell which, so no picture rather than a wrong one.
    if (shows.length > 3) return null;
    final picks = <String, String>{}; // show → its picture
    for (final show in shows) {
      final found = await _json(Uri.parse('https://v3-cinemeta.strem.io/catalog/series/top/search=${Uri.encodeComponent(show)}.json'));
      final ids = [
        for (final m in (found is Map ? found['metas'] as List? : null) ?? const [])
          if (m is Map && fold('${m['name']}') == fold(show) && m['id'] is String) m['id'] as String,
      ];
      String? backdrop;
      for (final id in ids.take(3)) {
        final meta = await _json(Uri.parse('https://v3-cinemeta.strem.io/meta/series/$id.json'));
        final videos = (meta is Map && meta['meta'] is Map ? meta['meta']['videos'] as List? : null) ?? const [];
        if (stillFor(videos, p.season, p.episode, p.name) case final still?) {
          picks[show] = still;
          break;
        }
        // The episode is there but has no still (or the show is the only one): its backdrop.
        final named = videos.any((v) => v is Map && foldName('${v['name'] ?? v['title']}') == foldName(p.name));
        if (named || shows.length == 1) backdrop ??= 'https://images.metahub.space/background/medium/$id/img';
      }
      if (!picks.containsKey(show) && backdrop != null) picks[show] = backdrop;
    }
    // Two shows both fit: can't tell which one is playing.
    return picks.length == 1 ? picks.values.single : null;
  }

  /// Shows with a TV episode called exactly [name], from a search of TV episodes only (Wikidata
  /// class Q21191270): for names too common for the general search.
  Future<List<String>> _episodeShows(String name, int season, int episode) async {
    final found = await _json(
      Uri.https('www.wikidata.org', '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': '$name haswbstatement:P31=Q21191270',
        'srlimit': '50',
        'format': 'json',
      }),
    );
    // No answer: stop here (the general search alone could pick the wrong show); tried again later.
    if (found is! Map) throw const SocketException('episode search unavailable');
    final ids = [
      for (final h in (found['query'] is Map ? found['query']['search'] as List? : null) ?? const [])
        if (h is Map && h['title'] is String) h['title'] as String,
    ];
    if (ids.isEmpty) return const [];
    final items = await _json(
      Uri.https('www.wikidata.org', '/w/api.php', {
        'action': 'wbgetentities',
        'ids': ids.join('|'),
        'props': 'labels|descriptions',
        'languages': 'en',
        'format': 'json',
      }),
    );
    if (items is! Map) throw const SocketException('episode details unavailable');
    final entities = items['entities'] is Map ? (items['entities'] as Map).values : const [];
    String? en(Object? e, String key) => e is Map && e[key] is Map && e[key]['en'] is Map ? e[key]['en']['value'] as String? : null;
    return showsFrom(
      [
        for (final e in entities)
          if (foldName(en(e, 'labels') ?? '') == foldName(name)) en(e, 'descriptions'),
      ],
      season: season,
      episode: episode,
    );
  }

  /// A JSON answer, or null. A busy or failed answer (Wikidata slows bursts down) is tried once
  /// more a moment later, so one hiccup doesn't leave a show without its picture.
  static Future<Object?> _json(Uri url) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      try {
        final req = await client.getUrl(url);
        req.headers.set(HttpHeaders.userAgentHeader, 'OneLauncherTV/1.0 (personal launcher)');
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode == 404) return null; // really not there
        if (res.statusCode == 200) return jsonDecode(await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 10)));
      } catch (_) {
        // offline or timed out: try again
      } finally {
        client.close();
      }
    }
    return null;
  }
}
