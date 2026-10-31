import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../one_stream.dart';
import '../prefs.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'catalog.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_metro.dart';
import 'tv_focus.dart';
import 'tv_one_stream.dart';
import 'tv_parts.dart';
import 'tv_ratings.dart' show TvSeasonTab;
import 'tv_title.dart';
import 'youtube_search.dart';

/// Search, content first. Under the field, filter chips: All · One Stream · YouTube · each
/// streaming service with results (Netflix, Prime Video…) · Apps. "All" shows one row per source —
/// One Stream and YouTube first, then a row per service from the TV's catalog (instant, built from
/// the Stremio addons — see catalog.dart — joined by their live search), the rest of the shows &
/// films, apps, then other ways to search. A chip shows just that source, as a grid with more.
/// Before typing: what's popular, by service. ↓ from the field goes to the chips, ↓ again into
/// the results.
class TvSearch extends StatefulWidget {
  const TvSearch({super.key, required this.apps, required this.onLaunch, this.query, this.prefs});
  final List<AppEntry> apps;

  /// Search history (shown as pills above the filters; saved when a search is used). None in tests.
  final Prefs? prefs;

  /// Words to search for at once (the phone remote's voice search).
  final String? query;
  final void Function(AppEntry) onLaunch;

  @override
  State<TvSearch> createState() => _TvSearchState();
}

class _TvSearchState extends State<TvSearch> {
  final _q = TextEditingController();
  final _field = FocusNode(debugLabel: 'search field');
  final _mic = FocusNode(debugLabel: 'mic');
  final _scroll = ScrollController();
  final _headerKey = GlobalKey();
  double _headerH = 180; // measured after layout: the results start under the header
  bool _listening = false;
  final _firstAction = FocusNode();
  // One focus node per card, kept by row + item: when results re-rank, focus stays on the card
  // it was on (a node never moves to another card).
  final _nodes = <String, FocusNode>{};
  final _seenNodes = <String>{}; // keys built this frame
  final _chipNodes = <String, FocusNode>{};
  String _filter = 'all'; // 'all' · 'stream' · 'youtube' · 'svc:<service>' · 'apps'
  List<String> _targets = const []; // apps that accept a search

  Timer? _debounce;
  Catalog get _catalog => Catalog.instance;
  int _seen = -1; // the catalog version the results come from
  List<ShowTitle> _local = const []; // from the TV's catalog (as you type)
  String _searched = ''; // what the live search last asked
  List<ShowTitle> _live = const []; // the sources' own search (Cinemeta…)
  bool _loading = false;
  Object? _error;
  // One Stream (the user's streaming app, when installed): its own search, as its own row.
  Timer? _streamWait;
  List<(OneStreamTitle, ShowTitle)> _stream = const [];
  // YouTube's own search (when the YouTube app is on the TV), once typing pauses.
  Timer? _ytWait;
  List<YtVideo> _yt = const [];

  @override
  void initState() {
    super.initState();
    _field.addListener(_onFieldFocus);
    TvApps.instance.searchTargets().then((t) {
      if (mounted) setState(() => _targets = t);
    });
    _catalog.addListener(_onCatalog);
    // No catalog yet (first run): make it now rather than at the next automatic check.
    _catalog.load().then((_) {
      if (_catalog.count == 0) _catalog.maybeUpdate();
      if (widget.query case final q? when mounted) {
        _q.text = q;
        _onType(q);
      }
    });
  }

  /// The catalog loaded / updated (or is updating): refresh what's shown.
  void _onCatalog() {
    if (!mounted) return;
    setState(() {
      if (_seen != _catalog.version) {
        _seen = _catalog.version;
        _local = _catalog.search(_q.text);
      }
    });
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalog);
    _debounce?.cancel();
    _streamWait?.cancel();
    _ytWait?.cancel();
    _field.removeListener(_onFieldFocus);
    _field.dispose();
    _mic.dispose();
    _scroll.dispose();
    _q.dispose();
    for (final n in [..._nodes.values, ..._chipNodes.values]) {
      n.dispose();
    }
    _firstAction.dispose();
    super.dispose();
  }

  /// Each letter searches the TV's catalog right away; once typing pauses the sources' own search
  /// joins in (each key on a TV keyboard is slow; don't ask the internet per letter).
  void _onType(String _) {
    final q = _q.text.trim();
    setState(() {
      _local = _catalog.search(q);
      _error = null;
    });
    _searchStream(q);
    _searchYouTube(q);
    _debounce?.cancel();
    if (!Catalog.enabled || q.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _loading = true);
      try {
        final r = await _catalog.searchOnline(q);
        if (!mounted || _q.text.trim() != q) return;
        setState(() {
          _searched = q;
          _live = r;
        });
      } catch (e) {
        debugPrint('Live search failed: ${e is CatalogException ? e : e.runtimeType}'); // addon names only, never links
        if (mounted && _q.text.trim() == q) setState(() => _error = e);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  /// One Stream's search, once typing pauses (it goes to the network inside One Stream).
  void _searchStream(String q) {
    _streamWait?.cancel();
    if (q.length < 2 || !OneStream.instance.available.value) {
      if (_stream.isNotEmpty) setState(() => _stream = const []);
      return;
    }
    _streamWait = Timer(const Duration(milliseconds: 450), () async {
      final r = await OneStream.instance.search(q);
      if (!mounted || _q.text.trim() != q) return;
      setState(() => _stream = [for (final t in r) (t, showTitleOf(t))]);
    });
  }

  bool get _hasYouTube => TvApps.demo || widget.apps.any((a) => a.package == YouTubeSearch.tvPackage);

  /// YouTube's search, once typing pauses.
  void _searchYouTube(String q) {
    _ytWait?.cancel();
    if (q.length < 2 || !_hasYouTube) {
      if (_yt.isNotEmpty) setState(() => _yt = const []);
      return;
    }
    _ytWait = Timer(const Duration(milliseconds: 450), () async {
      final r = await YouTubeSearch.instance.search(q);
      if (!mounted || _q.text.trim() != q) return;
      setState(() => _yt = r);
    });
  }

  /// The focus node for a card ([key]: row + item), made on first use.
  FocusNode _node(String key) {
    _seenNodes.add(key);
    return _nodes[key] ??= FocusNode(debugLabel: key);
  }

  FocusNode _chip(String id) => _chipNodes[id] ??= FocusNode(debugLabel: 'chip:$id');

  /// After a frame: let go of the nodes of cards no longer shown.
  void _dropStaleNodes() {
    if (!mounted) return;
    _nodes.removeWhere((k, n) {
      if (_seenNodes.contains(k) || n.hasFocus) return false;
      n.dispose();
      return true;
    });
  }

  void _openVideo(YtVideo v) {
    _remember();
    TvApps.instance.openUri(v.link, package: YouTubeSearch.tvPackage);
  }

  /// Back rule: away from the field, Back returns to it (and the page to its top); on the field
  /// Back leaves Search. The PopScope reads this.
  void _onFieldFocus() {
    if (mounted) setState(() {});
  }

  void _backToField() {
    _field.requestFocus();
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  /// The search was used (a result opened, Enter): keep it in the history.
  void _remember() => widget.prefs?.addSearch(_q.text);

  /// A history pill: search for it again.
  void _searchAgain(String q) {
    _q.text = q;
    _q.selection = TextSelection.collapsed(offset: q.length);
    _onType(q);
  }

  /// The mic: speak, and the words go into the field. TVs without a speech recogniser get the
  /// Assistant instead.
  Future<void> _listen() async {
    if (_listening) return;
    setState(() => _listening = true);
    final words = await TvApps.instance.listen();
    if (!mounted) return;
    setState(() => _listening = false);
    if (words == null) return TvApps.instance.openAction('t:assistant');
    if (words.trim().isEmpty) return;
    _searchAgain(words.trim());
    _remember();
  }

  /// Keeps [_headerH] in step with the header's real height.
  void _measureHeader() {
    final h = (_headerKey.currentContext?.findRenderObject() as RenderBox?)?.size.height;
    if (h != null && mounted && (h - _headerH).abs() > .5) setState(() => _headerH = h);
  }

  /// One Stream's own page for it, here on the TV (One Stream opens only to play).
  void _openStream(OneStreamTitle s) {
    _remember();
    Navigator.of(context).push(tvFade(TvOneStreamPage(title: s)));
  }

  void _openTitle(ShowTitle t) {
    _remember();
    Navigator.of(context).push(tvFade(TvTitlePage(title: t, apps: widget.apps, searchTargets: _targets, onOpenApp: widget.onLaunch)));
  }

  /// No posters to show: why, in words.
  String _emptyNote(String raw) {
    final c = _catalog;
    if (raw.isEmpty) {
      if (!c.loaded) return 'Loading…';
      if (c.syncing) return 'Getting the catalog ready… ${(c.progress * 100).round()}%';
      if (c.error != null) return c.error!;
      return c.updated == null
          ? 'No catalog yet. Make it in Customise → Search → Update catalog now.'
          : 'The catalog is empty. Check its sources in Customise → Search.';
    }
    if (_loading || (raw.length >= 2 && _searched != raw && _error == null)) return 'Searching…';
    if (_error is CatalogException && (_error as CatalogException).status == -1) return 'Couldn’t reach the catalogs. Check the TV’s internet.';
    return 'No shows or films called “$raw”.';
  }

  /// Each source's TV app: its icon is the source's chip (when the app is installed).
  static const _chipApps = {
    'stream': OneStream.package,
    'youtube': YouTubeSearch.tvPackage,
    'svc:Netflix': 'com.netflix.ninja',
    'svc:Prime Video': 'com.amazon.amazonvideo.livingroom',
    'svc:JioHotstar': 'in.startv.hotstar',
    'svc:Apple TV+': 'com.apple.atve.androidtv.appletv',
    'svc:ZEE5': 'com.graymatrix.did',
    'svc:Sony LIV': 'com.sonyliv',
  };

  /// …else its website's icon, fetched once (Google's site-icon service).
  static const _chipSites = {
    'youtube': 'youtube.com',
    'svc:Netflix': 'netflix.com',
    'svc:Prime Video': 'primevideo.com',
    'svc:JioHotstar': 'hotstar.com',
    'svc:Apple TV+': 'tv.apple.com',
    'svc:ZEE5': 'zee5.com',
    'svc:Sony LIV': 'sonyliv.com',
    'svc:Disney+': 'disneyplus.com',
    'svc:HBO Max': 'max.com',
    'svc:Hulu': 'hulu.com',
    'svc:Paramount+': 'paramountplus.com',
    'svc:Peacock': 'peacocktv.com',
    'svc:Crunchyroll': 'crunchyroll.com',
    'svc:MUBI': 'mubi.com',
    'svc:Sun NXT': 'sunnxt.com',
    'svc:MX Player': 'mxplayer.in',
    'svc:Lionsgate Play': 'lionsgateplay.com',
    'svc:Discovery+': 'discoveryplus.com',
  };

  Widget? _chipIcon(String id, Map<String, AppEntry> byPkg) {
    Widget clip(Widget w) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox.square(dimension: 26, child: w),
    );
    if (id == 'apps') return const Icon(Icons.apps_rounded, size: 24, color: TvDS.ink);
    if (byPkg[_chipApps[id]] case final app?) return clip(TvAppIcon(app: app, size: 26));
    if (_chipSites[id] case final site?) {
      return clip(
        FutureBuilder<MemoryImage?>(
          future: TvApps.instance.image('https://www.google.com/s2/favicons?domain=$site&sz=128', width: 64).catchError((Object _) => null),
          builder: (context, snap) =>
              snap.data == null ? ColoredBox(color: tvTint(site)) : Image(image: snap.data!, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
        ),
      );
    }
    return null; // no icon anywhere: the chip keeps its name
  }

  /// Services to group by, in this order first (the big ones here), then by how many results.
  static const _servicePriority = ['Netflix', 'Prime Video', 'JioHotstar', 'Apple TV+', 'ZEE5', 'Sony LIV'];

  @override
  Widget build(BuildContext context) {
    final raw = _q.text.trim();
    final q = raw.toLowerCase();
    final metro = TvMetro.on;
    final apps = q.isEmpty
        ? const <AppEntry>[]
        : (widget.apps.where((a) => a.label.toLowerCase().contains(q)).toList()
            ..sort((a, b) => (a.label.toLowerCase().startsWith(q) ? 0 : 1).compareTo(b.label.toLowerCase().startsWith(q) ? 0 : 1)));
    final byPkg = {for (final a in widget.apps) a.package: a};
    final targets = [for (final p in _targets) ?byPkg[p]];
    final searchOn = Catalog.enabled;
    final posters = !searchOn ? const <ShowTitle>[] : (q.isEmpty ? _catalog.trending(40) : combineResults(raw, _local, _searched == raw ? _live : const []));
    final stream = raw.length >= 2 ? _stream : const <(OneStreamTitle, ShowTitle)>[];
    final yt = raw.length >= 2 ? _yt : const <YtVideo>[];

    // Shows & films by service; the ones on no service row go to "More shows & films".
    final bySvc = <String, List<ShowTitle>>{};
    for (final t in posters) {
      for (final s in t.services) {
        (bySvc[s] ??= []).add(t);
      }
    }
    int rank(String s) {
      final i = _servicePriority.indexOf(s);
      return i < 0 ? _servicePriority.length : i;
    }

    final services = bySvc.keys.toList()..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : bySvc[b]!.length - bySvc[a]!.length);
    final rowServices = services.take(4).toList(); // "All" keeps to the main few
    final onRows = {for (final s in rowServices) ...bySvc[s]!.map((t) => t.key)};
    final rest = [
      for (final t in posters)
        if (!onRows.contains(t.key)) t,
    ];

    // The chips: All, then each source that has something.
    final chips = <(String, String)>[
      ('all', 'All'),
      if (stream.isNotEmpty) ('stream', 'One Stream'),
      if (yt.isNotEmpty) ('youtube', 'YouTube'),
      for (final s in services) ('svc:$s', s),
      if (apps.isNotEmpty) ('apps', 'Apps'),
    ];
    final filter = chips.any((c) => c.$1 == _filter) ? _filter : 'all';

    _seenNodes.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _dropStaleNodes());

    // ---- Pieces ----
    Widget header(String title, [int? count]) => Padding(
      padding: const EdgeInsets.only(top: DS.s24, bottom: DS.s12),
      child: Text(count == null ? TvMetro.cased(title) : '${TvMetro.cased(title)} · $count', style: TvMetro.headerOr(TvDS.rowTitleFocused)),
    );
    // A row scrolls sideways; a single source shows as a grid.
    Widget row(List<Widget> cards, {double gap = DS.s16}) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, c) in cards.indexed) ...[if (i > 0) SizedBox(width: gap), c],
        ],
      ),
    );
    Widget grid(List<Widget> cards, {double gap = DS.s16}) => Wrap(spacing: gap, runSpacing: DS.s20, children: cards);

    List<Widget> streamCards(String rowId, int n) => [
      for (final (s, t) in stream.take(n))
        TvPoster(key: ValueKey('$rowId:${s.key}'), title: t, focusNode: _node('$rowId:${s.key}'), onSelect: () => _openStream(s)),
    ];
    List<Widget> ytCards(String rowId, int n) => [
      for (final v in yt.take(n)) _VideoCard(key: ValueKey('$rowId:${v.id}'), video: v, focusNode: _node('$rowId:${v.id}'), onSelect: () => _openVideo(v)),
    ];
    List<Widget> posterCards(String rowId, List<ShowTitle> list, int n) => [
      for (final t in list.take(n)) TvPoster(key: ValueKey('$rowId:${t.key}'), title: t, focusNode: _node('$rowId:${t.key}'), onSelect: () => _openTitle(t)),
    ];
    List<Widget> appCards() => [
      for (final a in apps)
        TvAppTile(
          key: ValueKey('app:${a.package}'),
          app: a,
          focusNode: _node('apps:${a.package}'),
          onSelect: () {
            _remember();
            widget.onLaunch(a);
          },
          onOptions: () {},
        ),
    ];

    List<Widget> moreWays(String title) => [
      header(title),
      Wrap(
        spacing: DS.s12,
        runSpacing: DS.s12,
        children: [
          if (raw.isNotEmpty)
            TvActionPill(
              focusNode: _firstAction,
              icon: Icons.travel_explore_rounded,
              label: 'Search Google TV for “$raw”',
              onSelect: () {
                _remember();
                TvApps.instance.searchEverywhere(raw);
              },
            ),
          TvActionPill(
            focusNode: raw.isEmpty ? _firstAction : null,
            icon: Icons.mic_none_rounded,
            label: 'Voice search',
            onSelect: () => TvApps.instance.openAction('t:assistant'),
          ),
          if (raw.isNotEmpty)
            for (final a in targets)
              TvActionPill(
                leading: SizedBox(width: 40, height: 22.5, child: TvAppArt(app: a, width: 40)),
                label: 'Search in ${a.label}',
                onSelect: () {
                  _remember();
                  TvApps.instance.searchIn(a.package, raw);
                },
              ),
        ],
      ),
    ];

    // ---- What the chip shows ----
    final List<Widget> body;
    if (filter == 'stream') {
      body = [header('One Stream', stream.length), grid(streamCards('stream', 24))];
    } else if (filter == 'youtube') {
      body = [header('YouTube', yt.length), grid(ytCards('youtube', 24), gap: DS.s20)];
    } else if (filter.startsWith('svc:')) {
      final s = filter.substring(4);
      body = [header(q.isEmpty ? 'Popular on $s' : 'On $s', bySvc[s]!.length), grid(posterCards(filter, bySvc[s]!, 40))];
    } else if (filter == 'apps') {
      body = [header('Apps', apps.length), grid(appCards(), gap: TvDS.gap)];
    } else {
      body = [
        if (!searchOn) ...moreWays('Search with Google TV'),
        // One Stream and YouTube lead.
        if (stream.isNotEmpty) ...[header('One Stream', stream.length), row(streamCards('stream', 12))],
        if (yt.isNotEmpty) ...[header('YouTube', yt.length), row(ytCards('youtube', 12), gap: DS.s20)],
        if (searchOn) ...[
          for (final s in rowServices) ...[header(q.isEmpty ? 'Popular on $s' : 'On $s', bySvc[s]!.length), row(posterCards('svc:$s', bySvc[s]!, 16))],
          if (rest.isNotEmpty) ...[
            header(rowServices.isEmpty ? (q.isEmpty ? 'Popular now' : 'Shows & films') : (q.isEmpty ? 'More popular' : 'More shows & films'), rest.length),
            row(posterCards('rest', rest, 16)),
          ],
          if (posters.isEmpty && stream.isEmpty && yt.isEmpty) ...[const SizedBox(height: DS.s24), Text(TvMetro.cased(_emptyNote(raw)), style: TvDS.heroBody)],
        ],
        if (apps.isNotEmpty) ...[header('Apps', apps.length), row(appCards(), gap: TvDS.gap)],
        if (searchOn) ...moreWays('More ways to search'),
      ];
    }

    final history = widget.prefs?.searchHistory.take(8).toList() ?? const <String>[];
    FocusNode historyNode(String h) => _node('history:$h');

    // ↓ from the box: the history pills, else the chip that's on. ↑ from the chips: the history,
    // else the box; ↑ from the history: the box.
    void down() => (history.isNotEmpty ? historyNode(history.first) : _chip(filter)).requestFocus();
    KeyEventResult up(KeyEvent e, FocusNode to) {
      if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
      to.requestFocus();
      return KeyEventResult.handled;
    }

    final query = TvDS.panelTitle.copyWith(fontSize: 44, fontWeight: FontWeight.w300, height: 1.15);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());

    // ---- Header: tiles title, the query, history, filters — on top of the results ----
    final top = Column(
      key: _headerKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tiles: the page's name, big and light, like "start".
        if (metro) ...[Text(TvMetro.cased('Search'), style: TvMetro.title(size: 40).copyWith(height: 1)), const SizedBox(height: DS.s16)],
        Row(
          children: [
            Expanded(
              child: Focus(
                // The field keeps ↓ for itself (send it to the pills) and → at the end goes to the mic.
                onKeyEvent: (_, e) {
                  if (e is! KeyDownEvent) return KeyEventResult.ignored;
                  if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                    down();
                    return KeyEventResult.handled;
                  }
                  if (e.logicalKey == LogicalKeyboardKey.arrowRight && _q.selection.baseOffset >= _q.text.length) {
                    _mic.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _q,
                  focusNode: _field,
                  autofocus: true,
                  onChanged: _onType,
                  // Enter / Done on the keyboard: straight to Google TV's results (unless our own
                  // shows & films search is on — then into the results).
                  onSubmitted: (_) {
                    _remember();
                    raw.isNotEmpty && !searchOn ? TvApps.instance.searchEverywhere(raw) : down();
                  },
                  // No box: the query is the page's headline, big and light.
                  style: query,
                  cursorColor: TvDS.ink,
                  cursorWidth: 3,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: TvMetro.cased(_listening ? 'Listening…' : (_hasYouTube ? 'Search shows, films, YouTube, apps' : 'Search shows, films, apps')),
                    hintStyle: query.copyWith(color: const Color(0x66FFFFFF)),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(DS.s16),
                            child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: TvDS.inkMuted)),
                          )
                        : null,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: DS.s8),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: DS.s16),
            Focus(
              onKeyEvent: (_, e) {
                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _field.requestFocus();
                  return KeyEventResult.handled;
                }
                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown) {
                  down();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: _MicButton(focusNode: _mic, listening: _listening, onSelect: _listen),
            ),
          ],
        ),
        // ---- Recent searches: the full words; OK searches again, hold OK forgets one ----
        if (history.isNotEmpty) ...[
          const SizedBox(height: DS.s12),
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, e) => up(e, _field),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  for (final (i, h) in history.indexed) ...[
                    if (i > 0) const SizedBox(width: DS.s12),
                    TvSeasonTab(
                      key: ValueKey('history:$h'),
                      focusNode: historyNode(h),
                      label: h,
                      selected: false,
                      leading: const Icon(Icons.history_rounded, size: 20, color: TvDS.inkMuted),
                      onSelect: () => _searchAgain(h),
                      onLongSelect: () async {
                        await widget.prefs?.removeSearch(h);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: DS.s16),
        // ---- Filter chips: the app's icon for each source ----
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, e) => up(e, history.isNotEmpty ? historyNode(history.first) : _field),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final (i, (id, label)) in chips.indexed) ...[
                  if (i > 0) const SizedBox(width: DS.s12),
                  TvSeasonTab(
                    key: ValueKey('chip:$id'),
                    focusNode: _chip(id),
                    label: label,
                    leading: _chipIcon(id, byPkg),
                    iconOnly: true,
                    selected: id == filter,
                    onSelect: () => setState(() => _filter = id),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: DS.s8),
      ],
    );

    const fade = 48.0; // the header's soft lower edge, over the results
    return PopScope(
      // Back: from the results to the field first; from the field, home.
      canPop: _field.hasFocus,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToField();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000000), // pure black: the big type and the posters carry the page
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ---- Results: start under the header, never clipped (a focused card's ring shows
            // whole); scrolled away, they pass under the header and fade out ----
            Positioned(
              top: TvDS.safe.top + _headerH,
              left: 0,
              right: 0,
              bottom: 0,
              child: SingleChildScrollView(
                controller: _scroll,
                clipBehavior: Clip.none,
                padding: EdgeInsets.fromLTRB(TvDS.safe.left, DS.s8, TvDS.safe.right, TvDS.safe.bottom + DS.s24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body),
              ),
            ),
            // ---- Header, drawn last so it sits on top ----
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(
                    color: const Color(0xFF000000),
                    child: Padding(padding: EdgeInsets.fromLTRB(TvDS.safe.left, TvDS.safe.top, TvDS.safe.right, 0), child: top),
                  ),
                  const IgnorePointer(
                    child: SizedBox(
                      height: fade,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF000000), Color(0xB3000000), Color(0x00000000)],
                            stops: [0, .5, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Search's mic: round, quiet until focused; pulses its fill while listening.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.focusNode, required this.listening, required this.onSelect});
  final FocusNode focusNode;
  final bool listening;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Voice search',
    child: TvFocusable(
      focusNode: focusNode,
      onSelect: onSelect,
      builder: (context, f) => AnimatedContainer(
        duration: Motion.pressIn * 2,
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: f ? TvDS.surfaceFocused : (listening ? const Color(0x40FFFFFF) : TvDS.surface),
          border: Border.all(color: listening && !f ? TvDS.ink : Colors.transparent, width: 1.5),
        ),
        child: Icon(listening ? Icons.mic_rounded : Icons.mic_none_rounded, size: 28, color: f ? TvDS.onLight : TvDS.ink),
      ),
    ),
  );
}

/// A YouTube video: its 16:9 thumbnail (length or LIVE on it), two lines of title, the channel
/// and views. OK opens it in the YouTube app.
class _VideoCard extends StatelessWidget {
  const _VideoCard({super.key, required this.video, required this.onSelect, this.focusNode});
  final YtVideo video;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  static const w = 224.0, h = 126.0;

  @override
  Widget build(BuildContext context) {
    final v = video;
    Widget badge(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TvDS.keycap.copyWith(fontSize: 11)),
    );
    return Semantics(
      button: true,
      label: '${v.title}, ${v.channel}',
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        builder: (context, f) => SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: Motion.pressIn * 2,
                width: w,
                height: h,
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
                      ShowImage(urls: [if (v.thumb.isNotEmpty) v.thumb], decodeWidth: 448, fallbackTitle: v.title),
                      if (v.live)
                        Positioned(right: DS.s8, bottom: DS.s8, child: badge('LIVE', const Color(0xFFCC0000)))
                      else if (v.length != null)
                        Positioned(right: DS.s8, bottom: DS.s8, child: badge(v.length!, const Color(0xCC000000))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: DS.s12),
              Text(
                v.title,
                style: TvDS.tileName.copyWith(fontSize: 14, height: 1.25, color: f ? TvDS.ink : TvDS.inkMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                [v.channel, ?v.views].where((x) => x.isNotEmpty).join(' · '),
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
