import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'one_stream.dart';
import 'one_stream_extras.dart';
import 'one_stream_widgets.dart';
import 'ratings.dart';
import 'tiles/tiles_home.dart' show tileAccent, tileAccentText;
import 'tv_cast.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'widgets.dart';

/// A One Stream title, right here in One Launcher: picture, story, critics' scores (IMDb · Rotten
/// Tomatoes · Metacritic), Play / Resume, watchlist, download, prepare to stream, its sources,
/// (series) episodes by season with their own IMDb scores, and reviews — One Stream only
/// opens when something actually plays. With a TV paired: play / download it on the TV. Classic: rounded, Sentence case; Metro: flat, lowercase.
Future<void> showOneStreamTitle(BuildContext context, OneStreamTitle title) =>
    showOneSheetWith(context, builder: (ctx) => OneStreamTitleSheet(title: title));

/// The sheet's content (also used by tests).
class OneStreamTitleSheet extends StatefulWidget {
  const OneStreamTitleSheet({super.key, required this.title});
  final OneStreamTitle title;

  @override
  State<OneStreamTitleSheet> createState() => _OneStreamTitleSheetState();
}

class _OneStreamTitleSheetState extends State<OneStreamTitleSheet> {
  OneStream get os => OneStream.instance;
  OneStreamTitle get t => _details?.title ?? widget.title;
  int? get tmdb => widget.title.tmdb;
  String get type => widget.title.type;

  OneStreamDetails? _details;
  bool _detailsDone = false;
  bool _inWatchlist = false;

  int _season = 1;
  List<OneStreamEpisode>? _episodes; // null: loading
  OneStreamEpisode? _episode; // series: the episode the sources are for

  Future<List<OneStreamSource>>? _sourcesFuture;
  List<OneStreamSource>? _sources; // null: looking

  List<OneStreamDownload> _downloads = const [];
  Timer? _poll;

  // Critics' scores and reviews (OMDb / TMDB, ratings.dart): asked when the sheet opens, kept a week.
  TitleRatings? _ratings;
  ShowReviews? _reviews;
  final _episodeRatings = <int, Map<int, double>>{}; // season → episode → IMDb score

  String? _note; // One Stream's answer to the last action
  bool _noteBad = false;
  VoidCallback? _retry; // the last request to the TV, when it didn't get there

  @override
  void initState() {
    super.initState();
    TvCast.prefs?.addListener(_tvChanged); // paired / forgotten while open
    if (extrasTitleOf(widget.title) case final x?) {
      TitleExtras.instance.ratings(x).then((r) {
        if (mounted) setState(() => _ratings = r);
      });
      TitleExtras.instance.reviews(x).then((r) {
        if (mounted) setState(() => _reviews = r);
      });
    }
    if (tmdb == null) {
      _detailsDone = true;
      return;
    }
    os.details(type, tmdb!).then((d) {
      if (!mounted) return;
      setState(() {
        _details = d;
        _detailsDone = true;
        _inWatchlist = d?.inWatchlist ?? false;
      });
    });
    if (widget.title.isTv) {
      _loadSeason(1);
    } else {
      _loadSources();
    }
    _loadDownloads();
  }

  @override
  void dispose() {
    TvCast.prefs?.removeListener(_tvChanged);
    _poll?.cancel();
    super.dispose();
  }

  // ---- loading ----

  Future<void> _loadSeason(int season) async {
    setState(() {
      _season = season;
      _episodes = null;
    });
    if (extrasTitleOf(widget.title) case final x? when !_episodeRatings.containsKey(season)) {
      TitleExtras.instance.episodeRatings(x, season).then((r) {
        if (r != null && mounted) setState(() => _episodeRatings[season] = r);
      });
    }
    final list = await os.episodes(tmdb!, season);
    if (!mounted || _season != season) return;
    setState(() => _episodes = list);
    // Ready to go: the episode you're in the middle of, else the next one not watched.
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
    final f = os.sources(type, tmdb!, season: e?.season, episode: e?.episode);
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
    // Moving downloads: follow their progress while the sheet is open.
    _poll?.cancel();
    if (mine.any((d) => !d.done)) _poll = Timer(const Duration(seconds: 3), _loadDownloads);
  }

  // ---- actions ----

  void _say(String text, {bool bad = false, VoidCallback? retry}) => setState(() {
    _note = text;
    _noteBad = bad;
    _retry = retry;
  });

  void _tvChanged() {
    if (mounted) setState(() {});
  }

  /// "On Kame TV": a TV is paired and One Stream answers here (the TV has its own).
  bool get _onTv => TvCast.paired && tmdb != null && os.available.value;

  /// Plays / downloads it in One Stream on the TV (the picked episode, for a series). [source]
  /// (else the best one found so far) only helps the TV pick the same one: it searches itself.
  Future<void> _cast({bool download = false, OneStreamSource? source}) async {
    HapticFeedback.selectionClick();
    final e = _episode;
    if (widget.title.isTv && e == null) return _say('Pick an episode first');
    final pool = [...?_sources?.where((s) => !download || s.downloadable)];
    final hint = source ?? pool.where((s) => s.best).firstOrNull ?? pool.firstOrNull;
    _say('Sending to ${TvCast.tvName}…');
    final r = download
        ? await TvCast.castDownload(widget.title, season: e?.season, episode: e?.episode, source: hint)
        : await TvCast.castPlay(widget.title, season: e?.season, episode: e?.episode, source: hint);
    if (!mounted) return;
    if (r.ok) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    _say(r.message, bad: !r.ok, retry: r.ok ? null : () => _cast(download: download, source: source));
  }

  void _reply(OneStreamReply r, String ok, String failed) => _say(r.message ?? (r.ok ? ok : failed), bad: !r.ok);

  /// The source One Stream marks best (else the first), once the search is done.
  Future<OneStreamSource?> _best({bool download = false}) async {
    if (_sourcesFuture == null) return null;
    if (_sources == null) _say('Finding the best source…');
    final list = await _sourcesFuture!;
    final pool = download ? list.where((s) => s.downloadable).toList() : list;
    return pool.where((s) => s.best).firstOrNull ?? pool.firstOrNull;
  }

  Future<void> _play() async {
    final resume = _details?.resumeLink;
    if (resume != null && _episode == null) {
      os.open(resume);
      return;
    }
    if (widget.title.isTv && _episode == null) return _say('Pick an episode first');
    final s = await _best();
    if (!mounted) return;
    if (s == null) return _say('No sources found', bad: true);
    _playSource(s);
  }

  void _playSource(OneStreamSource s) {
    final e = _episode;
    os.open(OneStream.playLink(s, type, tmdb!, season: e?.season, episode: e?.episode));
  }

  Future<void> _download([OneStreamSource? source]) async {
    final s = source ?? await _best(download: true);
    if (!mounted) return;
    if (s == null) return _say('Nothing here can be downloaded', bad: true);
    _reply(await os.download(s.token), 'Download started', 'Couldn’t start the download');
    _loadDownloads();
  }

  Future<void> _prepare([OneStreamSource? source]) async {
    final s = source ?? await _best();
    if (!mounted) return;
    if (s == null) return _say('No sources found', bad: true);
    _reply(await os.prepare(s.token), 'Getting it ready to stream', 'Couldn’t prepare it');
  }

  Future<void> _toggleWatchlist() async {
    final add = !_inWatchlist;
    setState(() => _inWatchlist = add); // at once; undone if One Stream says no
    final r = await os.setWatchlist(add, type, tmdb!);
    if (!mounted) return;
    if (!r.ok) setState(() => _inWatchlist = !add);
    _reply(r, add ? 'Added to your watchlist' : 'Removed from your watchlist', 'Couldn’t change your watchlist');
  }

  Future<void> _cancel(OneStreamDownload d) async {
    _reply(await os.cancelDownload(d.key), 'Download cancelled', 'Couldn’t cancel it');
    _loadDownloads();
  }

  void _sourceMenu(OneStreamSource s) => showOneSheet(
    context,
    header: SheetHeader(title: s.label, subtitle: s.detail.isEmpty ? s.name : s.detail, yours: true),
    actions: [
      SheetAction(Icons.play_arrow_rounded, 'Play', () {
        Navigator.pop(context);
        _playSource(s);
      }),
      if (s.downloadable)
        SheetAction(Icons.download_rounded, 'Download', () {
          Navigator.pop(context);
          _download(s);
        }),
      SheetAction(Icons.bolt_rounded, 'Prepare to stream', () {
        Navigator.pop(context);
        _prepare(s);
      }),
      if (_onTv) ...[
        SheetAction(Icons.tv_rounded, 'Play on TV', () {
          Navigator.pop(context);
          _cast(source: s);
        }),
        if (s.downloadable)
          SheetAction(Icons.download_rounded, 'Download on TV', () {
            Navigator.pop(context);
            _cast(download: true, source: s);
          }),
      ],
    ],
  );

  // ---- look ----

  Color get _accent => DS.metro ? tileAccent() : DS.ink;

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(DS.s24, DS.s24, DS.s24, DS.s8),
    child: Text(
      DS.cased(text),
      style: DS.metro
          ? TextStyle(fontFamily: DS.face, color: tileAccentText(), fontSize: 20, fontWeight: FontWeight.w300)
          : DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 13),
    ),
  );

  /// How far in: a thin bar on a faint track.
  Widget _bar(double p, {Color? colour}) => ClipRRect(
    borderRadius: BorderRadius.circular(DS.metro ? 0 : 2),
    child: LinearProgressIndicator(value: p.clamp(0, 1).toDouble(), minHeight: 3, color: colour ?? _accent, backgroundColor: DS.hairline),
  );

  Widget _row({required Widget lead, required String title, String? sub, Widget? trailing, VoidCallback? onTap, bool selected = false, Key? key}) => Material(
    key: key,
    color: selected ? DS.cardMuted : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: DS.s8),
          child: Row(
            children: [
              lead,
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DS.rowTitle.copyWith(fontWeight: DS.metro ? FontWeight.w400 : FontWeight.w500)),
                    if (sub != null && sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.rowSub.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    ),
  );

  Widget _square(Widget child) => Container(
    width: 44,
    height: 44,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: DS.metro ? tileAccent() : DS.cardMuted,
      borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : 12),
    ),
    child: child,
  );

  Widget _spinnerRow(String text) => _row(
    lead: _square(SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: DS.metro ? Colors.white : DS.ink))),
    title: text,
  );

  @override
  Widget build(BuildContext context) {
    final d = _details;
    final tv = widget.title.isTv;
    final resume = d?.resumeLink != null && _episode == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Picture: the backdrop, the title over its fade.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DS.rMedia),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OneStreamArt(title: t, backdrop: true, radius: 0),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB3000000)]),
                    ),
                  ),
                  Positioned(
                    left: DS.s16,
                    right: DS.s16,
                    bottom: DS.s12,
                    child: Text(
                      t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: DS.face, color: Colors.white, fontSize: DS.metro ? 30 : 24, fontWeight: DS.metro ? FontWeight.w300 : FontWeight.w600, height: 1.1),
                    ),
                  ),
                  if (resume && d!.resumeProgress > 0) Positioned(left: 0, right: 0, bottom: 0, child: _bar(d.resumeProgress, colour: Colors.white)),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, DS.s12, DS.s24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d?.meta.isNotEmpty == true ? d!.meta : t.caption,
                style: DS.rowSub.copyWith(color: DS.ink, fontWeight: FontWeight.w500),
              ),
              if (d?.genres != null) Text(d!.genres!, style: DS.rowSub.copyWith(fontSize: 13)),
              if (_ratings != null && !_ratings!.isEmpty) ...[const SizedBox(height: DS.s12), PhoneRatingsRow(ratings: _ratings)],
              if (d?.overview != null) ...[
                const SizedBox(height: DS.s8),
                Text(d!.overview!, maxLines: 5, overflow: TextOverflow.ellipsis, style: DS.rowSub.copyWith(color: DS.ink, height: 1.35)),
              ] else if (!_detailsDone)
                Padding(
                  padding: const EdgeInsets.only(top: DS.s8),
                  child: Text(DS.cased('Loading…'), style: DS.rowSub),
                ),
            ],
          ),
        ),
        // Actions: Play / Resume first, then watchlist, download, prepare.
        Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, 0),
          child: Wrap(
            spacing: DS.s8,
            runSpacing: DS.s8,
            children: [
              _Button(
                icon: Icons.play_arrow_rounded,
                label: resume ? 'Resume' : (tv && _episode != null ? 'Play ${_episode!.code}' : 'Play'),
                primary: true,
                onTap: tmdb == null ? () => os.open(widget.title.link) : _play,
              ),
              if (tmdb != null) ...[
                _Button(
                  key: const ValueKey('watchlist'),
                  icon: _inWatchlist ? Icons.check_rounded : Icons.add_rounded,
                  label: _inWatchlist ? 'In watchlist' : 'Watchlist',
                  onTap: _toggleWatchlist,
                ),
                _Button(icon: Icons.download_rounded, label: 'Download', onTap: () => _download()),
                _Button(icon: Icons.bolt_rounded, label: 'Prepare', onTap: () => _prepare()),
              ],
            ],
          ),
        ),
        // On the paired TV: the same title in One Stream there.
        if (_onTv)
          Padding(
            key: const ValueKey('on-tv'),
            padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DS.cased('On ${TvCast.tvName}'),
                  style: DS.metro
                      ? TextStyle(fontFamily: DS.face, color: tileAccentText(), fontSize: 16, fontWeight: FontWeight.w400)
                      : DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 13),
                ),
                const SizedBox(height: DS.s8),
                Wrap(
                  spacing: DS.s8,
                  runSpacing: DS.s8,
                  children: [
                    _Button(key: const ValueKey('tv-play'), icon: Icons.tv_rounded, label: 'Play on TV', snug: true, onTap: () => _cast()),
                    _Button(key: const ValueKey('tv-download'), icon: Icons.download_rounded, label: 'Download on TV', snug: true, onTap: () => _cast(download: true)),
                  ],
                ),
              ],
            ),
          ),
        // One Stream's answer ("Download started").
        AnimatedSize(
          duration: Motion.snapDuration,
          curve: Curves.easeOutCubic,
          child: _note == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(DS.s24, DS.s12, DS.s24, 0),
                  child: Row(
                    children: [
                      Icon(
                        _noteBad
                            ? Icons.error_outline_rounded
                            : (_note!.endsWith('…') ? Icons.hourglass_top_rounded : Icons.check_circle_outline_rounded),
                        size: 18,
                        color: _noteBad ? DS.alert : DS.inkMuted,
                      ),
                      const SizedBox(width: DS.s8),
                      Expanded(
                        child: Text(DS.cased(_note!), style: DS.rowSub.copyWith(color: _noteBad ? DS.alert : DS.ink)),
                      ),
                      if (_retry != null) ...[
                        const SizedBox(width: DS.s8),
                        _Button(key: const ValueKey('retry'), label: 'Retry', compact: true, onTap: _retry!),
                      ],
                    ],
                  ),
                ),
        ),

        // ---- Episodes (series): season chips, then its episodes ----
        if (tv && tmdb != null) ...[
          _header('Episodes'),
          if ((d?.seasons ?? 1) > 1)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                itemCount: d!.seasons!,
                separatorBuilder: (_, _) => const SizedBox(width: DS.s8),
                itemBuilder: (context, i) => _Button(label: 'Season ${i + 1}', selected: _season == i + 1, compact: true, onTap: () => _loadSeason(i + 1)),
              ),
            ),
          if (_episodes == null)
            _spinnerRow('Loading episodes…')
          else if (_episodes!.isEmpty)
            _row(lead: _square(Icon(Icons.tv_off_rounded, color: DS.metro ? Colors.white : DS.ink)), title: DS.cased('No episodes listed'))
          else
            for (final e in _episodes!)
              PhoneEpisodeRow(
                key: ValueKey('ep:${e.season}:${e.episode}'),
                episode: e,
                selected: _episode?.season == e.season && _episode?.episode == e.episode,
                rating: _episodeRatings[e.season]?[e.episode],
                still: e.still == null
                    ? ColoredBox(
                        color: DS.metro ? tileAccent() : DS.ink.withValues(alpha: .08),
                        child: Center(child: Text(e.code, style: DS.rowTitle.copyWith(fontSize: 14, color: DS.metro ? Colors.white : DS.ink))),
                      )
                    : Image.network(e.still!, fit: BoxFit.cover, cacheWidth: 240, errorBuilder: (_, _, _) => ColoredBox(color: DS.cardMuted)),
                progressBar: e.progress > 0 ? _bar(e.progress, colour: Colors.white) : null,
                onTap: e.aired ? () => _pick(e) : null,
              ),
        ],

        // ---- Sources ----
        if (tmdb != null) ...[
          _header(tv && _episode != null ? 'Sources · S${_episode!.season} ${_episode!.code}' : 'Sources'),
          if (_sourcesFuture == null)
            _row(lead: _square(Icon(Icons.touch_app_outlined, color: DS.metro ? Colors.white : DS.ink)), title: DS.cased('Pick an episode to see its sources'))
          else if (_sources == null)
            _spinnerRow(DS.cased('Looking for sources… this can take a few seconds'))
          else if (_sources!.isEmpty)
            _row(lead: _square(Icon(Icons.search_off_rounded, color: DS.metro ? Colors.white : DS.ink)), title: DS.cased('No sources found'))
          else
            for (final s in _sources!)
              _row(
                key: ValueKey('src:${s.token}'),
                lead: _square(Icon(s.kind == 'download' ? Icons.download_done_rounded : Icons.play_arrow_rounded, color: DS.metro ? Colors.white : DS.ink)),
                title: [s.label, if (s.best) DS.cased('Best')].join(' · '),
                sub: s.detail.isEmpty ? s.name : s.detail,
                trailing: Icon(Icons.more_horiz_rounded, color: DS.inkFaint),
                onTap: () => _sourceMenu(s),
              ),
        ],

        // ---- Reviews (TMDB): sideways cards, tap one for all of it ----
        PhoneReviewsSection(reviews: _reviews, title: t.title, header: _header),

        // ---- Downloads (this title's, in One Stream) ----
        if (_downloads.isNotEmpty) ...[
          _header('Downloads'),
          for (final dl in _downloads)
            _row(
              key: ValueKey('dl:${dl.key}'),
              lead: _square(Icon(dl.done ? Icons.download_done_rounded : Icons.downloading_rounded, color: DS.metro ? Colors.white : DS.ink)),
              title: dl.subtitle ?? dl.title,
              sub: dl.detail,
              trailing: dl.done
                  ? null
                  : IconButton(tooltip: 'Cancel download', icon: Icon(Icons.close_rounded, color: DS.inkMuted), onPressed: () => _cancel(dl)),
              onTap: dl.done && dl.playLink != null ? () => os.open(dl.playLink!) : null,
            ),
        ],
        const SizedBox(height: DS.s16),
      ],
    );
  }
}

/// The sheet's buttons. Classic: pills (the first an ink one); Metro: flat boxes, the accent
/// for the main one and the chosen one, outlined otherwise, lowercase.
class _Button extends StatelessWidget {
  const _Button({super.key, this.icon, required this.label, required this.onTap, this.primary = false, this.selected = false, this.compact = false, this.snug = false});
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool primary, selected, compact;
  final bool snug; // full height, less padding: two long labels share a row

  @override
  Widget build(BuildContext context) {
    final strong = primary || selected;
    final fill = strong ? (DS.metro ? tileAccent() : DS.ink) : (DS.metro ? Colors.transparent : DS.cardMuted);
    final ink = strong ? (DS.metro ? Colors.white : DS.card) : DS.ink;
    return Pressable(
      scale: .94,
      child: Material(
        color: fill,
        shape: DS.metro
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DS.rMedia),
                side: strong ? BorderSide.none : BorderSide(color: DS.ink.withValues(alpha: .5), width: 1.5),
              )
            : const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: DS.metro ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)) : const StadiumBorder(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 40 : 48),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact || snug ? DS.s16 : DS.s20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20, color: ink), const SizedBox(width: 6)],
                  Text(DS.cased(label), style: DS.rowTitle.copyWith(color: ink, fontSize: 15, fontWeight: DS.metro ? FontWeight.w400 : FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
