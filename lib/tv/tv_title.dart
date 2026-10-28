import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../one_stream.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'catalog.dart';
import '../ratings.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';
import 'tv_metro.dart';
import 'tv_one_stream.dart';
import 'tv_parts.dart';
import 'tv_ratings.dart';

// ---- Streaming service → the app on this TV ---------------------------------------

/// Known services → their Android TV apps (India first; the first one installed wins).
/// Anything else is matched by name.
const _servicePackages = <String, List<String>>{
  'netflix': ['com.netflix.ninja'],
  'amazonprimevideo': ['com.amazon.amazonvideo.livingroom'],
  'amazonvideo': ['com.amazon.amazonvideo.livingroom'],
  'amazon': ['com.amazon.amazonvideo.livingroom'],
  'primevideo': ['com.amazon.amazonvideo.livingroom'],
  'jiohotstar': ['in.startv.hotstar'],
  'hotstar': ['in.startv.hotstar'],
  'disneyplushotstar': ['in.startv.hotstar'],
  'disneyplus': ['in.startv.hotstar', 'com.disney.disneyplus'],
  'disney': ['in.startv.hotstar', 'com.disney.disneyplus'],
  'jiocinema': ['in.startv.hotstar'],
  'hbomax': ['com.wbd.stream', 'com.hbo.hbonow'],
  'max': ['com.wbd.stream'],
  'zee5': ['com.graymatrix.did'],
  'sonyliv': ['com.sonyliv'],
  'youtube': ['com.google.android.youtube.tv'],
  'googleplaymovies': ['com.google.android.videos'],
  'googletv': ['com.google.android.videos'],
  'appletvplus': ['com.apple.atve.androidtv.appletv'],
  'appletv': ['com.apple.atve.androidtv.appletv'],
  'mxplayer': ['com.mxtech.videoplayer.television'],
  'sunnxt': ['com.suntv.sunnxt'],
  'aha': ['ahaflix.tv'],
  'lionsgateplay': ['com.lionsgateplay.videoapp'],
  'mubi': ['com.mubi'],
  'crunchyroll': ['com.crunchyroll.crunchyroid'],
};

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// The installed app for a streaming service, if there is one.
AppEntry? appForService(String service, List<AppEntry> apps) {
  final n = _norm(service.replaceAll(RegExp(r'(with ads|amazon channel|apple tv channel)', caseSensitive: false), ''));
  final byPkg = {for (final a in apps) a.package: a};
  for (final e in _servicePackages.entries) {
    if (!n.startsWith(e.key)) continue;
    for (final p in e.value) {
      if (byPkg[p] case final app?) return app;
    }
  }
  final first = _norm(service.split(' ').first);
  if (first.length < 3) return null;
  return apps.where((a) => _norm(a.label).contains(first) || n.contains(_norm(a.label))).firstOrNull;
}

// ---- Poster tile ------------------------------------------------------------------

/// A One Stream title as a catalog one (for [TvPoster]): the standard artwork for its IMDb id
/// first, then One Stream's own picture. Its score is IMDb's when known (the catalog's, or one
/// already looked up) — One Stream's own is TMDB's, so it isn't shown as IMDb's.
ShowTitle showTitleOf(OneStreamTitle t) => ShowTitle(
  id: t.imdb ?? 'tmdb${t.tmdb ?? t.key}',
  type: t.isTv ? 'series' : 'movie',
  title: t.title,
  year: t.year?.toString(),
  poster: t.poster,
  backdrop: t.backdrop,
  rating: t.imdb == null ? null : Catalog.instance.byId(t.imdb!)?.rating ?? TitleExtras.instance.imdbNow(t.imdb),
);

/// A show / film as a 2:3 poster: IMDb's pill top left, title + year underneath.
class TvPoster extends StatelessWidget {
  const TvPoster({super.key, required this.title, required this.onSelect, this.focusNode});
  final ShowTitle title;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  static const w = 116.0, h = 174.0;

  @override
  Widget build(BuildContext context) {
    final t = title;
    return Semantics(
      button: true,
      label: t.title,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        builder: (context, f) => SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: f ? TvDS.focusScaleCard : 1,
                duration: Motion.popDuration,
                curve: Motion.pop,
                child: AnimatedContainer(
                  duration: Motion.pressIn * 2,
                  width: w,
                  height: h,
                  // Tiles: the Metro frame and the tile corners.
                  foregroundDecoration: TvMetro.on ? TvMetro.frame(f, width: TvDS.focusRing) : TvRing(on: f, radius: TvDS.rTile),
                  decoration: BoxDecoration(
                    borderRadius: TvMetro.corners(TvDS.rTile),
                    boxShadow: TvMetro.on ? TvMetro.glow(f) : (f ? const [BoxShadow(color: TvDS.glow, blurRadius: 22)] : null),
                  ),
                  child: ClipRRect(
                    borderRadius: TvMetro.corners(TvDS.rTile),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ShowImage(urls: t.posters, decodeWidth: 240, fallbackTitle: t.title),
                        if (t.rating != null) Positioned(top: DS.s8, left: DS.s8, child: ImdbBadge(t.rating!)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DS.s12),
              Text(
                t.title,
                style: TvDS.tileName.copyWith(fontSize: 14, color: f ? TvDS.ink : TvDS.inkMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                [if (t.year != null) t.year!, TvMetro.cased(t.isTv ? 'Series' : 'Film')].join(' · '),
                style: TvDS.tileName.copyWith(fontSize: 12, color: TvDS.inkMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A poster / backdrop: the first of [urls] that loads (fetched through Android, decoded small —
/// TVs have little memory); a tinted title card while loading or when none does.
class ShowImage extends StatelessWidget {
  const ShowImage({super.key, required this.urls, this.decodeWidth = 400, this.fallbackTitle, this.alignment = Alignment.center});
  final List<String> urls;
  final int decodeWidth;
  final String? fallbackTitle;
  final Alignment alignment;

  /// The first picture that loads (each is cached, so a failed one isn't asked again).
  static Future<MemoryImage?> _first(List<String> urls, int width) async {
    for (final u in urls) {
      final m = await TvApps.instance.image(u, width: width).catchError((Object _) => null);
      if (m != null) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tvTint(fallbackTitle ?? ''), TvDS.canvas]),
      ),
      child: fallbackTitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(DS.s12),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(fallbackTitle!, style: TvDS.panelTitle.copyWith(fontSize: 17, height: 1.1), maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
            ),
    );
    if (urls.isEmpty || TvApps.demo) return fallback;
    // The best picture already here at this size: shown at once. A lesser one that's here (e.g. the
    // poster while the backdrop loads) holds the place until the best one arrives.
    final best = TvApps.instance.imageNow(urls.first, width: decodeWidth);
    if (best != null) return Image(image: best, fit: BoxFit.cover, alignment: alignment, gaplessPlayback: true);
    final meanwhile = urls.skip(1).map((u) => TvApps.instance.imageNow(u, width: decodeWidth)).nonNulls.firstOrNull;
    return FutureBuilder<MemoryImage?>(
      future: _first(urls, decodeWidth),
      initialData: meanwhile,
      builder: (context, s) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: s.data == null
            ? KeyedSubtree(key: const ValueKey(0), child: fallback)
            : Image(key: ValueKey(s.data), image: s.data!, fit: BoxFit.cover, alignment: alignment, gaplessPlayback: true),
      ),
    );
  }
}

// ---- Details page ---------------------------------------------------------------

/// A show or film, cinematic: backdrop; kind · year · runtime · genres; title; the critics' scores
/// (IMDb, Rotten Tomatoes, Metacritic — only the ones there are); plot; where to watch (open it in
/// its app on this TV), Open in Nuvio, trailer; reviews (OK opens one whole); cast. Details from the
/// catalog sources (Cinemeta first); where to watch from WatchHub; scores from OMDb and reviews
/// from TMDB when the build has their keys (ratings.dart).
class TvTitlePage extends StatefulWidget {
  const TvTitlePage({super.key, required this.title, required this.apps, required this.searchTargets, required this.onOpenApp});
  final ShowTitle title;
  final List<AppEntry> apps;
  final List<String> searchTargets; // apps that accept a search → we can jump to the title
  final void Function(AppEntry app) onOpenApp; // records "Jump back in" too

  @override
  State<TvTitlePage> createState() => _TvTitlePageState();
}

/// One "watch" button: the app, and WatchHub's link when there is one (else the app's own search).
typedef _Watch = ({AppEntry app, ShowLink? link});

class _TvTitlePageState extends State<TvTitlePage> {
  ShowDetails? _details;
  Object? _detailsError;
  List<ShowLink> _links = const [];
  Object? _linksError;
  bool _linksDone = false;
  List<(String, String)> _openers = const []; // apps that open stremio:///detail/… (Nuvio)
  // Focus starts on "Search everywhere" (always there); when the Watch on … buttons arrive and the
  // remote hasn't been touched yet, it moves to the first of them.
  final _everywhere = FocusNode(debugLabel: 'everywhere'), _firstWatch = FocusNode(debugLabel: 'watch');
  bool _moved = false; // a key was pressed on this page
  OneStreamTitle? _stream; // One Stream's row for this title (its progress, when started there)
  TitleRatings? _ratings; // Rotten Tomatoes, Metacritic (and IMDb when the catalog has none)
  ShowReviews? _reviews;
  // Series: the season shown, each shown season's episode scores (OMDb) and TMDB's fill-ins.
  int? _season;
  final _episodeRatings = <int, Map<int, double>>{};
  final _tmdbEpisodes = <int, List<ShowEpisode>>{};

  @override
  void initState() {
    super.initState();
    final t = widget.title;
    // Scores and reviews: asked once per page (kept on the TV for a week); the page never waits.
    TitleExtras.instance.ratings(t).then((r) => _update(() => _ratings = r));
    TitleExtras.instance.reviews(t).then((r) => _update(() => _reviews = r));
    Catalog.instance
        .details(t)
        .then(
          (d) {
            _update(() => _details = d);
            if (d.seasonNumbers.isNotEmpty) _showSeason(d.seasonNumbers.first);
          },
          onError: (Object e) {
            debugPrint('Title details: ${e is CatalogException ? e : e.runtimeType}'); // addon names only, never links
            _update(() => _detailsError = e);
          },
        );
    // "Search everywhere" is there at once; the Watch on … buttons join ahead of it when WatchHub
    // answers (that can take a while on a slow network — the page stays usable meanwhile).
    Catalog.instance
        .whereToWatch(t)
        .then<void>(
          (l) {
            _links = l;
          },
          onError: (Object e) {
            _linksError = e;
          },
        )
        .whenComplete(() {
          _update(() => _linksDone = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_moved && _everywhere.hasPrimaryFocus && _firstWatch.context != null) _firstWatch.requestFocus();
          });
        });
    // One Stream: "Play in One Stream" from the IMDb id; "Resume … · 12 min left" once it's started.
    if (_inStream) OneStream.instance.titleFor(t.id, t.isTv ? 'tv' : 'movie').then((s) => _update(() => _stream = s));
    TvApps.instance.linkHandlers(Catalog.detailLink(t)).then<void>((o) => _update(() => _openers = o), onError: (Object _) {});
  }

  @override
  void dispose() {
    _everywhere.dispose();
    _firstWatch.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  // ---- The rows (season tabs, episodes, reviews): ↑ / ↓ enter a row at its chosen tab or the card
  // last on, never at whichever card happens to sit nearest. ----

  final _nodes = <String, FocusNode>{}; // 'season:2', 'episode:2:5', 'review:0'
  int? _lastEpisode; // in the season shown
  int _lastReview = 0;

  FocusNode _node(String key) => _nodes.putIfAbsent(key, () => FocusNode(debugLabel: key));

  /// The row a node is in: 'season', 'episode', 'review' — null for the buttons, cast…
  String? _rowOf(FocusNode? n) {
    if (n == null) return null;
    for (final e in _nodes.entries) {
      if (identical(e.value, n)) return e.key.split(':').first;
    }
    return null;
  }

  List<String> get _rows => [
    if (_season != null && (_details?.seasonNumbers.isNotEmpty ?? false)) ...['season', 'episode'],
    if (_reviews?.list.isNotEmpty ?? false) 'review',
  ];

  FocusNode? _entry(String row) => switch (row) {
    'season' => _node('season:$_season'),
    'episode' => switch (_episodes(_season ?? 0)) {
      final eps when eps.isNotEmpty => _node('episode:$_season:${_lastEpisode ?? eps.first.episode}'),
      _ => null,
    },
    'review' => _node('review:$_lastReview'),
    _ => null,
  };

  KeyEventResult _onPageKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent) _moved = true;
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final dir = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      _ => null,
    };
    final from = FocusManager.instance.primaryFocus;
    if (dir == null || from == null) return KeyEventResult.ignored;
    final rows = _rows, was = _rowOf(from);
    // Leaving a row: remember the card it was on, to come back to.
    final key = _nodes.entries.where((e) => identical(e.value, from)).firstOrNull?.key.split(':');
    if (was == 'episode') _lastEpisode = int.tryParse(key!.last);
    if (was == 'review') _lastReview = int.tryParse(key!.last) ?? 0;
    String? target;
    if (was != null) {
      // Row to row in order; past the first / last row, the page's own ↑ / ↓ (buttons, cast).
      final i = rows.indexOf(was) + (dir == TraversalDirection.down ? 1 : -1);
      if (i >= 0 && i < rows.length) target = rows[i];
    }
    if (target != null) {
      _enter(target);
      return KeyEventResult.handled;
    }
    if (!from.focusInDirection(dir)) return KeyEventResult.handled;
    // Focus moves at the end of this turn: then, if it landed in the rows from outside them, enter
    // the first row going down, the last going up.
    scheduleMicrotask(() {
      final now = _rowOf(FocusManager.instance.primaryFocus);
      if (mounted && now != null && now != was && rows.isNotEmpty) _enter(dir == TraversalDirection.down ? rows.first : rows.last);
    });
    return KeyEventResult.handled;
  }

  void _enter(String row) {
    final entry = _entry(row);
    if (entry?.context == null) return;
    entry!.requestFocus();
    Scrollable.ensureVisible(entry.context!, alignment: .5, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  }

  void _update(VoidCallback f) {
    if (mounted) setState(f);
  }

  /// Watch on an app: WatchHub's deep link into the title; if that doesn't open, the app's own
  /// search for it, else just the app.
  Future<void> _watch(_Watch w) async {
    final l = w.link;
    if (l != null && await TvApps.instance.openLink(l.tvUrl ?? l.webUrl!, package: w.app.package, fallback: l.webUrl)) return;
    if (widget.searchTargets.contains(w.app.package)) {
      TvApps.instance.searchIn(w.app.package, widget.title.title);
    } else {
      widget.onOpenApp(w.app);
    }
  }

  /// Shows a season's episodes, then asks (once, only now) for their IMDb scores — and TMDB for
  /// stills / plots Cinemeta doesn't have.
  void _showSeason(int season) {
    _update(() {
      if (_season != season) _lastEpisode = null;
      _season = season;
    });
    final t = widget.title;
    if (!_episodeRatings.containsKey(season)) {
      TitleExtras.instance.episodeRatings(t, season).then((r) {
        if (r != null) _update(() => _episodeRatings[season] = r);
      });
    }
    final eps = _details?.episodesOf(season) ?? const <ShowEpisode>[];
    if (!_tmdbEpisodes.containsKey(season) && eps.any((e) => e.still == null || e.overview == null)) {
      TitleExtras.instance.tmdbSeason(t, season).then((r) {
        if (r != null) _update(() => _tmdbEpisodes[season] = r);
      });
    }
  }

  /// The season's episodes, Cinemeta's filled in from TMDB's.
  List<ShowEpisode> _episodes(int season) {
    final eps = _details?.episodesOf(season) ?? const <ShowEpisode>[];
    final more = {for (final e in _tmdbEpisodes[season] ?? const <ShowEpisode>[]) e.episode: e};
    return [for (final e in eps) more[e.episode] == null ? e : e.filledFrom(more[e.episode]!)];
  }

  bool get _inStream => OneStream.instance.available.value && widget.title.id.startsWith('tt');

  AppEntry? _installed(String package) => widget.apps.where((a) => a.package == package).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final t = _details?.title ?? widget.title;
    return Scaffold(
      backgroundColor: TvDS.canvas,
      body: LayoutBuilder(
        builder: (context, c) => Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              right: 0,
              width: c.maxWidth * .78,
              height: c.maxHeight * .86,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.06, end: 1),
                duration: const Duration(milliseconds: 2200),
                curve: Curves.easeOutCubic,
                builder: (context, s, child) => Transform.scale(scale: s, alignment: Alignment.topRight, child: child),
                child: ShowImage(urls: [...t.backdrops, ...t.posters], decodeWidth: 1280, alignment: Alignment.topCenter),
              ),
            ),
            const TvScrims(),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(TvDS.safe.left, 64, TvDS.safe.right, TvDS.safe.bottom + DS.s24),
              child: Focus(
                skipTraversal: true,
                onKeyEvent: _onPageKey,
                child: FocusTraversalGroup(child: _body(t)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ShowTitle t) {
    final d = _details;
    // The eyebrow: FILM · 2024 · 2h 8m · DRAMA, MYSTERY (series: seasons instead of the runtime).
    final runtime = d?.runtime != null && d!.runtime! > 0 ? '${d.runtime! ~/ 60 > 0 ? '${d.runtime! ~/ 60}h ' : ''}${d.runtime! % 60}m' : null;
    final genres = (d?.genres ?? t.genres).take(3).join(', ');
    final eyebrow = [
      t.isTv ? 'Series' : 'Film',
      ?t.year,
      ?runtime,
      if (d?.seasons != null) '${d!.seasons} ${d.seasons == 1 ? 'season' : 'seasons'}',
      if (genres.isNotEmpty) genres,
    ];
    final reviews = _reviews?.list ?? const <ShowReview>[];

    // Where to watch: WatchHub's services with an app here (buttons), the rest listed underneath.
    final watch = <_Watch>[];
    final elsewhere = <ShowLink>[];
    bool shown(String package) => watch.any((w) => w.app.package == package);
    for (final l in _links) {
      final app = (l.package == null ? null : _installed(l.package!)) ?? appForService(l.service, widget.apps);
      if (app == null) {
        elsewhere.add(l);
      } else if (!shown(app.package)) {
        watch.add((app: app, link: l));
      }
    }
    // Services whose catalogs list it (e.g. Netflix's), when WatchHub didn't link them: the app's search.
    final searchable = <AppEntry>[
      for (final s in t.services) ?appForService(s, widget.apps),
      for (final p in widget.searchTargets)
        if (p != 'com.android.vending') ?_installed(p),
    ];
    final searchIn = <AppEntry>[];
    for (final a in searchable) {
      if (!shown(a.package) && !searchIn.any((x) => x.package == a.package)) searchIn.add(a);
    }

    final hub = Catalog.instance.watchSourceName;
    final dataFrom = {
      ?d?.source,
      if (_linksDone && hub != null) hub,
      if (_ratings?.rottenTomatoes != null || _ratings?.metascore != null || _episodeRatings.values.any((m) => m.isNotEmpty)) 'OMDb',
      if (reviews.isNotEmpty) 'TMDB',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tiles: the eyebrow in Metro's accent and case; the title big and light.
              TvMetro.on
                  ? Text(TvMetro.cased(eyebrow.join(' · ')), style: TvMetro.header.copyWith(fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis)
                  : Text(
                      [for (final e in eyebrow) identical(e, runtime) ? e : e.toUpperCase()].join(' · '),
                      style: TvDS.heroEyebrow,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              const SizedBox(height: DS.s8),
              Text(t.title, style: TvMetro.on ? TvMetro.title(size: 44) : TvDS.heroTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: DS.s16),
              // The scores there are (IMDb from the catalog, the rest from OMDb), then the series' status.
              RatingsRow(
                imdb: t.rating,
                ratings: _ratings,
                trailing: [if (d?.status != null) _Chip(label: TvMetro.cased(d!.status!))],
              ),
              if (t.overview != null) ...[
                const SizedBox(height: DS.s16),
                Text(t.overview!, style: TvDS.heroBody, maxLines: 3, overflow: TextOverflow.ellipsis),
              ] else if (_detailsError != null) ...[
                const SizedBox(height: DS.s16),
                Text(
                  _detailsError is CatalogException && (_detailsError as CatalogException).status == -1
                      ? 'Couldn’t load the details. Check the TV’s internet.'
                      : 'No details for this one yet.',
                  style: TvDS.heroBody,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: DS.s24),

        // ---- Where to watch: the actions, right under the plot ----
        Wrap(
          spacing: DS.s12,
          runSpacing: DS.s12,
          children: [
            // One Stream first (the user's own app): play, or pick up where it was left.
            if (_inStream)
              TvActionPill(
                key: const ValueKey('onestream'),
                focusNode: _firstWatch,
                leading: _installed(OneStream.package) == null
                    ? null
                    : SizedBox(width: 40, height: 22.5, child: TvAppArt(app: _installed(OneStream.package)!, width: 40)),
                icon: Icons.play_arrow_rounded,
                label: _stream?.hasProgress == true ? ['Resume in One Stream', ?_stream!.left].join(' · ') : 'Play in One Stream',
                onSelect: () => OneStream.instance.open(_stream?.hasProgress == true ? _stream!.link : OneStream.imdbLink(t.id, t.isTv ? 'tv' : 'movie')),
              ),
            // …and its page here (episodes, sources, watchlist, download), when One Stream knows it.
            if (_stream?.tmdb != null)
              TvActionPill(
                key: const ValueKey('onestream:more'),
                icon: Icons.read_more_rounded,
                label: 'More in One Stream',
                onSelect: () => Navigator.of(context).push(tvFade(TvOneStreamPage(title: _stream!))),
              ),
            // Keyed: buttons that arrive later never take over the focused one's place.
            for (final (i, w) in watch.indexed)
              TvActionPill(
                key: ValueKey('watch:${w.app.package}'),
                focusNode: i == 0 && !_inStream ? _firstWatch : null,
                leading: SizedBox(width: 40, height: 22.5, child: TvAppArt(app: w.app, width: 40)),
                label: 'Watch on ${w.app.label}',
                detail: w.link?.kind,
                onSelect: () => _watch(w),
              ),
            for (final (pkg, name) in _openers)
              TvActionPill(
                key: ValueKey('nuvio:$pkg'),
                leading: _installed(pkg) == null ? null : SizedBox(width: 40, height: 22.5, child: TvAppArt(app: _installed(pkg)!, width: 40)),
                icon: Icons.open_in_new_rounded,
                label: 'Open in $name',
                onSelect: () => TvApps.instance.openLink(Catalog.detailLink(t), package: pkg),
              ),
            if (d?.trailer != null)
              TvActionPill(
                key: const ValueKey('trailer'),
                icon: Icons.play_circle_outline_rounded,
                label: 'Trailer',
                onSelect: () => TvApps.instance.openUri('https://www.youtube.com/watch?v=${d!.trailer}', package: 'com.google.android.youtube.tv'),
              ),
            TvActionPill(
              key: const ValueKey('everywhere'),
              focusNode: _everywhere,
              autofocus: true,
              icon: Icons.travel_explore_rounded,
              label: 'Search everywhere',
              onSelect: () => TvApps.instance.searchEverywhere(t.title),
            ),
            for (final a in searchIn.take(3))
              TvActionPill(
                key: ValueKey('search:${a.package}'),
                leading: SizedBox(width: 40, height: 22.5, child: TvAppArt(app: a, width: 40)),
                label: widget.searchTargets.contains(a.package) ? 'Search in ${a.label}' : 'Open ${a.label}',
                onSelect: () => _watch((app: a, link: null)),
              ),
          ],
        ),
        const SizedBox(height: DS.s12),
        Text(
          !_linksDone
              ? TvMetro.cased('Finding where it’s streaming…')
              : _linksError != null
              ? 'Couldn’t reach ${hub ?? 'WatchHub'}. Check the TV’s internet.'
              : _links.isEmpty
              ? (hub == null ? 'Turn on WatchHub (Customise → Search → Sources) to see where it’s streaming.' : 'No streaming links for this one yet.')
              : elsewhere.isEmpty
              ? ''
              : 'Also on ${elsewhere.take(5).map((l) => l.kind == null ? l.service : '${l.service} (${l.kind!.toLowerCase()})').join(', ')}',
          style: TvDS.heroBody.copyWith(fontSize: 13),
        ),

        // ---- Series: season tabs, then that season's episodes ----
        if (d != null && _season != null && d.seasonNumbers.isNotEmpty) ...[
          const SizedBox(height: DS.s24),
          SingleChildScrollView(
            key: const ValueKey('seasons'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final (i, n) in d.seasonNumbers.indexed) ...[
                  if (i > 0) const SizedBox(width: DS.s12),
                  TvSeasonTab(
                    key: ValueKey('season:$n'),
                    focusNode: _node('season:$n'),
                    label: 'Season $n',
                    selected: n == _season,
                    onSelect: () => _showSeason(n),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: DS.s16),
          SingleChildScrollView(
            key: ValueKey('episodes:$_season'), // a new season starts at its first episode
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, e) in _episodes(_season!).indexed) ...[
                  if (i > 0) const SizedBox(width: DS.s20),
                  TvEpisodeCard(
                    key: ValueKey('episode:${e.season}:${e.episode}'),
                    focusNode: _node('episode:${e.season}:${e.episode}'),
                    episode: e,
                    rating: _episodeRatings[_season]?[e.episode],
                    runtime: d.episodeRuntime,
                  ),
                ],
              ],
            ),
          ),
        ],

        // ---- Reviews (TMDB): a row of cards; OK opens one whole ----
        if (reviews.isNotEmpty) ...[
          const SizedBox(height: DS.s24),
          Text('${TvMetro.cased('Reviews')} · ${_reviews!.total}', style: TvMetro.headerOr(TvDS.rowTitleFocused)),
          const SizedBox(height: DS.s12),
          SingleChildScrollView(
            key: const ValueKey('reviews'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, r) in reviews.indexed) ...[
                  if (i > 0) const SizedBox(width: DS.s16),
                  TvReviewCard(
                    focusNode: _node('review:$i'),
                    review: r,
                    onSelect: () => Navigator.of(context).push(tvFade(TvReviewPage(review: r, title: t.title))),
                  ),
                ],
              ],
            ),
          ),
        ],

        // ---- Cast ----
        if (d?.cast.isNotEmpty ?? false) ...[
          const SizedBox(height: DS.s24),
          Text(TvMetro.cased('Cast'), style: TvMetro.headerOr(TvDS.rowTitleFocused)),
          const SizedBox(height: DS.s12),
          SizedBox(
            height: 150,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, p) in d!.cast.indexed) ...[if (i > 0) const SizedBox(width: DS.s20), _CastCard(person: p)],
                ],
              ),
            ),
          ),
        ],
        if (dataFrom.isNotEmpty) ...[
          const SizedBox(height: DS.s12),
          Text(
            'Data: ${dataFrom.join(' · ')}',
            style: const TextStyle(fontFamily: DS.font, fontSize: 11, color: TvDS.inkMuted),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: TvMetro.corners(6),
      border: Border.all(color: TvDS.inkMuted),
    ),
    child: Text(label, style: TvDS.keycap),
  );
}

/// Initials disc, name, role. Focusable so the remote can scroll through the cast.
class _CastCard extends StatelessWidget {
  const _CastCard({required this.person});
  final ShowPerson person;

  /// "Mira Rao" → "MR".
  static String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final a = parts.first.characters.first;
    return parts.length == 1 ? a.toUpperCase() : '$a${parts.last.characters.first}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => TvFocusable(
    builder: (context, f) => SizedBox(
      width: 96,
      child: Column(
        children: [
          AnimatedScale(
            scale: f ? 1.1 : 1,
            duration: Motion.popDuration,
            curve: Motion.pop,
            child: Container(
              width: 80,
              height: 80,
              // Tiles: an accent square with the tile corners and the Metro frame; else a disc.
              decoration: TvMetro.on
                  ? BoxDecoration(borderRadius: TvMetro.corners(0), color: TvMetro.tileFill, boxShadow: TvMetro.glow(f))
                  : BoxDecoration(
                      shape: BoxShape.circle,
                      color: f ? TvDS.surfaceFocused : tvTint(person.name).withValues(alpha: .55),
                      border: Border.all(color: f ? TvDS.surfaceFocused : Colors.transparent, width: TvDS.focusRing),
                    ),
              foregroundDecoration: TvMetro.on ? TvMetro.frame(f) : null,
              alignment: Alignment.center,
              child: Text(
                _initials(person.name),
                style: TvMetro.on
                    ? TvDS.panelTitle.copyWith(fontWeight: FontWeight.w300, color: Colors.white)
                    : TvDS.panelTitle.copyWith(color: f ? TvDS.onLight : TvDS.ink),
              ),
            ),
          ),
          const SizedBox(height: DS.s8),
          Text(
            person.name,
            style: TvDS.tileName.copyWith(color: f ? TvDS.ink : TvDS.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (person.role != null)
            Text(
              person.role!,
              style: TvDS.tileName.copyWith(fontSize: 11, color: TvDS.inkMuted, fontWeight: FontWeight.w400),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
        ],
      ),
    ),
  );
}
