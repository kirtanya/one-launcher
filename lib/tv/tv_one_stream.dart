import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../one_stream.dart';
import '../ui/ds.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';
import 'tv_metro.dart';
import 'tv_parts.dart';
import 'tv_title.dart' show ShowImage;

/// A One Stream title as a TV page, inside One Launcher, drawn like One Stream's own TV title +
/// sources screens: pure black, backdrop top-right fading out, details line, Play / Resume +
/// watchlist / download / prepare pills, (series) season tabs and episode cards, the sources
/// (recommended card, quality / type chips, rows) and downloads — One Stream opens only when
/// something plays. Focus never scales (rings and fills only).
class TvOneStreamPage extends StatefulWidget {
  const TvOneStreamPage({super.key, required this.title});
  final OneStreamTitle title;

  @override
  State<TvOneStreamPage> createState() => _TvOneStreamPageState();
}

class _TvOneStreamPageState extends State<TvOneStreamPage> {
  OneStream get os => OneStream.instance;
  OneStreamTitle get t => _details?.title ?? widget.title;
  int get tmdb => widget.title.tmdb!;
  String get type => widget.title.type;
  bool get tv => widget.title.isTv;

  OneStreamDetails? _details;
  bool _detailsDone = false;
  bool _inWatchlist = false;
  int _season = 1;
  List<OneStreamEpisode>? _episodes;
  OneStreamEpisode? _episode;
  Future<List<OneStreamSource>>? _sourcesFuture;
  List<OneStreamSource>? _sources;
  List<OneStreamDownload> _downloads = const [];
  Timer? _poll;
  String? _note;
  String? _fQuality, _fKind; // the sources' filter chips

  @override
  void initState() {
    super.initState();
    // Play is likely next: One Stream's engine stops itself when idle, so wake it now.
    os.warmEngine();
    if (widget.title.tmdb == null) {
      _detailsDone = true;
      return;
    }
    os.details(type, tmdb).then((d) {
      if (!mounted) return;
      setState(() {
        _details = d;
        _detailsDone = true;
        _inWatchlist = d?.inWatchlist ?? false;
      });
    });
    tv ? _loadSeason(1) : _loadSources();
    _loadDownloads();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSeason(int season) async {
    setState(() {
      _season = season;
      _episodes = null;
    });
    final list = await os.episodes(tmdb, season);
    if (!mounted || _season != season) return;
    setState(() => _episodes = list);
    if (_episode == null || _episode!.season != season) {
      final next =
          list.where((e) => e.progress > 0 && e.progress < .95).firstOrNull ??
          list.where((e) => e.aired && e.progress < .9).firstOrNull ??
          list.firstOrNull;
      if (next != null) _pick(next);
    }
  }

  void _pick(OneStreamEpisode e) {
    setState(() => _episode = e);
    _loadSources();
  }

  void _loadSources() {
    final e = _episode;
    final f = os.sources(type, tmdb, season: e?.season, episode: e?.episode);
    setState(() {
      _sourcesFuture = f;
      _sources = null;
      _fQuality = _fKind = null;
    });
    f.then((list) {
      if (mounted && _sourcesFuture == f) setState(() => _sources = list);
    });
  }

  Future<void> _loadDownloads() async {
    final all = await os.downloads();
    if (!mounted) return;
    final mine = [
      for (final d in all)
        if (d.title.toLowerCase() == widget.title.title.toLowerCase()) d,
    ];
    setState(() => _downloads = mine);
    _poll?.cancel();
    if (mine.any((d) => !d.done)) _poll = Timer(const Duration(seconds: 3), _loadDownloads);
  }

  void _say(String text) => setState(() => _note = text);
  void _reply(OneStreamReply r, String ok, String failed) => _say(r.message ?? (r.ok ? ok : failed));

  Future<OneStreamSource?> _best({bool download = false}) async {
    if (_sourcesFuture == null) return null;
    if (_sources == null) _say('Finding the best source…');
    final list = await _sourcesFuture!;
    final pool = download ? list.where((s) => s.downloadable).toList() : list;
    return pool.where((s) => s.best).firstOrNull ?? pool.firstOrNull;
  }

  Future<void> _play() async {
    if (widget.title.tmdb == null) {
      os.open(widget.title.link);
      return;
    }
    final resume = _details?.resumeLink;
    if (resume != null && _episode == null) {
      os.open(resume);
      return;
    }
    if (tv && _episode == null) return _say('Pick an episode first');
    final s = await _best();
    if (!mounted) return;
    if (s == null) return _say('No sources found');
    _playSource(s);
  }

  void _playSource(OneStreamSource s) => os.open(OneStream.playLink(s, type, tmdb, season: _episode?.season, episode: _episode?.episode));

  Future<void> _download([OneStreamSource? source]) async {
    final s = source ?? await _best(download: true);
    if (!mounted) return;
    if (s == null) return _say('Nothing here can be downloaded');
    _reply(await os.download(s.token), 'Download started', 'Couldn’t start the download');
    _loadDownloads();
  }

  Future<void> _prepare([OneStreamSource? source]) async {
    final s = source ?? await _best();
    if (!mounted) return;
    if (s == null) return _say('No sources found');
    _reply(await os.prepare(s.token), 'Getting it ready to stream', 'Couldn’t prepare it');
  }

  Future<void> _toggleWatchlist() async {
    final add = !_inWatchlist;
    setState(() => _inWatchlist = add);
    final r = await os.setWatchlist(add, type, tmdb);
    if (!mounted) return;
    if (!r.ok) setState(() => _inWatchlist = !add);
    _reply(r, add ? 'Added to your watchlist' : 'Removed from your watchlist', 'Couldn’t change your watchlist');
  }

  void _sourceMenu(OneStreamSource s) => showTvPanel(
    context,
    title: s.detail.isEmpty ? s.label : '${s.label} · ${s.detail}',
    actions: [
      TvAction(Icons.play_arrow_rounded, 'Play', () => _playSource(s)),
      if (s.downloadable) TvAction(Icons.download_rounded, 'Download', () => _download(s)),
      TvAction(Icons.bolt_rounded, 'Prepare to stream', () => _prepare(s)),
    ],
  );

  // ---- Focus: rows. ↑ / ↓ go row to row (landing on the card last on, or the chosen season /
  // episode), ← / → step inside a row; each move scrolls the page so what's focused is in view. ----

  static const _rowOrder = ['act', 'season', 'ep', 'best', 'filter', 'src', 'dl'];
  final _scroll = ScrollController();
  final _nodes = <String, FocusNode>{}; // 'act:play', 'season:2', 'ep:1:3', 'src:<token>' …
  final _layout = <String, List<String>>{}; // row → its nodes' keys, left to right (rebuilt each build)
  final _last = <String, String>{}; // row → the node last on

  FocusNode _node(String row, String id) {
    final key = '$row:$id';
    (_layout[row] ??= []).add(key);
    return _nodes.putIfAbsent(key, () => FocusNode(debugLabel: key));
  }

  String? _keyOf(FocusNode? n) => n == null ? null : _nodes.entries.where((e) => identical(e.value, n)).firstOrNull?.key;

  void _reveal(String row, FocusNode n) {
    n.requestFocus();
    if (row == 'act') {
      // The first row: bring the whole top (title, story) back — scrolling only the buttons into view left it half up.
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    } else if (n.context != null) {
      Scrollable.ensureVisible(n.context!, alignment: .5, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
    }
  }

  String? _entry(String row) {
    final keys = _layout[row];
    if (keys == null || keys.isEmpty) return null;
    return switch (row) {
      'season' => keys.contains('season:$_season') ? 'season:$_season' : keys.first,
      'ep' => keys.contains(_last['ep']) ? _last['ep'] : (keys.contains('ep:${_episode?.season}:${_episode?.episode}') ? 'ep:${_episode!.season}:${_episode!.episode}' : keys.first),
      _ => keys.contains(_last[row]) ? _last[row] : keys.first,
    };
  }

  KeyEventResult _onPageKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final vertical = k == LogicalKeyboardKey.arrowDown ? 1 : (k == LogicalKeyboardKey.arrowUp ? -1 : 0);
    final sideways = k == LogicalKeyboardKey.arrowRight ? 1 : (k == LogicalKeyboardKey.arrowLeft ? -1 : 0);
    final from = _keyOf(FocusManager.instance.primaryFocus);
    if ((vertical == 0 && sideways == 0) || from == null) return KeyEventResult.ignored;
    final row = from.split(':').first;
    if (sideways != 0) {
      final keys = _layout[row] ?? const <String>[], i = keys.indexOf(from) + sideways;
      if (i >= 0 && i < keys.length) _reveal(row, _nodes[keys[i]]!);
      return KeyEventResult.handled; // even at an edge: no jumping to another row
    }
    _last[row] = from;
    if (row == 'src') {
      // The sources are a column: ↑ / ↓ step through them before leaving the list.
      final keys = _layout[row]!, j = keys.indexOf(from) + vertical;
      if (j >= 0 && j < keys.length) {
        _reveal(row, _nodes[keys[j]]!);
        return KeyEventResult.handled;
      }
    }
    final rows = [for (final r in _rowOrder) if (_layout[r]?.isNotEmpty ?? false) r];
    final i = rows.indexOf(row) + vertical;
    if (i >= 0 && i < rows.length) {
      final key = _entry(rows[i]);
      if (key != null) _reveal(rows[i], _nodes[key]!);
    }
    return KeyEventResult.handled;
  }

  // ---- Pieces ----

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(top: DS.s24, bottom: DS.s12),
    child: Text(TvMetro.cased(text), style: TvMetro.headerOr(TvDS.panelTitle.copyWith(fontSize: 20))),
  );

  Widget _quiet(String text) => Text(TvMetro.cased(text), style: TvDS.heroBody);

  /// A row that scrolls sideways (its focus rings may spill out of it).
  Widget _scrolling(List<Widget> children, {double gap = DS.s12, CrossAxisAlignment align = CrossAxisAlignment.center}) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: Row(
      crossAxisAlignment: align,
      children: [for (final (i, w) in children.indexed) ...[if (i > 0) SizedBox(width: gap), w]],
    ),
  );

  /// Quality bucket as One Stream's chips group them.
  static String _bucket(OneStreamSource s) {
    final q = s.quality?.toLowerCase() ?? '';
    if (q.contains('2160') || q == '4k') return '4K';
    if (q.contains('1080')) return '1080p';
    if (q.contains('720')) return '720p';
    return 'SD';
  }

  static String? _kindOf(OneStreamSource s) => switch (s.kind?.toLowerCase()) {
    null || '' => null,
    'torrent' => 'Torrent',
    'stream' || 'direct' => 'Direct',
    final k => k[0].toUpperCase() + k.substring(1),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _black,
      body: LayoutBuilder(
        builder: (context, c) => Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              right: 0,
              width: c.maxWidth * .78,
              height: c.maxHeight * .86,
              child: ShowImage(urls: [?t.backdrop, ?t.poster], decodeWidth: 1280, alignment: Alignment.topCenter),
            ),
            const _BlackFade(),
            SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(TvDS.safe.left, 64, TvDS.safe.right, TvDS.safe.bottom + DS.s24),
              child: Focus(
                skipTraversal: true,
                onKeyEvent: _onPageKey,
                child: FocusTraversalGroup(child: _body()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    _layout.clear();
    final d = _details;
    final resume = d?.resumeLink != null && _episode == null;
    final hasTmdb = widget.title.tmdb != null;
    final mins = d?.runtimeMin ?? 0;
    final seasons = d?.seasons ?? 0;
    // SERIES · 2024 · 2 SEASONS · DRAMA, SCI-FI (film: the runtime instead of seasons)
    final details = [
      tv ? 'Series' : 'Film',
      ?t.year?.toString(),
      if (!tv && mins > 0) mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m',
      if (tv && seasons > 0) '$seasons ${seasons == 1 ? 'season' : 'seasons'}',
      ?d?.genres,
    ].join(' · ').toUpperCase();
    final rating = t.rating != null && t.rating! > 0 ? t.rating! : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.title, style: TvMetro.on ? TvMetro.title(size: 44) : TvDS.heroTitle.copyWith(fontSize: 44), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: DS.s12),
              Text(details, style: TvDS.heroMeta.copyWith(fontSize: 14, letterSpacing: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (rating != null) ...[const SizedBox(height: DS.s12), _Rating(rating)],
              if (d?.overview != null) ...[
                const SizedBox(height: DS.s12),
                Text(d!.overview!, style: TvDS.heroBody, maxLines: 3, overflow: TextOverflow.ellipsis),
              ] else if (!_detailsDone) ...[
                const SizedBox(height: DS.s12),
                _quiet('Loading…'),
              ],
            ],
          ),
        ),
        const SizedBox(height: DS.s20),
        _scrolling([
          _Pill(
            key: const ValueKey('play'),
            focusNode: _node('act', 'play'),
            autofocus: true,
            primary: true,
            icon: Icons.play_arrow_rounded,
            label: resume ? 'Resume' : (tv && _episode != null ? 'Play S${_episode!.season} ${_episode!.code}' : 'Play'),
            detail: resume && d!.resumeProgress > 0 ? '${(d.resumeProgress * 100).round()}%' : null,
            onSelect: _play,
          ),
          if (hasTmdb) ...[
            _Pill(
              key: const ValueKey('watchlist'),
              focusNode: _node('act', 'watchlist'),
              icon: _inWatchlist ? Icons.check_rounded : Icons.add_rounded,
              label: _inWatchlist ? 'In watchlist' : 'Add to watchlist',
              onSelect: _toggleWatchlist,
            ),
            _Pill(key: const ValueKey('download'), focusNode: _node('act', 'download'), icon: Icons.download_rounded, label: 'Download', onSelect: () => _download()),
            _Pill(key: const ValueKey('prepare'), focusNode: _node('act', 'prepare'), icon: Icons.bolt_rounded, label: 'Prepare to stream', onSelect: () => _prepare()),
          ],
        ]),
        if (_note != null) ...[const SizedBox(height: DS.s12), Text(TvMetro.cased(_note!), style: TvDS.heroMeta)],

        // ---- Episodes ----
        if (tv && hasTmdb) ...[
          _header('Episodes'),
          if (seasons > 1) ...[
            // The tabs' own padding sits left of the text: pull the first one back so its text lines up with the page's.
            Transform.translate(
              offset: const Offset(-DS.s12, 0),
              child: _scrolling([
                for (var s = 1; s <= seasons; s++)
                  _SeasonTab(key: ValueKey('season:$s'), focusNode: _node('season', '$s'), label: 'Season $s', selected: _season == s, onSelect: () => _loadSeason(s)),
              ], gap: DS.s8),
            ),
            const SizedBox(height: DS.s16),
          ],
          if (_episodes == null)
            _quiet('Loading episodes…')
          else if (_episodes!.isEmpty)
            _quiet('No episodes listed')
          else
            _scrolling([
              for (final e in _episodes!)
                _EpisodeCard(
                  key: ValueKey('ep:${e.season}:${e.episode}'),
                  focusNode: _node('ep', '${e.season}:${e.episode}'),
                  episode: e,
                  selected: _episode?.episode == e.episode && _episode?.season == e.season,
                  onSelect: () => e.aired ? _pick(e) : _say('Not out yet'),
                ),
            ], gap: DS.s20, align: CrossAxisAlignment.start),
        ],

        // ---- Sources ----
        if (hasTmdb) ..._sourcesSection(),

        // ---- Downloads ----
        if (_downloads.isNotEmpty) ...[
          _header('Downloads'),
          _scrolling([
            for (final dl in _downloads)
              _Pill(
                key: ValueKey('dl:${dl.key}'),
                focusNode: _node('dl', dl.key),
                icon: dl.done ? Icons.download_done_rounded : Icons.downloading_rounded,
                label: dl.subtitle ?? dl.title,
                detail: dl.detail,
                onSelect: () => dl.done && dl.playLink != null
                    ? os.open(dl.playLink!)
                    : showTvPanel(
                        context,
                        title: dl.subtitle ?? dl.title,
                        actions: [
                          TvAction(Icons.close_rounded, 'Cancel download', () async {
                            _reply(await os.cancelDownload(dl.key), 'Download cancelled', 'Couldn’t cancel it');
                            _loadDownloads();
                          }, danger: true),
                        ],
                      ),
              ),
          ]),
        ],
      ],
    );
  }

  /// One Stream's sources screen, as a section: the recommended source as a card, the quality /
  /// type chips, then the other sources as rows.
  List<Widget> _sourcesSection() {
    final all = _sources;
    final head = _header(tv && _episode != null ? 'Sources · S${_episode!.season} ${_episode!.code}' : 'Sources');
    if (_sourcesFuture == null) return [head, _quiet('Pick an episode to see its sources')];
    if (all == null) {
      return [
        head,
        Row(
          children: [
            const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: TvDS.inkMuted)),
            const SizedBox(width: DS.s12),
            _quiet('Looking for sources… this can take a few seconds'),
          ],
        ),
      ];
    }
    if (all.isEmpty) return [head, _quiet('No sources found')];

    final best = all.where((s) => s.best).firstOrNull ?? all.first;
    // Chips: the qualities and types there are, with how many each; tap = only those, again = all.
    final qualities = [
      for (final q in const ['4K', '1080p', '720p', 'SD'])
        if (all.any((s) => _bucket(s) == q)) (q, all.where((s) => _bucket(s) == q).length),
    ];
    final kinds = <String, int>{};
    for (final s in all) {
      if (_kindOf(s) case final k?) kinds[k] = (kinds[k] ?? 0) + 1;
    }
    final filtering = _fQuality != null || _fKind != null;
    final shown = [
      for (final s in all)
        if (!identical(s, best) && (_fQuality == null || _bucket(s) == _fQuality) && (_fKind == null || _kindOf(s) == _fKind)) s,
    ];
    return [
      head,
      Text('${all.length} ${all.length == 1 ? 'result' : 'results'}', style: TvDS.heroMeta),
      const SizedBox(height: DS.s12),
      _BestSource(
        key: ValueKey('src:${best.token}'),
        source: best,
        kind: _kindOf(best),
        playNode: _node('best', 'play'),
        moreNode: _node('best', 'more'),
        onPlay: () => _playSource(best),
        onMore: () => _sourceMenu(best),
      ),
      if (qualities.length + kinds.length > 1) ...[
        const SizedBox(height: DS.s16),
        _scrolling([
          for (final (q, n) in qualities)
            _Pill(
              key: ValueKey('q:$q'),
              focusNode: _node('filter', 'q:$q'),
              height: 40,
              chip: true,
              primary: _fQuality == q,
              label: '$q · $n',
              onSelect: () => setState(() => _fQuality = _fQuality == q ? null : q),
            ),
          for (final k in kinds.entries)
            _Pill(
              key: ValueKey('k:${k.key}'),
              focusNode: _node('filter', 'k:${k.key}'),
              height: 40,
              chip: true,
              primary: _fKind == k.key,
              label: '${k.key} · ${k.value}',
              onSelect: () => setState(() => _fKind = _fKind == k.key ? null : k.key),
            ),
          if (filtering)
            _Pill(
              key: const ValueKey('clear'),
              focusNode: _node('filter', 'clear'),
              height: 40,
              chip: true,
              icon: Icons.close_rounded,
              label: 'Clear',
              onSelect: () => setState(() => _fQuality = _fKind = null),
            ),
        ], gap: DS.s8),
      ],
      const SizedBox(height: DS.s12),
      if (shown.isEmpty && filtering) _quiet('No sources match'),
      for (final s in shown) ...[
        _SourceRow(key: ValueKey('src:${s.token}'), focusNode: _node('src', s.token), source: s, kind: _kindOf(s), onSelect: () => _sourceMenu(s)),
        const SizedBox(height: DS.s8),
      ],
    ];
  }
}

// ---- One Stream's look: black page, white primary pill, dark outlined pills / cards ----

const _black = Color(0xFF000000);
const _card = Color(0xFF111112); // sources, on the black page
const _pillFill = Color(0xFF1A1A1C);
const _outline = Color(0x2EFFFFFF); // the thin line round dark pills and cards
const _white = Color(0xFFFFFFFF);
const _onWhite = Color(0xFF161616);

/// The backdrop into black: from the left (behind the text) and from the bottom (behind the rows),
/// plus a light veil at the top. Drawn over the picture only; the page is black under it.
/// (A copy of tv_title.dart's page-local one.)
class _BlackFade extends StatelessWidget {
  const _BlackFade();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_black, _black.withValues(alpha: .94), _black.withValues(alpha: .4), _black.withValues(alpha: 0)],
              stops: const [0, .3, .55, .78],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_black.withValues(alpha: .35), _black.withValues(alpha: 0), _black.withValues(alpha: .85), _black],
              stops: const [0, .3, .68, .86],
            ),
          ),
        ),
      ],
    ),
  );
}

/// A pill button: white when primary (or chosen, for a chip), else dark with a thin outline and
/// white when focused; a white ring on focus either way. Never scales.
class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.onSelect,
    this.label,
    this.icon,
    this.detail,
    this.primary = false,
    this.chip = false,
    this.height = 48,
    this.width,
    this.focusNode,
    this.autofocus = false,
    this.semantics,
  });
  final String? label, detail, semantics;
  final IconData? icon;
  final VoidCallback onSelect;
  final bool primary, chip, autofocus;
  final double height;
  final double? width;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: chip ? primary : null,
    label: semantics ?? label,
    child: TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (context, f) {
        final light = primary || f;
        final ink = light ? _onWhite : _white;
        return Container(
          width: width,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : (chip ? DS.s16 : DS.s20)),
          alignment: Alignment.center,
          foregroundDecoration: TvRing(on: f, radius: height / 2),
          decoration: BoxDecoration(
            color: light ? _white : _pillFill,
            borderRadius: BorderRadius.circular(height / 2),
            border: light ? null : Border.all(color: _outline),
          ),
          child: label == null
              ? SizedBox.square(dimension: height, child: Icon(icon, size: 22, color: ink))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[Icon(icon, size: chip ? 18 : 22, color: ink), SizedBox(width: chip ? DS.s8 : DS.s12)],
                    Flexible(
                      child: Text(label!, style: TvDS.panelRow.copyWith(fontSize: chip ? 14 : 15, color: ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (detail != null) ...[
                      const SizedBox(width: DS.s8),
                      Text(detail!, style: TvDS.panelRow.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: light ? TvDS.onLightMuted : TvDS.inkMuted)),
                    ],
                  ],
                ),
        );
      },
    ),
  );
}

/// The title's score, quietly (One Stream's rating isn't named as IMDb's, so no IMDb badge).
class _Rating extends StatelessWidget {
  const _Rating(this.score);
  final double score;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: 3),
    decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(6)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF5C518)),
        const SizedBox(width: DS.s4),
        Text(score.toStringAsFixed(1), style: TvDS.panelRow.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

/// "Season 2": plain text, a short underline under the chosen season; a ring when focused.
class _SeasonTab extends StatelessWidget {
  const _SeasonTab({super.key, required this.label, required this.selected, required this.onSelect, required this.focusNode});
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: TvFocusable(
      focusNode: focusNode,
      onSelect: onSelect,
      builder: (context, f) => Container(
        padding: const EdgeInsets.fromLTRB(DS.s12, DS.s8, DS.s12, DS.s8),
        foregroundDecoration: TvRing(on: f, radius: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              TvMetro.cased(label),
              style: TvDS.panelRow.copyWith(fontSize: 17, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected || f ? _white : TvDS.inkMuted),
            ),
            const SizedBox(height: DS.s4),
            Container(width: 16, height: 2, color: selected ? _white : Colors.transparent),
          ],
        ),
      ),
    ),
  );
}

/// One episode: a 16:9 picture (a tint when it has none), "E1 · Name", progress / Watched / air
/// date, two lines of plot. The picked one is marked; one not out yet is dimmed.
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({super.key, required this.episode, required this.selected, required this.onSelect, required this.focusNode});
  final OneStreamEpisode episode;
  final bool selected;
  final VoidCallback onSelect;
  final FocusNode focusNode;

  static const w = 240.0, stillH = 135.0;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final status = !e.aired
        ? 'Coming ${e.airDate ?? 'soon'}'
        : [if (e.progress >= .95) 'Watched' else if (e.progress > 0) '${(e.progress * 100).round()}%', ?e.airDate].join(' · ');
    return Semantics(
      button: true,
      selected: selected,
      label: ['Episode ${e.episode}', e.name, if (status.isNotEmpty) status].join(', '),
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        builder: (context, f) => SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: w,
                height: stillH,
                foregroundDecoration: TvRing(on: f, radius: TvDS.rTile - 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(TvDS.rTile - 4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ShowImage(urls: [?e.still], decodeWidth: 400, fallbackTitle: 'Episode ${e.episode}'),
                      if (!e.aired) const ColoredBox(color: Color(0x80000000)),
                      if (selected)
                        const Positioned(
                          top: DS.s8,
                          left: DS.s8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                            child: Padding(padding: EdgeInsets.all(2), child: Icon(Icons.radio_button_checked_rounded, size: 20, color: _white)),
                          ),
                        ),
                      if (e.aired && e.progress > 0 && e.progress < .95)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(value: e.progress, minHeight: 3, backgroundColor: const Color(0x66000000), color: _white),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: DS.s12),
              Text(
                '${e.code} · ${e.name}',
                style: TvDS.tileName.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: f || selected ? _white : const Color(0xE6FFFFFF)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(status, style: TvDS.tileName.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: TvDS.inkMuted), maxLines: 1),
              ],
              if (e.overview != null) ...[
                const SizedBox(height: DS.s4),
                Text(
                  e.overview!,
                  style: TvDS.tileName.copyWith(fontSize: 12, fontWeight: FontWeight.w400, height: 1.35, color: TvDS.inkMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small label: "Recommended" (white, with a sparkle), "1080p", "Torrent".
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: 3),
    decoration: BoxDecoration(
      color: strong ? _white : _pillFill,
      borderRadius: BorderRadius.circular(12),
      border: strong ? null : Border.all(color: _outline),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (strong) ...[const Icon(Icons.auto_awesome_rounded, size: 12, color: _onWhite), const SizedBox(width: DS.s4)],
        Text(text, style: TvDS.panelRow.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: strong ? _onWhite : _white)),
      ],
    ),
  );
}

String _seedsOf(OneStreamSource s) => s.seeds != null && s.seeds! >= 0 ? '${s.seeds} seeds' : '';

/// The recommended source: a highlighted card — tags, size, provider · languages, name, Play and ⋮.
class _BestSource extends StatelessWidget {
  const _BestSource({super.key, required this.source, required this.kind, required this.playNode, required this.moreNode, required this.onPlay, required this.onMore});
  final OneStreamSource source;
  final String? kind;
  final FocusNode playNode, moreNode;
  final VoidCallback onPlay, onMore;

  @override
  Widget build(BuildContext context) {
    final s = source;
    final size = sizeLabel(s.sizeBytes);
    final how = kind == 'Torrent' ? _seedsOf(s) : (kind == null ? _seedsOf(s) : 'Direct link · no peers needed');
    final from = [?s.provider, ?s.languages].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DS.s16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x66FFFFFF), width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: DS.s8, runSpacing: DS.s4, children: [const _Tag('Recommended', strong: true), if (s.quality != null) _Tag(s.quality!), if (kind != null) _Tag(kind!)]),
          const SizedBox(height: DS.s8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (size.isNotEmpty) Text(size, style: TvDS.panelRow.copyWith(fontSize: 20, fontWeight: FontWeight.w600)),
              if (size.isNotEmpty && how.isNotEmpty) const SizedBox(width: DS.s12),
              if (how.isNotEmpty) Text(how, style: TvDS.panelRow.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: TvDS.inkMuted)),
            ],
          ),
          if (from.isNotEmpty) ...[const SizedBox(height: DS.s4), Text(from, style: TvDS.panelRow.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: TvDS.inkMuted))],
          if (s.name.isNotEmpty) ...[
            const SizedBox(height: DS.s4),
            Text(s.name, style: TvDS.tileName.copyWith(fontSize: 12, fontWeight: FontWeight.w400, color: TvDS.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: DS.s12),
          Row(
            children: [
              _Pill(key: const ValueKey('best:play'), focusNode: playNode, primary: true, height: 44, width: 200, icon: Icons.play_arrow_rounded, label: 'Play', onSelect: onPlay),
              const SizedBox(width: DS.s12),
              _Pill(key: const ValueKey('best:more'), focusNode: moreNode, height: 44, icon: Icons.more_vert_rounded, semantics: 'More for this source', onSelect: onMore),
            ],
          ),
        ],
      ),
    );
  }
}

/// Another source: a dark row — tags, size · seeds, provider · languages. OK opens its options.
class _SourceRow extends StatelessWidget {
  const _SourceRow({super.key, required this.source, required this.kind, required this.onSelect, required this.focusNode});
  final OneStreamSource source;
  final String? kind;
  final VoidCallback onSelect;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final s = source;
    final top = [sizeLabel(s.sizeBytes), _seedsOf(s)].where((x) => x.isNotEmpty).join(' · ');
    final from = [?s.provider, ?s.languages].join(' · ');
    return Semantics(
      button: true,
      label: s.detail.isEmpty ? s.label : '${s.label}, ${s.detail}',
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        builder: (context, f) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s12),
          foregroundDecoration: TvRing(on: f, radius: 14),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: f ? const Color(0x99FFFFFF) : _outline)),
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: Wrap(spacing: DS.s8, runSpacing: DS.s4, children: [if (s.quality != null) _Tag(s.quality!), if (kind != null) _Tag(kind!), if (s.quality == null && kind == null) _Tag(s.label)]),
              ),
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (top.isNotEmpty) Text(top, style: TvDS.panelRow.copyWith(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (from.isNotEmpty) Text(from, style: TvDS.panelRow.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: TvDS.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.more_vert_rounded, size: 22, color: f ? _white : TvDS.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
