import 'dart:async';

import 'package:flutter/material.dart';

import '../one_stream.dart';
import '../ui/ds.dart';
import 'tv_ds.dart';
import 'tv_metro.dart';
import 'tv_parts.dart';
import 'tv_title.dart' show ShowImage;

/// A One Stream title as a TV page, inside One Launcher: backdrop, story, Play / Resume,
/// watchlist, download, prepare to stream, (series) seasons and episodes, its sources and
/// downloads — One Stream opens only when something plays. Cinematic or Metro (TvMetro), like
/// the catalog's title page.
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

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(top: DS.s24, bottom: DS.s12),
    child: Text(TvMetro.cased(text), style: TvMetro.headerOr(TvDS.rowTitleFocused)),
  );

  Widget _quiet(String text) => Text(TvMetro.cased(text), style: TvDS.heroBody);

  @override
  Widget build(BuildContext context) {
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
              child: ShowImage(urls: [?t.backdrop, ?t.poster], decodeWidth: 1280, alignment: Alignment.topCenter),
            ),
            const TvScrims(),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(TvDS.safe.left, 64, TvDS.safe.right, TvDS.safe.bottom + DS.s24),
              child: FocusTraversalGroup(child: _body()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final d = _details;
    final resume = d?.resumeLink != null && _episode == null;
    final hasTmdb = widget.title.tmdb != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TvMetro.on
                  ? Text(TvMetro.cased(tv ? 'Series · One Stream' : 'Film · One Stream'), style: TvMetro.header.copyWith(fontSize: 16))
                  : Text(tv ? 'SERIES · ONE STREAM' : 'FILM · ONE STREAM', style: TvDS.heroEyebrow),
              const SizedBox(height: DS.s8),
              Text(t.title, style: TvMetro.on ? TvMetro.title(size: 44) : TvDS.heroTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: DS.s12),
              Text(
                [if (d != null && d.meta.isNotEmpty) d.meta else t.caption, ?d?.genres].join(' · '),
                style: TvDS.heroMeta,
              ),
              if (d?.overview != null) ...[
                const SizedBox(height: DS.s16),
                Text(d!.overview!, style: TvDS.heroBody, maxLines: 4, overflow: TextOverflow.ellipsis),
              ] else if (!_detailsDone) ...[
                const SizedBox(height: DS.s16),
                _quiet('Loading…'),
              ],
            ],
          ),
        ),
        const SizedBox(height: DS.s24),
        Wrap(
          spacing: DS.s12,
          runSpacing: DS.s12,
          children: [
            TvActionPill(
              key: const ValueKey('play'),
              autofocus: true,
              icon: Icons.play_arrow_rounded,
              label: resume ? 'Resume' : (tv && _episode != null ? 'Play S${_episode!.season} ${_episode!.code}' : 'Play'),
              detail: resume && d!.resumeProgress > 0 ? '${(d.resumeProgress * 100).round()}%' : null,
              onSelect: _play,
            ),
            if (hasTmdb) ...[
              TvActionPill(
                key: const ValueKey('watchlist'),
                icon: _inWatchlist ? Icons.check_rounded : Icons.add_rounded,
                label: _inWatchlist ? 'In watchlist' : 'Add to watchlist',
                onSelect: _toggleWatchlist,
              ),
              TvActionPill(key: const ValueKey('download'), icon: Icons.download_rounded, label: 'Download', onSelect: () => _download()),
              TvActionPill(key: const ValueKey('prepare'), icon: Icons.bolt_rounded, label: 'Prepare to stream', onSelect: () => _prepare()),
            ],
          ],
        ),
        if (_note != null) ...[const SizedBox(height: DS.s12), Text(TvMetro.cased(_note!), style: TvDS.heroMeta)],

        // ---- Episodes ----
        if (tv && hasTmdb) ...[
          _header('Episodes'),
          if ((d?.seasons ?? 1) > 1) ...[
            Wrap(
              spacing: DS.s12,
              runSpacing: DS.s12,
              children: [
                for (var s = 1; s <= d!.seasons!; s++)
                  TvActionPill(
                    key: ValueKey('season:$s'),
                    icon: _season == s ? Icons.check_rounded : null,
                    label: 'Season $s',
                    onSelect: () => _loadSeason(s),
                  ),
              ],
            ),
            const SizedBox(height: DS.s12),
          ],
          if (_episodes == null)
            _quiet('Loading episodes…')
          else if (_episodes!.isEmpty)
            _quiet('No episodes listed')
          else
            Wrap(
              spacing: DS.s12,
              runSpacing: DS.s12,
              children: [
                for (final e in _episodes!)
                  TvActionPill(
                    key: ValueKey('ep:${e.season}:${e.episode}'),
                    icon: _episode?.episode == e.episode && _episode?.season == e.season ? Icons.radio_button_checked_rounded : null,
                    label: '${e.code} · ${e.name}',
                    detail: !e.aired
                        ? 'Coming ${e.airDate ?? 'soon'}'
                        : e.progress >= .95
                        ? 'Watched'
                        : (e.progress > 0 ? '${(e.progress * 100).round()}%' : null),
                    onSelect: () => e.aired ? _pick(e) : _say('Not out yet'),
                  ),
              ],
            ),
        ],

        // ---- Sources ----
        if (hasTmdb) ...[
          _header(tv && _episode != null ? 'Sources · S${_episode!.season} ${_episode!.code}' : 'Sources'),
          if (_sourcesFuture == null)
            _quiet('Pick an episode to see its sources')
          else if (_sources == null)
            Row(
              children: [
                const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: TvDS.inkMuted)),
                const SizedBox(width: DS.s12),
                _quiet('Looking for sources… this can take a few seconds'),
              ],
            )
          else if (_sources!.isEmpty)
            _quiet('No sources found')
          else
            Wrap(
              spacing: DS.s12,
              runSpacing: DS.s12,
              children: [
                for (final s in _sources!)
                  TvActionPill(
                    key: ValueKey('src:${s.token}'),
                    icon: s.best ? Icons.star_rounded : Icons.play_circle_outline_rounded,
                    label: s.best ? '${s.label} · Best' : s.label,
                    detail: s.detail.isEmpty ? null : s.detail,
                    onSelect: () => _sourceMenu(s),
                  ),
              ],
            ),
        ],

        // ---- Downloads ----
        if (_downloads.isNotEmpty) ...[
          _header('Downloads'),
          Wrap(
            spacing: DS.s12,
            runSpacing: DS.s12,
            children: [
              for (final dl in _downloads)
                TvActionPill(
                  key: ValueKey('dl:${dl.key}'),
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
            ],
          ),
        ],
      ],
    );
  }
}
