import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;

import '../prefs.dart';
import 'tv_apps.dart';

/// Shows & films for the TV's search, from Stremio addons — no third-party API key needed.
///
/// - **Sources**: addon manifest links. tool/build_tv.sh builds in the ones listed in
///   catalog_sources.txt (without that file: the public Cinemeta + WatchHub). The TV keeps its own
///   list after that: Customise → Search → Sources (switch off, remove, add).
/// - **Catalog**: every source's film & series catalogs (their first pages), merged into one local
///   list saved on the TV — search answers from it instantly, offline too. It updates itself in the
///   background (daily by default: Customise → Search → Auto-update).
/// - **Details**: the addons' "meta" (Cinemeta first): plot, IMDb rating, cast, seasons, trailer.
/// - **Where to watch**: WatchHub's official links into the streaming apps.
///
/// Only an addon's catalog and meta resources are read. The one stream resource ever asked is
/// WatchHub's, and only for its official service links — never another addon's streams, never
/// torrents or players. Manifest links can hold personal tokens: they're never logged (only addon
/// names are). All network goes through Android's own stack (TvApps.httpGet / TvApps.image).
class Catalog extends ChangeNotifier {
  Catalog._();
  static final instance = Catalog._();

  // ---- Tuning (small on purpose: the TV is a weak 32-bit device) ----
  static const pagesPerCatalog = 2; // first pages of each catalog (≈ 80–200 titles)
  static const parallel = 4; // catalog requests at a time
  static const maxCatalogsPerSource = 120;
  static const maxTitles = 30000;
  static const retryAfter = Duration(minutes: 30); // after a failed update (offline), wait this long
  static const _json = {'Accept': 'application/json'};

  /// The public addons used when the build has no sources file.
  static const publicSources = [cinemetaUrl, watchHubUrl];
  static const cinemetaUrl = 'https://v3-cinemeta.strem.io/manifest.json';
  static const watchHubUrl = 'https://watchhub.strem.io/manifest.json';

  /// Sources this build came with (tool/build_tv.sh → --dart-define=CATALOG_SOURCES, space-separated).
  static List<String> get buildSources {
    final s = parseSources(const String.fromEnvironment('CATALOG_SOURCES'));
    return s.isEmpty ? publicSources : s;
  }

  Prefs? _prefs;
  List<ShowTitle> _titles = const []; // most popular first
  final _byId = <String, ShowTitle>{};
  final _addons = <String, Addon>{}; // manifest link → addon (saved with the catalog; refreshed on update)
  List<String> _builtFrom = const []; // the sources the saved catalog was made from

  /// When the catalog last updated (null = never).
  DateTime? updated;
  bool loaded = false;
  bool syncing = false;
  double progress = 0; // 0–1 while updating

  /// What went wrong in the last update, in words (null = it worked).
  String? error;

  /// Bumps when the titles change (search screens re-run their query).
  int version = 0;

  DateTime? _lastTry;
  Future<void>? _loading;
  Completer<bool>? _sync;
  bool _pending = false; // the sources changed while an update ran: run again after it
  Timer? _clock, _syncSoon, _saveSoon;
  String? _path;

  /// Search is on: there's at least one source switched on (always in previews / tests).
  static bool get enabled => TvApps.demo || instance.enabledSources.isNotEmpty;

  int get count => _titles.length;

  /// Before typing: the most popular titles across every catalog.
  List<ShowTitle> trending([int n = 24]) => _titles.take(n).toList();

  /// Search the local catalog (instant). See [searchTitles] for the order.
  List<ShowTitle> search(String query, {int limit = 40}) => searchTitles(_titles, query, limit: limit);

  // ---- Sources ----------------------------------------------------------------

  /// Every source in the user's order (switched off ones too).
  List<String> get sources => _prefs?.catalogSources ?? buildSources;

  /// The sources that are switched on.
  List<String> get enabledSources {
    final off = _prefs?.catalogSourcesOff.toSet() ?? const <String>{};
    return [
      for (final u in sources)
        if (!off.contains(u)) u,
    ];
  }

  bool isOn(String url) => !(_prefs?.catalogSourcesOff.contains(url) ?? false);

  /// A source's addon name ("Cinemeta"); its web address until it has been checked.
  String sourceName(String url) => _addons[url]?.name ?? Uri.tryParse(url)?.host ?? 'Source';

  /// What a source gives the TV, in words ("Catalogs · details", "Where to watch").
  String sourceRole(String url) {
    final a = _addons[url];
    if (!isOn(url)) return 'Off';
    if (a == null) return 'Not checked yet';
    if (a.isWatchHub) return 'Where to watch';
    return [if (a.hasCatalogs) 'Catalogs', if (a.provides('meta')) 'Details'].join(' · ');
  }

  /// The addon whose links "Where to watch" shows (WatchHub), if it's on.
  String? get watchSourceName {
    for (final u in enabledSources) {
      final a = _addons[u];
      if (a != null && a.isWatchHub) return a.name;
    }
    return null;
  }

  /// First run: the build's sources. Later builds: sources new to the build are added (ones the
  /// user removed stay removed).
  static Future<void> seedSources(Prefs p) async {
    final (list, seen) = mergeBuildSources(current: p.catalogSources, seen: p.catalogSourcesSeen, build: buildSources);
    if (!listEquals(list, p.catalogSources)) await p.setCatalogSources(list);
    if (!listEquals(seen, p.catalogSourcesSeen)) await p.setCatalogSourcesSeen(seen);
  }

  /// Switch a source on or off (the catalog updates a moment later).
  Future<void> setSourceOn(String url, bool on) async {
    final p = _prefs;
    if (p == null) return;
    final off = [...p.catalogSourcesOff]..remove(url);
    await p.setCatalogSourcesOff(on ? off : [...off, url]);
    _sourcesChanged();
  }

  Future<void> removeSource(String url) async {
    final p = _prefs;
    if (p == null) return;
    await p.setCatalogSources([...sources]..remove(url));
    await p.setCatalogSourcesOff([...p.catalogSourcesOff]..remove(url));
    _sourcesChanged();
  }

  /// Back to the sources this build came with, all on.
  Future<void> resetSources() async {
    final p = _prefs;
    if (p == null) return;
    await p.setCatalogSources(buildSources);
    await p.setCatalogSourcesOff(const []);
    await p.setCatalogSourcesSeen({...p.catalogSourcesSeen, ...buildSources}.toList());
    _sourcesChanged();
  }

  /// Add a source from a manifest link the user typed: checks it's a working addon with catalogs,
  /// details or WatchHub's links. → a problem to show, or null when added. [stillWanted] false
  /// after the check (the user went back meanwhile) → not added.
  Future<String?> addSource(String typed, {bool Function()? stillWanted}) async {
    final p = _prefs;
    final url = normaliseSource(typed);
    if (p == null) return 'Not ready yet. Try again in a moment.';
    if (url == null) return 'That isn’t a link. It starts with https:// and ends with /manifest.json.';
    if (sources.contains(url)) return 'That source is already in the list.';
    Addon? a;
    if (TvApps.demo) {
      a = Addon.fromJson(url, const {
        'id': 'demo.addon',
        'name': 'Demo addon',
        'resources': ['catalog'],
        'types': ['movie'],
        'catalogs': [
          {'type': 'movie', 'id': 'top'},
        ],
      });
    } else {
      final (status, body) = await TvApps.instance.httpGet(url, headers: _json);
      if (status == -1) return 'Couldn’t reach it. Check the link and the TV’s internet.';
      if (status != 200) return 'The link answered $status. Use the addon’s manifest link.';
      try {
        a = Addon.fromJson(url, jsonDecode(body));
      } catch (_) {}
    }
    if (a == null) return 'That isn’t a Stremio addon manifest.';
    if (!a.hasCatalogs && !a.provides('meta') && !a.isWatchHub) return '${a.name} only has streams — nothing to search.';
    if (stillWanted != null && !stillWanted()) return 'Cancelled.';
    _addons[url] = a;
    await p.setCatalogSources([...sources, url]);
    _sourcesChanged();
    return null;
  }

  void _sourcesChanged() {
    notifyListeners();
    if (TvApps.demo) return;
    // A few changes in a row → one update.
    _syncSoon?.cancel();
    _syncSoon = Timer(const Duration(seconds: 3), () {
      if (_sync != null) _pending = true; // the running update read the old list: another one after it
      update();
    });
    if (_sync != null) _pending = true;
  }

  // ---- Start, load, auto-update ----------------------------------------------------

  /// When the home screen starts: this build's sources, the saved catalog, then an update in
  /// the background when one is due (checked again every hour — TVs stay on for days).
  Future<void> start(Prefs prefs) async {
    _prefs = prefs;
    await seedSources(prefs);
    await load();
    if (TvApps.demo) return; // previews / tests: no timers, no network
    _clock ??= Timer.periodic(const Duration(hours: 1), (_) => maybeUpdate());
    Timer(const Duration(seconds: 20), maybeUpdate); // the home screen and its artwork first
  }

  /// The saved catalog, read once (off the UI thread).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    if (TvApps.demo) {
      _setTitles(demoTitles());
      for (final a in demoAddons()) {
        _addons[a.url] = a;
      }
      updated = DateTime.now();
      _builtFrom = enabledSources;
    } else {
      try {
        final path = await _file();
        final saved = path == null ? null : await compute(readCatalogFile, path);
        if (saved != null) {
          _setTitles(saved.titles);
          updated = saved.updated;
          _builtFrom = saved.sources;
          for (final a in saved.addons) {
            _addons[a.url] = a;
          }
        }
      } catch (e) {
        debugPrint('Catalog: the saved catalog couldn’t be read (${e.runtimeType})');
      }
    }
    loaded = true;
    version++;
    notifyListeners();
  }

  /// Auto-update: when the catalog is older than the setting allows (Daily / Weekly; Off = never by
  /// itself) or the sources changed since. After a failed try (offline) it waits [retryAfter].
  void maybeUpdate() {
    final p = _prefs;
    if (p == null || TvApps.demo || !loaded || syncing) return;
    // Not while another app is in front (a film playing): the timers keep running in the
    // background, but an update is heavy for the TV. Coming back home checks again (tv.onResumed).
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    if (error != null && _lastTry != null && DateTime.now().difference(_lastTry!) < retryAfter) return;
    final changed = !listEquals(_builtFrom, enabledSources);
    if (isStale(updated: updated, now: DateTime.now(), mode: autoMode(p), sourcesChanged: changed)) update();
  }

  /// Customise → Search → Auto-update: 'daily' | 'weekly' | 'off'.
  static String autoMode(Prefs p) => p.tvSettings['catalogAuto'] as String? ?? 'daily';

  /// Update now: every source's catalogs → one merged, saved catalog. → whether it worked.
  Future<bool> update() {
    if (_sync != null) return _sync!.future;
    final c = _sync = Completer<bool>();
    _run().then(
      c.complete,
      onError: (Object e) {
        debugPrint('Catalog: update failed (${e.runtimeType})');
        error = 'The update stopped. Try again.';
        notifyListeners();
        c.complete(false);
      },
    );
    return c.future.whenComplete(() {
      _sync = null;
      if (!_pending) return;
      _pending = false;
      // Sources switched on / off / added during that update: build again from the current list.
      if (!listEquals(_builtFrom, enabledSources)) update();
    });
  }

  Future<bool> _run() async {
    syncing = true;
    progress = 0;
    error = null;
    _lastTry = DateTime.now();
    notifyListeners();
    try {
      if (TvApps.demo) {
        updated = DateTime.now();
        return true;
      }
      final urls = enabledSources;
      // 1. Manifests (a source that doesn't answer keeps its last known one).
      final found = await Future.wait([for (final u in urls) _manifest(u)]);
      final addons = found.nonNulls.toList();
      var anyFailed = found.contains(null);

      // 2. Each film / series catalog's first pages, a few at a time; parsed off the UI thread.
      final jobs = [
        for (final a in addons)
          if (a.provides('catalog'))
            for (final c in a.browsable.take(maxCatalogsPerSource)) (a, c),
      ];
      final hits = <String, ShowTitle>{};
      final answered = <String>{};
      var done = 0;
      await runPool(jobs, parallel, (job) async {
        final (a, c) = job;
        try {
          final seen = <String>{};
          var skip = 0;
          for (var page = 0; page < (c.pages ? pagesPerCatalog : 1); page++) {
            final (status, body) = await TvApps.instance.httpGet(a.catalogUrl(c, skip: skip), headers: _json);
            if (status != 200) break;
            final r = await compute(parseCatalogJob, (body, c.type, skip, c.service));
            answered.add(a.url);
            var fresh = 0;
            for (final t in r.titles) {
              if (!seen.add(t.id)) continue; // pages can overlap: count a title once per catalog
              fresh++;
              hits.update(t.id, (x) => x.mergedWith(t), ifAbsent: () => t);
            }
            if (r.count == 0 || fresh == 0) break; // the end (or the addon ignores skip)
            skip += r.count;
          }
        } catch (e) {
          debugPrint('Catalog: a ${a.name} catalog failed (${e.runtimeType})');
        }
        done++;
        progress = done / jobs.length;
        notifyListeners();
      });
      if (jobs.isNotEmpty && answered.isEmpty) {
        error = 'Couldn’t reach the catalogs. Check the TV’s internet.';
        return false;
      }
      for (final a in addons) {
        if (a.provides('catalog') && a.browsable.isNotEmpty && !answered.contains(a.url)) anyFailed = true;
      }

      // 3. Merge with what to keep from before: titles found by live search, and — when a source
      // didn't answer this time — its titles from last time (less popular, so they fade out).
      final keep = [
        for (final t in _titles)
          if (!hits.containsKey(t.id) && (t.live || anyFailed)) t.live ? t : t.withPopularity(t.popularity ~/ 2),
      ];
      final now = DateTime.now();
      final saved = CatalogFile(titles: [...hits.values, ...keep], updated: now, sources: urls, addons: addons);
      final path = await _file();
      final titles = await compute(finishCatalogJob, (saved, path, maxTitles));
      _setTitles(titles);
      updated = now;
      _builtFrom = urls;
      for (final a in addons) {
        _addons[a.url] = a;
      }
      debugPrint('Catalog: ${titles.length} titles from ${addons.map((a) => a.name).join(', ')}');
      return true;
    } finally {
      syncing = false;
      progress = 0;
      notifyListeners();
    }
  }

  Future<Addon?> _manifest(String url) async {
    try {
      final (status, body) = await TvApps.instance.httpGet(url, headers: _json);
      if (status == 200) {
        final a = Addon.fromJson(url, jsonDecode(body));
        if (a != null) return _addons[url] = a;
      }
      debugPrint('Catalog: ${_addons[url]?.name ?? 'a source'} answered $status');
    } catch (e) {
      debugPrint('Catalog: ${_addons[url]?.name ?? 'a source'} failed (${e.runtimeType})');
    }
    return _addons[url];
  }

  /// The switched-on sources' addons in the user's order (manifests fetched now if not known yet).
  Future<List<Addon>> _ready() async {
    final urls = enabledSources;
    await Future.wait([
      for (final u in urls)
        if (!_addons.containsKey(u)) _manifest(u),
    ]);
    return [for (final u in urls) ?_addons[u]];
  }

  Future<String?> _file() async {
    if (_path != null) return _path;
    final dir = await TvApps.instance.filesDir();
    return _path = dir == null ? null : '$dir/catalog.json';
  }

  void _setTitles(List<ShowTitle> titles) {
    _titles = titles;
    _byId
      ..clear()
      ..addEntries(titles.map((t) => MapEntry(t.id, t)));
    version++;
  }

  // ---- Live search (sources that can search, e.g. Cinemeta) --------------------------

  /// Asks every source that can search — for titles beyond the local catalog. What it finds joins
  /// the catalog (kept across updates).
  Future<List<ShowTitle>> searchOnline(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    if (TvApps.demo) return searchTitles(demoTitles(), q);
    final addons = await _ready();
    final jobs = [
      for (final a in addons)
        if (a.provides('catalog'))
          for (final c in a.searchable) (a, c),
    ];
    if (jobs.isEmpty) return const [];
    var offline = 0;
    final pages = await Future.wait([
      for (final (a, c) in jobs)
        // One source's broken answer (an HTML page, bad JSON) adds nothing — the others still count.
        TvApps.instance
            .httpGet(a.catalogUrl(c, search: q), headers: _json)
            .then((r) async {
              if (r.$1 == -1) offline++;
              if (r.$1 != 200) return const <ShowTitle>[];
              return (await compute(parseCatalogJob, (r.$2, c.type, 0, null))).titles;
            })
            .catchError((Object e) {
              debugPrint('Catalog: ${a.name} search failed (${e.runtimeType})');
              return const <ShowTitle>[];
            }),
    ]);
    if (offline == jobs.length) throw const CatalogException(-1);
    final out = <ShowTitle>[];
    final ids = <String>{};
    for (final list in pages) {
      for (final (i, t) in list.indexed) {
        if (ids.add(t.id)) out.add(t.withPopularity(hitScore(i) ~/ 2, live: true));
      }
    }
    _addLive(out);
    return out;
  }

  /// Titles found online join the catalog (new ones), or fill in what it was missing.
  void _addLive(List<ShowTitle> found) {
    final add = <ShowTitle>[];
    var changed = false;
    for (final t in found) {
      final had = _byId[t.id];
      if (had == null) {
        add.add(t);
      } else if ((had.year == null && t.year != null) || (had.rating == null && t.rating != null)) {
        final better = had.filledFrom(t);
        _byId[t.id] = better;
        final i = _titles.indexOf(had);
        if (i >= 0) _titles = [..._titles]..[i] = better;
        changed = true;
      }
    }
    if (add.isEmpty && !changed) return;
    _setTitles([..._titles, ...add]);
    notifyListeners();
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(seconds: 20), _save);
  }

  Future<void> _save() async {
    final path = await _file();
    if (path == null || TvApps.demo) return;
    try {
      await compute(writeCatalogJob, (
        CatalogFile(titles: _titles, updated: updated ?? DateTime.now(), sources: _builtFrom, addons: _addons.values.toList()),
        path,
      ));
    } catch (e) {
      debugPrint('Catalog: couldn’t save (${e.runtimeType})');
    }
  }

  // ---- A title's page --------------------------------------------------------------

  final _details = <String, ShowDetails>{};

  /// Plot, rating, cast, seasons, trailer — from the first source with details for it (Cinemeta
  /// first). Throws [CatalogException] when none answers.
  Future<ShowDetails> details(ShowTitle t) async {
    final hit = _details[t.key];
    if (hit != null) return hit;
    final d = TvApps.demo ? demoDetails(t) : await _detailsOf(t);
    if (_details.length > 40) _details.remove(_details.keys.first);
    return _details[t.key] = d;
  }

  Future<ShowDetails> _detailsOf(ShowTitle t) async {
    final addons = await _ready();
    final ask = [...addons.where((a) => a.isCinemeta), ...addons.where((a) => !a.isCinemeta)].where((a) => a.provides('meta', t.type, t.id));
    CatalogException? last;
    for (final a in ask) {
      final (status, body) = await TvApps.instance.httpGet(a.metaUrl(t.type, t.id), headers: _json);
      if (status == 200) {
        final d = await compute(parseMetaJob, (body, t, a.name));
        if (d != null) return d;
      }
      last = CatalogException(status, a.name);
    }
    throw last ?? const CatalogException(0);
  }

  final _links = <String, List<ShowLink>>{};

  /// Official ways to watch it (WatchHub): services with deep links into their TV apps.
  /// The only "stream" resource this app ever reads — and only WatchHub's.
  Future<List<ShowLink>> whereToWatch(ShowTitle t) async {
    final hit = _links[t.key];
    if (hit != null) return hit;
    if (TvApps.demo) return demoLinks(t);
    final hubs = (await _ready()).where((a) => a.isWatchHub && a.provides('stream', t.type, t.id));
    final out = <ShowLink>[];
    for (final a in hubs) {
      // Series: the show itself, else its first episode (WatchHub answers either, depending).
      for (final id in [t.id, if (t.isTv) '${t.id}:1:1']) {
        final url = a.watchLinksUrl(t.type, id);
        if (url == null) break;
        final (status, body) = await TvApps.instance.httpGet(url, headers: _json);
        if (status == -1) throw CatalogException(-1, a.name);
        if (status != 200) break;
        final links = parseWatchLinks(jsonDecode(body), source: a.name);
        if (links.isNotEmpty) {
          out.addAll(links.where((l) => !out.any((o) => o.service == l.service)));
          break;
        }
      }
    }
    if (_links.length > 40) _links.remove(_links.keys.first);
    return _links[t.key] = out;
  }

  /// Opens the title in a Stremio-style app (Nuvio, Stremio): its details screen there.
  static String detailLink(ShowTitle t) => 'stremio:///detail/${t.type}/${t.id}';
}

// =====================================================================================
// Models
// =====================================================================================

/// A show or film in a list (search, popular): what a poster needs.
class ShowTitle {
  ShowTitle({
    required this.id,
    required this.type,
    required this.title,
    this.year,
    String? poster,
    String? backdrop,
    this.rating,
    this.overview,
    this.genres = const [],
    this.popularity = 0,
    this.services = const [],
    this.live = false,
  }) : _poster = _ownImage(poster),
       _backdrop = _ownImage(backdrop),
       _key = ' ${foldTitle(title)}' {
    _compact = _key.replaceAll(' ', '');
  }

  final String id; // IMDb id: tt…
  final String type; // 'movie' | 'series'
  final String title;
  final String? year; // "2014", "2021–2023"
  final String? _poster, _backdrop; // the source's own picture links (kept as a second choice)
  final double? rating; // IMDb, 0–10
  final String? overview;
  final List<String> genres;
  final int popularity; // higher = more popular (from the catalogs' rankings)
  final List<String> services; // streaming services whose catalogs list it ("Netflix")
  final bool live; // found by a live search (kept across updates)
  final String _key; // folded title with a leading space: ' the long night'
  late final String _compact; // …and without spaces: 'thelongnight'

  bool get isTv => type == 'series';
  String get key => '$type:$id';

  /// Poster links, best first: the standard artwork for the IMDb id (metahub — what Stremio apps
  /// use), then the source's own (often on an image host some networks block).
  List<String> get posters => ['https://images.metahub.space/poster/medium/$id/img', ?_poster];
  List<String> get backdrops => ['https://images.metahub.space/background/medium/$id/img', ?_backdrop];

  // metahub links are the standard artwork above already; a source's own art is the second choice.
  static String? _ownImage(String? url) {
    if (url == null || !url.startsWith('http')) return null;
    return url.contains('metahub.space') ? null : url;
  }

  /// Two catalogs listed the same title: one entry, the details filled in, popularity added up.
  ShowTitle mergedWith(ShowTitle o) => ShowTitle(
    id: id,
    type: type,
    title: year == null && o.year != null ? o.title : title,
    year: year ?? o.year,
    poster: _poster ?? o._poster,
    backdrop: _backdrop ?? o._backdrop,
    rating: rating ?? o.rating,
    overview: overview ?? o.overview,
    genres: genres.isEmpty ? o.genres : genres,
    popularity: popularity + o.popularity,
    services: {...services, ...o.services}.toList(),
    live: live && o.live,
  );

  /// The same title with what it was missing taken from [o] (popularity unchanged).
  ShowTitle filledFrom(ShowTitle o) => mergedWith(o).withPopularity(popularity, live: live);

  /// Details from a title's own page win over the list's.
  ShowTitle detailedBy(ShowTitle o) => ShowTitle(
    id: id,
    type: type,
    title: o.title,
    year: o.year ?? year,
    poster: o._poster ?? _poster,
    backdrop: o._backdrop ?? _backdrop,
    rating: o.rating ?? rating,
    overview: o.overview ?? overview,
    genres: o.genres.isEmpty ? genres : o.genres,
    popularity: popularity,
    services: services,
    live: live,
  );

  ShowTitle withPopularity(int p, {bool? live}) => ShowTitle(
    id: id,
    type: type,
    title: title,
    year: year,
    poster: _poster,
    backdrop: _backdrop,
    rating: rating,
    overview: overview,
    genres: genres,
    popularity: p,
    services: services,
    live: live ?? this.live,
  );

  /// How well it matches a search (lower = better), null = not at all. [q] is folded; [sq] = ' $q';
  /// [words] = each query word with a leading space; [compact] = [q] without spaces.
  int? matchTier(String q, String sq, List<String> words, String compact) {
    final k = _key;
    if (k == sq || (compact.length >= 3 && _compact == compact)) return 0; // the title
    if (k.startsWith(sq)) return 1; // title starts with it
    if (k.contains(sq)) return 2; // a word starts with it
    if (words.length > 1 && words.every(k.contains)) return 3; // every word starts a word, any order
    if (q.length >= 2 && (k.contains(q) || (compact.length >= 3 && _compact.contains(compact)))) return 4; // anywhere
    return null;
  }

  Map<String, Object?> toJson() => {
    'i': id,
    't': isTv ? 's' : 'm',
    'n': title,
    'y': ?year,
    'p': ?_poster,
    'b': ?_backdrop,
    'r': ?rating,
    if (genres.isNotEmpty) 'g': genres,
    'd': ?overview,
    if (popularity > 0) 'o': popularity,
    if (services.isNotEmpty) 's': services,
    if (live) 'l': 1,
  };

  static ShowTitle? fromJson(Object? j) {
    if (j is! Map || j['i'] is! String || j['n'] is! String) return null;
    return ShowTitle(
      id: j['i'] as String,
      type: j['t'] == 's' ? 'series' : 'movie',
      title: j['n'] as String,
      year: j['y'] as String?,
      poster: j['p'] as String?,
      backdrop: j['b'] as String?,
      rating: (j['r'] as num?)?.toDouble(),
      overview: j['d'] as String?,
      genres: [...?(j['g'] as List?)?.whereType<String>()],
      popularity: (j['o'] as num?)?.toInt() ?? 0,
      services: [...?(j['s'] as List?)?.whereType<String>()],
      live: j['l'] == 1,
    );
  }
}

/// Someone in the cast (or the director).
class ShowPerson {
  const ShowPerson(this.name, [this.role]);
  final String name;
  final String? role; // "Director", a character
}

/// One official way to watch (WatchHub): the service, how ("Subscription", "Rent, Buy") and its links.
class ShowLink {
  const ShowLink({required this.service, this.kind, this.tvUrl, this.webUrl, this.package, this.source = 'WatchHub'});
  final String service; // "Netflix", "Amazon Prime Video"
  final String? kind;
  final String? tvUrl; // Android TV deep link (intent://… or https://…)
  final String? webUrl;
  final String? package; // the app the TV link names
  final String source; // the addon that gave it
}

/// A title's page: everything its source knows.
class ShowDetails {
  const ShowDetails({
    required this.title,
    required this.source,
    this.genres = const [],
    this.runtime,
    this.seasons,
    this.cast = const [],
    this.trailer,
    this.status,
  });
  final ShowTitle title;
  final String source; // the addon that answered ("Cinemeta")
  final List<String> genres;
  final int? runtime; // minutes (films)
  final int? seasons;
  final List<ShowPerson> cast; // cast, then director(s)
  final String? trailer; // YouTube video id
  final String? status; // series: "Ended", "Continuing"…
}

class CatalogException implements Exception {
  const CatalogException(this.status, [this.source]);
  final int status; // -1 = no connection, 0 = no source to ask
  final String? source; // the addon's name (never its link)

  @override
  String toString() => switch (status) {
    -1 => 'No connection${source == null ? '' : ' to $source'}',
    0 => 'No source has details for this',
    _ => '${source ?? 'The source'} answered $status',
  };
}

// =====================================================================================
// Addons (Stremio manifests)
// =====================================================================================

/// One source: a Stremio addon's manifest — what it offers and where.
class Addon {
  Addon._(this.url, this.id, this.name, this._resources, this.types, this.idPrefixes, this.catalogs, this.raw);

  final String url; // the manifest link — may hold a personal token: never log it
  final String id, name;
  final Map<String, (Set<String>?, List<String>?)> _resources; // name → (types, id prefixes) when narrower
  final Set<String> types;
  final List<String>? idPrefixes; // null = any id
  final List<AddonCatalog> catalogs;
  final Map raw; // as fetched (saved with the catalog)

  static Addon? fromJson(String url, Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    List<String>? strings(Object? v) => v is List ? v.whereType<String>().toList() : null;
    final resources = <String, (Set<String>?, List<String>?)>{};
    for (final r in (j['resources'] as List?) ?? const []) {
      if (r is String) resources[r] = (null, null);
      if (r is Map && r['name'] is String) resources[r['name'] as String] = (strings(r['types'])?.toSet(), strings(r['idPrefixes']));
    }
    return Addon._(
      url,
      j['id'] as String,
      (j['name'] as String?)?.trim().isNotEmpty ?? false ? (j['name'] as String).trim() : j['id'] as String,
      resources,
      {...?strings(j['types'])},
      strings(j['idPrefixes']),
      [
        for (final c in (j['catalogs'] as List?) ?? const [])
          if (c is Map) ?AddonCatalog.fromJson(c),
      ],
      j,
    );
  }

  /// The link without "/manifest.json": every resource lives under it.
  String get base => url.endsWith('/manifest.json') ? url.substring(0, url.length - '/manifest.json'.length) : url;

  /// WatchHub is known by its link only — any addon could copy its id.
  bool get isWatchHub {
    final u = Uri.tryParse(url);
    return u != null && u.scheme == 'https' && u.host == 'watchhub.strem.io';
  }

  bool get isCinemeta => id == 'com.linvo.cinemeta';
  bool get hasCatalogs => _resources.containsKey('catalog') && catalogs.isNotEmpty;

  /// Whether it offers [resource] (for this type / id, when given).
  bool provides(String resource, [String? type, String? itemId]) {
    final r = _resources[resource];
    if (r == null) return false;
    final (rTypes, rPrefixes) = r;
    if (type != null && !(rTypes ?? types).contains(type)) return false;
    final prefixes = rPrefixes ?? idPrefixes;
    return itemId == null || prefixes == null || prefixes.isEmpty || prefixes.any(itemId.startsWith);
  }

  /// The catalogs an update reads: films & series that need nothing we can't give.
  Iterable<AddonCatalog> get browsable => catalogs.where((c) => c.browsable);

  /// The catalogs that answer a search.
  Iterable<AddonCatalog> get searchable => catalogs.where((c) => c.searchable);

  String catalogUrl(AddonCatalog c, {int skip = 0, String? search}) {
    final extra = [if (search != null) 'search=${Uri.encodeComponent(search)}', if (skip > 0 || c.needsSkip) 'skip=$skip'];
    return '$base/catalog/${Uri.encodeComponent(c.type)}/${Uri.encodeComponent(c.id)}${extra.isEmpty ? '' : '/${extra.join('&')}'}.json';
  }

  String metaUrl(String type, String itemId) => '$base/meta/${Uri.encodeComponent(type)}/${Uri.encodeComponent(itemId)}.json';

  /// WatchHub only — its official where-to-watch links. No other addon's streams are ever asked.
  String? watchLinksUrl(String type, String itemId) =>
      isWatchHub && provides('stream', type, itemId) ? '$base/stream/${Uri.encodeComponent(type)}/${Uri.encodeComponent(itemId)}.json' : null;

  Map<String, Object?> toJson() => {'url': url, 'manifest': raw};
  static Addon? fromSaved(Object? j) => j is Map && j['url'] is String ? Addon.fromJson(j['url'] as String, j['manifest']) : null;
}

/// One catalog an addon lists ("Popular films", "Netflix series").
class AddonCatalog {
  const AddonCatalog(this.type, this.id, this.name, {this.extras = const {}, this.required = const {}});
  final String type, id;
  final String? name;
  final Set<String> extras; // what it accepts: 'search', 'skip', 'genre'…
  final Set<String> required; // what it must be given

  static const _special = {'last-videos', 'calendar-videos'}; // need ids of their own

  static AddonCatalog? fromJson(Map c) {
    if (c['type'] is! String || c['id'] is! String) return null;
    final extras = <String>{};
    final required = <String>{};
    for (final e in (c['extra'] as List?) ?? const []) {
      if (e is! Map || e['name'] is! String) continue;
      extras.add(e['name'] as String);
      if (e['isRequired'] == true) required.add(e['name'] as String);
    }
    extras.addAll(((c['extraSupported'] as List?) ?? const []).whereType<String>());
    required.addAll(((c['extraRequired'] as List?) ?? const []).whereType<String>());
    return AddonCatalog(c['type'] as String, c['id'] as String, c['name'] as String?, extras: extras, required: required);
  }

  bool get isShows => type == 'movie' || type == 'series';

  /// Listed in an update: films / series that need nothing but paging ("skip" is always given).
  bool get browsable => isShows && !_special.contains(id) && required.every((e) => e == 'skip');

  /// Answers a search (Cinemeta's Popular, an addon's own search catalog).
  bool get searchable => isShows && extras.contains('search') && required.every((e) => e == 'search' || e == 'skip');

  bool get pages => extras.contains('skip');
  bool get needsSkip => required.contains('skip');

  /// The streaming service a catalog is about ("netflix_movies" → Netflix), if any.
  String? get service => serviceFor('$id ${name ?? ''}');
}

/// Streaming services named by catalogs, in the words "Where to watch" uses.
const _serviceWords = [
  ('netflix', 'Netflix'),
  ('amazon', 'Prime Video'),
  ('prime', 'Prime Video'),
  ('hotstar', 'JioHotstar'),
  ('jio', 'JioHotstar'),
  ('disney', 'Disney+'),
  ('hbo', 'HBO Max'),
  ('appletv', 'Apple TV+'),
  ('apple', 'Apple TV+'),
  ('hulu', 'Hulu'),
  ('paramount', 'Paramount+'),
  ('peacock', 'Peacock'),
  ('zee5', 'ZEE5'),
  ('sonyliv', 'Sony LIV'),
  ('crunchyroll', 'Crunchyroll'),
  ('mubi', 'MUBI'),
  ('sunnxt', 'Sun NXT'),
  ('mxplayer', 'MX Player'),
  ('lionsgate', 'Lionsgate Play'),
  ('discovery', 'Discovery+'),
];

String? serviceFor(String text) {
  final s = text.toLowerCase();
  for (final (word, name) in _serviceWords) {
    if (s.contains(word)) return name;
  }
  return null;
}

// =====================================================================================
// Parsing (pure; runs off the UI thread through compute)
// =====================================================================================

final _tt = RegExp(r'^tt\d{5,10}$');
final _yt = RegExp(r'^[A-Za-z0-9_-]{6,20}$');

/// Popularity for a place in a catalog: #1 → 100, #10 → 50, #100 → 9.
int hitScore(int rank) => (1000 / (rank + 10)).round();

String? _str(Object? v) => v is String ? (v.trim().isEmpty ? null : v.trim()) : (v is num ? '$v' : null);

/// A catalog / meta entry → a title (IMDb ids only: tt…), or null.
ShowTitle? titleFromMeta(Map m, {String? type, int popularity = 0, String? service, bool shorten = true}) {
  var id = _str(m['imdb_id']);
  if (id == null || !_tt.hasMatch(id)) id = _str(m['id']);
  if (id == null || !_tt.hasMatch(id)) return null;
  final kind = switch (_str(m['type'])) {
    'movie' => 'movie',
    'series' => 'series',
    _ => type,
  };
  final name = _str(m['name']);
  if (name == null || (kind != 'movie' && kind != 'series')) return null;
  var year = _str(m['releaseInfo']) ?? _str(m['year']);
  if (year != null && RegExp(r'^\d{4}-\d\d-\d\d').hasMatch(year)) year = year.substring(0, 4);
  final rating = double.tryParse(_str(m['imdbRating']) ?? '');
  var about = _str(m['description']);
  if (shorten && about != null && about.length > 220) about = '${about.substring(0, 217).trimRight()}…';
  final genres = m['genres'] ?? m['genre'];
  return ShowTitle(
    id: id,
    type: kind!,
    title: name,
    year: year,
    poster: _str(m['poster']),
    backdrop: _str(m['background']),
    rating: rating != null && rating > 0 && rating <= 10 ? rating : null,
    overview: about,
    genres: genres is List ? genres.whereType<String>().take(4).toList() : const [],
    popularity: popularity,
    services: [?service],
  );
}

/// One catalog page → its titles (+ how many entries it had, for the next page's "skip").
({List<ShowTitle> titles, int count}) parseCatalogPage(String body, {required String type, int offset = 0, String? service}) {
  final metas = (jsonDecode(body) as Map?)?['metas'];
  if (metas is! List) return (titles: const [], count: 0);
  return (
    titles: [
      for (final (i, m) in metas.indexed)
        if (m is Map) ?titleFromMeta(m, type: type, popularity: hitScore(offset + i), service: service),
    ],
    count: metas.length,
  );
}

({List<ShowTitle> titles, int count}) parseCatalogJob((String, String, int, String?) job) =>
    parseCatalogPage(job.$1, type: job.$2, offset: job.$3, service: job.$4);

/// Merged catalog titles, most popular first (ties: higher rated, then shorter title).
List<ShowTitle> mergeTitles(Iterable<ShowTitle> hits, {int limit = Catalog.maxTitles}) {
  final byId = <String, ShowTitle>{};
  for (final t in hits) {
    byId.update(t.id, (x) => x.mergedWith(t), ifAbsent: () => t);
  }
  final list = byId.values.toList()..sort(byPopularity);
  return list.length > limit ? list.sublist(0, limit) : list;
}

int byPopularity(ShowTitle a, ShowTitle b) {
  final p = b.popularity.compareTo(a.popularity);
  if (p != 0) return p;
  final r = (b.rating ?? 0).compareTo(a.rating ?? 0);
  return r != 0 ? r : a.title.length.compareTo(b.title.length);
}

/// A title page ("meta" resource) → details, or null.
ShowDetails? detailsFromMeta(Object? j, ShowTitle base, String source) {
  final m = j is Map ? j['meta'] : null;
  if (m is! Map) return null;
  final own = titleFromMeta({...m, 'id': base.id, 'imdb_id': base.id}, type: base.type, shorten: false);
  final genres = m['genres'] ?? m['genre'];
  final videos = m['videos'];
  final seasons = <int>{
    if (videos is List)
      for (final v in videos)
        if (v is Map && v['season'] is num && (v['season'] as num) > 0) (v['season'] as num).toInt(),
  };
  String? person(Object? p) => p is String ? _str(p) : (p is Map ? _str(p['name']) : null);
  var cast = [
    for (final c in (m['cast'] as List?) ?? const [])
      if (person(c) case final n?) ShowPerson(n, c is Map ? _str(c['character']) : null),
  ];
  if (cast.isEmpty) {
    cast = [
      for (final l in (m['links'] as List?) ?? const [])
        if (l is Map && l['category'] == 'Cast' && _str(l['name']) != null) ShowPerson(_str(l['name'])!),
    ];
  }
  return ShowDetails(
    title: own == null ? base : base.detailedBy(own),
    source: source,
    genres: genres is List ? genres.whereType<String>().toList() : base.genres,
    runtime: base.isTv ? null : parseRuntime(m['runtime']),
    seasons: seasons.isEmpty ? null : seasons.length,
    cast: [
      ...cast.take(12),
      for (final d in ((m['director'] as List?) ?? const []).take(2))
        if (person(d) case final n?) ShowPerson(n, 'Director'),
    ],
    trailer: trailerOf(m),
    status: base.isTv ? _str(m['status']) : null,
  );
}

ShowDetails? parseMetaJob((String, ShowTitle, String) job) => detailsFromMeta(jsonDecode(job.$1), job.$2, job.$3);

/// "169 min", "2h 49min", 169 → minutes.
int? parseRuntime(Object? v) {
  if (v is num) return v > 0 ? v.toInt() : null;
  if (v is! String) return null;
  final h = RegExp(r'(\d+)\s*h').firstMatch(v);
  final m = RegExp(r'(\d+)\s*m').firstMatch(v);
  if (h != null || m != null) return int.parse(h?.group(1) ?? '0') * 60 + int.parse(m?.group(1) ?? '0');
  return int.tryParse(RegExp(r'\d+').firstMatch(v)?.group(0) ?? '');
}

/// The YouTube id of a title's trailer.
String? trailerOf(Map m) {
  for (final s in (m['trailerStreams'] as List?) ?? const []) {
    if (s is Map && s['ytId'] is String && _yt.hasMatch(s['ytId'] as String)) return s['ytId'] as String;
  }
  final list = ((m['trailers'] as List?) ?? const []).whereType<Map>();
  final pick = list.where((t) => t['type'] == 'Trailer').firstOrNull ?? list.firstOrNull;
  final id = pick?['source'];
  return id is String && _yt.hasMatch(id) ? id : null;
}

/// WatchHub's answer → official service links. Anything that isn't an app / web link (a video
/// file, a torrent) is ignored.
List<ShowLink> parseWatchLinks(Object? j, {String source = 'WatchHub'}) {
  final streams = j is Map ? j['streams'] : null;
  if (streams is! List) return const [];
  bool web(String? u) => u != null && (u.startsWith('https://') || u.startsWith('http://'));
  final out = <ShowLink>[];
  for (final s in streams) {
    if (s is! Map || s['infoHash'] != null) continue; // a torrent: never
    final name = _str(s['name']);
    var tv = _str(s['androidTvUrl']);
    final ext = _str(s['externalUrl']);
    if (tv != null && !tv.startsWith('intent://') && !web(tv)) tv = null;
    if (name == null || (tv == null && !web(ext))) continue; // not an app / web link (e.g. a video file)
    out.add(ShowLink(service: name, kind: _str(s['title']), tvUrl: tv, webUrl: web(ext) ? ext : null, package: packageOfIntent(tv), source: source));
  }
  return out;
}

/// The app an `intent://…#Intent;package=…;end` link names.
String? packageOfIntent(String? uri) => uri == null ? null : RegExp(r'[#;]package=([A-Za-z0-9_.]+)').firstMatch(uri)?.group(1);

// ---- Search ---------------------------------------------------------------------------

/// Local search, best first: the title itself, titles starting with the words, a word starting
/// with them, every word starting a word (any order), then anywhere. Ties: more popular, then
/// higher rated. Case and accents don't matter ("amelie" finds "Amélie").
List<ShowTitle> searchTitles(Iterable<ShowTitle> titles, String query, {int limit = 40}) {
  final q = foldTitle(query);
  if (q.isEmpty) return const [];
  final sq = ' $q';
  final words = [for (final w in q.split(' ')) ' $w'];
  final compact = q.replaceAll(' ', '');
  final hits = <(int, ShowTitle)>[];
  for (final t in titles) {
    final tier = t.matchTier(q, sq, words, compact);
    if (tier != null) hits.add((tier, t));
  }
  hits.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : byPopularity(a.$2, b.$2));
  return [for (final h in hits.take(limit)) h.$2];
}

/// Local results + a live search's: one list, no repeats, ranked together (live results the
/// words don't match — the source's own fuzzy finds — go last, in its order).
List<ShowTitle> combineResults(String query, List<ShowTitle> local, List<ShowTitle> live, {int limit = 40}) {
  final ids = {for (final t in local) t.id};
  final extra = [
    for (final t in live)
      if (ids.add(t.id)) t,
  ];
  if (extra.isEmpty) return local;
  final ranked = searchTitles([...local, ...extra], query, limit: limit);
  final shown = {for (final t in ranked) t.id};
  return [
    ...ranked,
    for (final t in extra)
      if (!shown.contains(t.id)) t,
  ].take(limit).toList();
}

final _fold = () {
  const groups = {
    'a': 'àáâãäåāăą',
    'c': 'çćĉċč',
    'd': 'ďđð',
    'e': 'èéêëēĕėęě',
    'g': 'ĝğġģ',
    'h': 'ĥħ',
    'i': 'ìíîïĩīĭįı',
    'j': 'ĵ',
    'k': 'ķ',
    'l': 'ĺļľŀł',
    'n': 'ñńņňŉ',
    'o': 'òóôõöøōŏő',
    'r': 'ŕŗř',
    's': 'śŝşšș',
    't': 'ţťŧț',
    'u': 'ùúûüũūŭůűų',
    'w': 'ŵ',
    'y': 'ýÿŷ',
    'z': 'źżž',
    'ae': 'æ',
    'oe': 'œ',
    'ss': 'ß',
    'th': 'þ',
  };
  return {
    for (final MapEntry(key: plain, value: chars) in groups.entries)
      for (final c in chars.runes) c: plain,
  };
}();

/// A title for matching: lower case, no accents, words separated by single spaces
/// ("Amélie: Part II!" → "amelie part ii"; apostrophes join: "Schindler's" → "schindlers").
String foldTitle(String s) {
  final out = StringBuffer();
  var gap = false;
  for (final r in s.toLowerCase().runes) {
    if ((r >= 97 && r <= 122) || (r >= 48 && r <= 57)) {
      if (gap && out.isNotEmpty) out.write(' ');
      gap = false;
      out.writeCharCode(r);
    } else if (r == 39 || r == 0x2019) {
      continue; // ' ’
    } else if (r < 0xC0 || r == 0xD7 || r == 0xF7 || (r >= 0x2000 && r <= 0x206F) || (r >= 0x3000 && r <= 0x303F)) {
      gap = true; // spaces, punctuation, symbols (ASCII, Latin-1, general and CJK punctuation)
    } else {
      if (gap && out.isNotEmpty) out.write(' ');
      gap = false;
      final plain = _fold[r];
      plain == null ? out.writeCharCode(r) : out.write(plain);
    }
  }
  return out.toString();
}

// ---- Sources ---------------------------------------------------------------------------

/// Manifest links from text (catalog_sources.txt, the build's list, what the user typed): any
/// number per line, `#` starts a comment, blank lines skipped, duplicates dropped.
List<String> parseSources(String text) {
  final out = <String>[];
  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    for (final word in line.trim().split(RegExp(r'\s+'))) {
      if (word.startsWith('#')) break;
      final url = normaliseSource(word);
      if (url != null && !out.contains(url)) out.add(url);
    }
  }
  return out;
}

/// A manifest link, tidied: stremio:// install links become https://, "/manifest.json" added
/// when missing. Null when it isn't a web link.
String? normaliseSource(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('stremio://')) s = 'https://${s.substring('stremio://'.length)}';
  final u = Uri.tryParse(s);
  if (u == null || (u.scheme != 'https' && u.scheme != 'http') || u.host.isEmpty) return null;
  if (!u.path.endsWith('/manifest.json')) s = '${s.replaceAll(RegExp(r'/+$'), '')}/manifest.json';
  return s;
}

/// After a build: (sources, sources any build has brought). First run = the build's list;
/// later = the user's list + links new to this build (a removed link isn't brought back).
(List<String>, List<String>) mergeBuildSources({required List<String>? current, required List<String> seen, required List<String> build}) {
  final fresh = [
    for (final u in build)
      if (!seen.contains(u)) u,
  ];
  final list = [...?current];
  for (final u in fresh) {
    if (!list.contains(u)) list.add(u);
  }
  return (list, [...seen, ...fresh]);
}

/// Time for an automatic update? Daily = after 24 h, weekly = after 7 days, off = never by itself.
/// Never updated, sources changed, or the clock went backwards → yes (unless off).
bool isStale({required DateTime? updated, required DateTime now, required String mode, bool sourcesChanged = false}) {
  if (mode == 'off') return false;
  if (updated == null || sourcesChanged) return true;
  final age = now.difference(updated);
  if (age.isNegative) return true;
  return age >= (mode == 'weekly' ? const Duration(days: 7) : const Duration(hours: 24));
}

/// "Just now", "5 min ago", "3 h ago", "Yesterday", "4 days ago"; "Never".
String agoLabel(DateTime? t, DateTime now) {
  if (t == null) return 'Never';
  final d = now.difference(t);
  if (d.inMinutes < 2) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'Yesterday';
  return '${d.inDays} days ago';
}

/// Runs [run] over [jobs], [n] at a time.
Future<void> runPool<T>(List<T> jobs, int n, Future<void> Function(T job) run) async {
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length) {
      await run(jobs[next++]);
    }
  }

  await Future.wait([for (var i = 0; i < n; i++) worker()]);
}

// ---- The saved catalog (one JSON file in the app's own storage) -----------------------

class CatalogFile {
  const CatalogFile({required this.titles, required this.updated, required this.sources, required this.addons});
  final List<ShowTitle> titles;
  final DateTime updated;
  final List<String> sources; // what it was built from
  final List<Addon> addons;

  String encode() => jsonEncode({
    'v': 1,
    'updated': updated.millisecondsSinceEpoch,
    'sources': sources,
    'addons': [for (final a in addons) a.toJson()],
    'titles': [for (final t in titles) t.toJson()],
  });

  static CatalogFile? decode(String text) {
    final j = jsonDecode(text);
    if (j is! Map || j['v'] != 1) return null;
    return CatalogFile(
      titles: [for (final t in (j['titles'] as List?) ?? const []) ?ShowTitle.fromJson(t)],
      updated: DateTime.fromMillisecondsSinceEpoch((j['updated'] as num?)?.toInt() ?? 0),
      sources: [...?(j['sources'] as List?)?.whereType<String>()],
      addons: [for (final a in (j['addons'] as List?) ?? const []) ?Addon.fromSaved(a)],
    );
  }
}

CatalogFile? readCatalogFile(String path) {
  final f = File(path);
  return f.existsSync() ? CatalogFile.decode(f.readAsStringSync()) : null;
}

void _write(String path, String text) {
  final tmp = File('$path.tmp')..writeAsStringSync(text, flush: true);
  tmp.renameSync(path); // whole file or nothing
}

/// Merge + sort + save in one go (off the UI thread). → the titles, most popular first.
List<ShowTitle> finishCatalogJob((CatalogFile, String?, int) job) {
  final (data, path, limit) = job;
  final titles = mergeTitles(data.titles, limit: limit);
  if (path != null) _write(path, CatalogFile(titles: titles, updated: data.updated, sources: data.sources, addons: data.addons).encode());
  return titles;
}

void writeCatalogJob((CatalogFile, String) job) => _write(job.$2, job.$1.encode());

// =====================================================================================
// Sample data (tests / previews: no network)
// =====================================================================================

List<ShowTitle> demoTitles() => [
  ShowTitle(
    id: 'tt9000001',
    type: 'series',
    title: 'The Long Night',
    year: '2024',
    rating: 8.4,
    overview: 'A frontier town braces for a winter that never ends.',
    genres: const ['Drama', 'Mystery'],
    popularity: 400,
    services: const ['Netflix'],
  ),
  ShowTitle(
    id: 'tt9000002',
    type: 'movie',
    title: 'Coastline',
    year: '2025',
    rating: 7.6,
    overview: 'Two sisters inherit a lighthouse and its secrets.',
    genres: const ['Drama'],
    popularity: 300,
    services: const ['Prime Video'],
  ),
  ShowTitle(
    id: 'tt9000003',
    type: 'movie',
    title: 'Final Over',
    year: '2023',
    rating: 7.1,
    overview: 'Six balls. One team. A whole country watching.',
    genres: const ['Sport', 'Drama'],
    popularity: 200,
    services: const ['JioHotstar'],
  ),
  ShowTitle(
    id: 'tt9000004',
    type: 'series',
    title: 'Night Shift',
    year: '2022',
    rating: 6.9,
    overview: 'The ER after midnight.',
    genres: const ['Drama'],
    popularity: 100,
  ),
];

List<Addon> demoAddons() => [
  Addon.fromJson(Catalog.cinemetaUrl, const {
    'id': 'com.linvo.cinemeta',
    'name': 'Cinemeta',
    'resources': ['catalog', 'meta'],
    'types': ['movie', 'series'],
    'idPrefixes': ['tt'],
    'catalogs': [
      {
        'type': 'movie',
        'id': 'top',
        'name': 'Popular',
        'extra': [
          {'name': 'search'},
          {'name': 'skip'},
        ],
      },
    ],
  })!,
  Addon.fromJson(Catalog.watchHubUrl, const {
    'id': 'org.stremio.watchhub',
    'name': 'WatchHub',
    'resources': ['stream'],
    'types': ['movie', 'series'],
    'idPrefixes': ['tt'],
    'catalogs': [],
  })!,
];

ShowDetails demoDetails(ShowTitle t) => ShowDetails(
  title: t,
  source: 'Cinemeta',
  genres: t.genres.isEmpty ? const ['Drama', 'Mystery'] : t.genres,
  runtime: t.isTv ? null : 128,
  seasons: t.isTv ? 2 : null,
  status: t.isTv ? 'Continuing' : null,
  cast: const [ShowPerson('Aarav Mehta'), ShowPerson('Mira Rao'), ShowPerson('Dev Iyer'), ShowPerson('Lena Ortiz'), ShowPerson('Kabir Sen', 'Director')],
  trailer: 'demoTrailer1',
);

List<ShowLink> demoLinks(ShowTitle t) => const [
  ShowLink(
    service: 'Netflix',
    kind: 'Subscription',
    tvUrl: 'intent://www.netflix.com/watch/80000001#Intent;scheme=https;package=com.netflix.ninja;end',
    webUrl: 'https://www.netflix.com/title/80000001',
    package: 'com.netflix.ninja',
  ),
  ShowLink(
    service: 'JioHotstar',
    kind: 'Subscription',
    tvUrl: 'intent://www.hotstar.com/in/shows/the-long-night/1#Intent;scheme=https;package=in.startv.hotstar;end',
    webUrl: 'https://www.hotstar.com/in/shows/the-long-night/1',
    package: 'in.startv.hotstar',
  ),
  ShowLink(
    service: 'Amazon Prime Video',
    kind: 'Rent',
    tvUrl: 'intent://app.primevideo.com/detail?gti=demo#Intent;package=com.amazon.amazonvideo.livingroom;scheme=https;end',
    webUrl: 'https://app.primevideo.com/detail?gti=demo',
    package: 'com.amazon.amazonvideo.livingroom',
  ),
  ShowLink(service: 'Google Play Movies', kind: 'Rent, Buy', webUrl: 'https://play.google.com/store/movies/details?id=demo'),
];
