import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../ui/ds.dart';
import 'catalog.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_metro.dart';
import 'tv_parts.dart';
import 'tv_title.dart';

/// Search, content first: type a show or film → posters from the TV's own catalog (instant, built
/// from the Stremio addons — see catalog.dart), joined by the addons' live search → its page with
/// rating, cast and where to watch. Before typing: what's popular. Matching apps and "search
/// everywhere / in an app" come after. ↓ from the field moves into the results.
class TvSearch extends StatefulWidget {
  const TvSearch({super.key, required this.apps, required this.onLaunch});
  final List<AppEntry> apps;
  final void Function(AppEntry) onLaunch;

  @override
  State<TvSearch> createState() => _TvSearchState();
}

class _TvSearchState extends State<TvSearch> {
  final _q = TextEditingController();
  final _firstApp = FocusNode(), _firstAction = FocusNode();
  // One focus node per poster, kept by title: when the results re-rank, focus stays on the poster
  // it was on (a node never moves to another poster).
  final _posterNodes = <String, FocusNode>{};
  Set<String> _shown = const {};
  List<String> _targets = const []; // apps that accept a search

  Timer? _debounce;
  Catalog get _catalog => Catalog.instance;
  int _seen = -1; // the catalog version the results come from
  List<ShowTitle> _local = const []; // from the TV's catalog (as you type)
  String _searched = ''; // what the live search last asked
  List<ShowTitle> _live = const []; // the sources' own search (Cinemeta…)
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    TvApps.instance.searchTargets().then((t) {
      if (mounted) setState(() => _targets = t);
    });
    _catalog.addListener(_onCatalog);
    // No catalog yet (first run): make it now rather than at the next automatic check.
    _catalog.load().then((_) {
      if (_catalog.count == 0) _catalog.maybeUpdate();
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
    _q.dispose();
    for (final n in _posterNodes.values) {
      n.dispose();
    }
    _firstApp.dispose();
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

  FocusNode _posterNode(ShowTitle t) => _posterNodes[t.key] ??= FocusNode(debugLabel: 'poster');

  /// After a frame: let go of the nodes of posters no longer shown.
  void _dropStaleNodes() {
    if (!mounted) return;
    _posterNodes.removeWhere((k, n) {
      if (_shown.contains(k)) return false;
      n.dispose();
      return true;
    });
  }

  void _openTitle(ShowTitle t) =>
      Navigator.of(context).push(tvFade(TvTitlePage(title: t, apps: widget.apps, searchTargets: _targets, onOpenApp: widget.onLaunch)));

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
    final posters = q.isEmpty ? _catalog.trending() : combineResults(raw, _local, _searched == raw ? _live : const []);
    final searchOn = Catalog.enabled;
    final shown = posters.take(18).toList();
    _shown = {for (final t in shown) t.key};
    if (_posterNodes.length > _shown.length) WidgetsBinding.instance.addPostFrameCallback((_) => _dropStaleNodes());

    List<Widget> googleRow(String title) => [
      const SizedBox(height: DS.s20),
      Text(TvMetro.cased(title), style: TvMetro.headerOr(TvDS.rowTitleFocused)),
      const SizedBox(height: DS.s12),
      Wrap(
        spacing: DS.s12,
        runSpacing: DS.s12,
        children: [
          if (raw.isNotEmpty)
            TvActionPill(
              focusNode: _firstAction,
              icon: Icons.travel_explore_rounded,
              label: 'Search Google TV for “$raw”',
              onSelect: () => TvApps.instance.searchEverywhere(raw),
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
                onSelect: () => TvApps.instance.searchIn(a.package, raw),
              ),
        ],
      ),
    ];

    // ↓ from the box: the first poster when there are shows & films, else the first matching app,
    // else the Google TV row.
    void down() {
      final to = searchOn && shown.isNotEmpty ? _posterNode(shown.first) : (apps.isNotEmpty ? _firstApp : _firstAction);
      to.requestFocus();
    }

    return Scaffold(
      backgroundColor: TvDS.canvas,
      body: Padding(
        padding: EdgeInsets.fromLTRB(TvDS.safe.left, TvDS.safe.top, TvDS.safe.right, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tiles: the page's name, big and light, like "start".
            if (metro) ...[Text(TvMetro.cased('Search'), style: TvMetro.title(size: 40).copyWith(height: 1)), const SizedBox(height: DS.s16)],
            Focus(
              // The field keeps ↓ for itself; send it to the results instead.
              onKeyEvent: (_, e) {
                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown) {
                  down();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: _onType,
                // Enter / Done on the keyboard: straight to Google TV's results (unless our own
                // shows & films search is on — then into those results).
                onSubmitted: (_) => raw.isNotEmpty && !searchOn ? TvApps.instance.searchEverywhere(raw) : down(),
                style: metro ? TvDS.panelTitle.copyWith(fontWeight: FontWeight.w300) : TvDS.panelTitle,
                cursorColor: TvDS.ink,
                decoration: InputDecoration(
                  hintText: TvMetro.cased('Shows, films, YouTube, apps'),
                  hintStyle: (metro ? TvDS.panelTitle.copyWith(fontWeight: FontWeight.w300) : TvDS.panelTitle).copyWith(color: TvDS.inkMuted),
                  prefixIcon: const Icon(Icons.search_rounded, color: TvDS.inkMuted, size: 28),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(DS.s16),
                          child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: TvDS.inkMuted)),
                        )
                      : null,
                  filled: true,
                  fillColor: TvDS.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: DS.s16),
                  // Tiles: a flat field with the tile corners and the Metro focus frame.
                  border: OutlineInputBorder(borderRadius: TvMetro.corners(32), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: TvMetro.corners(32),
                    borderSide: BorderSide(color: metro ? TvMetro.focus : TvDS.ink, width: 2),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                clipBehavior: Clip.none,
                padding: EdgeInsets.only(bottom: TvDS.safe.bottom + DS.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // With our own shows & films search on, those come first; Google TV's search
                    // and voice follow ("More ways to search"). Without it, Google TV leads.
                    if (!searchOn) ...googleRow('Search with Google TV'),

                    // ---- Shows & films ----
                    if (searchOn) ...[
                      const SizedBox(height: DS.s24),
                      Text(TvMetro.cased(q.isEmpty ? 'Popular now' : 'Shows & films'), style: TvMetro.headerOr(TvDS.rowTitleFocused)),
                      const SizedBox(height: DS.s16),
                      if (posters.isEmpty)
                        Text(TvMetro.cased(_emptyNote(raw)), style: TvDS.heroBody)
                      else
                        Wrap(
                          spacing: DS.s16,
                          runSpacing: DS.s20,
                          children: [for (final t in shown) TvPoster(key: ValueKey(t.key), title: t, focusNode: _posterNode(t), onSelect: () => _openTitle(t))],
                        ),
                    ],

                    // ---- Apps ----
                    if (apps.isNotEmpty) ...[
                      const SizedBox(height: DS.s24),
                      Text('${apps.length} ${apps.length == 1 ? 'app' : 'apps'}', style: TvMetro.headerOr(TvDS.rowTitleFocused)),
                      Wrap(
                        spacing: TvDS.gap,
                        children: [
                          for (final (i, a) in apps.indexed)
                            TvAppTile(
                              key: ValueKey(a.package),
                              app: a,
                              focusNode: i == 0 ? _firstApp : null,
                              onSelect: () => widget.onLaunch(a),
                              onOptions: () {},
                            ),
                        ],
                      ),
                    ],
                    if (searchOn) ...googleRow('More ways to search'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
