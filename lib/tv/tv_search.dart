import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../ui/ds.dart';
import 'tmdb.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_parts.dart';
import 'tv_title.dart';

/// Search, content first: type a show or film → posters (TMDB) → its page with ratings, cast
/// and where to watch. Before typing: what's trending. Matching apps and "search everywhere /
/// in an app" come after. ↓ from the field moves into the results.
class TvSearch extends StatefulWidget {
  const TvSearch({super.key, required this.apps, required this.onLaunch});
  final List<AppEntry> apps;
  final void Function(AppEntry) onLaunch;

  @override
  State<TvSearch> createState() => _TvSearchState();
}

class _TvSearchState extends State<TvSearch> {
  final _q = TextEditingController();
  final _firstPoster = FocusNode(), _firstApp = FocusNode(), _firstAction = FocusNode();
  List<String> _targets = const []; // apps that accept a search

  Timer? _debounce;
  String _searched = '';
  List<TmdbTitle> _trending = const [], _results = const [];
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    TvApps.instance.searchTargets().then((t) {
      if (mounted) setState(() => _targets = t);
    });
    if (Tmdb.enabled) {
      Tmdb.instance.trending().then(
        (t) {
          if (mounted) setState(() => _trending = t);
        },
        onError: (Object e) {
          if (mounted) setState(() => _error = e);
        },
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _firstPoster.dispose();
    _firstApp.dispose();
    _firstAction.dispose();
    super.dispose();
  }

  /// Ask TMDB once typing pauses (each key on a TV keyboard is slow; don't search per letter).
  void _onType(String _) {
    setState(() {});
    _debounce?.cancel();
    final q = _q.text.trim();
    if (!Tmdb.enabled) return;
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _loading = true);
      try {
        final r = await Tmdb.instance.search(q);
        if (!mounted || _q.text.trim() != q) return;
        setState(() {
          _searched = q;
          _results = r;
          _error = null;
        });
      } catch (e) {
        if (mounted) setState(() => _error = e);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  void _openTitle(TmdbTitle t) =>
      Navigator.of(context).push(tvFade(TvTitlePage(title: t, apps: widget.apps, searchTargets: _targets, onOpenApp: widget.onLaunch)));

  @override
  Widget build(BuildContext context) {
    final raw = _q.text.trim();
    final q = raw.toLowerCase();
    final apps = q.isEmpty
        ? const <AppEntry>[]
        : (widget.apps.where((a) => a.label.toLowerCase().contains(q)).toList()
            ..sort((a, b) => (a.label.toLowerCase().startsWith(q) ? 0 : 1).compareTo(b.label.toLowerCase().startsWith(q) ? 0 : 1)));
    final byPkg = {for (final a in widget.apps) a.package: a};
    final targets = [for (final p in _targets) ?byPkg[p]];
    final posters = q.isEmpty ? _trending : (_searched.toLowerCase() == q ? _results : const <TmdbTitle>[]);

    // ↓ from the box: the Google TV row first (it's always there), then posters / apps.
    void down() => _firstAction.requestFocus();

    return Scaffold(
      backgroundColor: TvDS.canvas,
      body: Padding(
        padding: EdgeInsets.fromLTRB(TvDS.safe.left, TvDS.safe.top, TvDS.safe.right, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                onSubmitted: (_) => raw.isNotEmpty && !Tmdb.enabled ? TvApps.instance.searchEverywhere(raw) : down(),
                style: TvDS.panelTitle,
                cursorColor: TvDS.ink,
                decoration: InputDecoration(
                  hintText: 'Shows, films, YouTube, apps',
                  hintStyle: TvDS.panelTitle.copyWith(color: TvDS.inkMuted),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(32), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(32),
                    borderSide: const BorderSide(color: TvDS.ink, width: 2),
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
                    // ---- Google TV: the TV's own search (every streaming app, YouTube, people) ----
                    const SizedBox(height: DS.s20),
                    const Text('Search with Google TV', style: TvDS.rowTitleFocused),
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

                    // ---- Shows & films ----
                    if (Tmdb.enabled) ...[
                      const SizedBox(height: DS.s24),
                      Text(q.isEmpty ? 'Trending this week' : 'Shows & films', style: TvDS.rowTitleFocused),
                      const SizedBox(height: DS.s16),
                      if (_error != null && posters.isEmpty)
                        Text(_error is TmdbException ? '$_error.' : 'Couldn’t reach TMDB. Check the TV’s internet.', style: TvDS.heroBody)
                      else if (posters.isEmpty)
                        Text(q.isEmpty || _loading || _searched.toLowerCase() != q ? 'Loading…' : 'No shows or films called “$raw”.', style: TvDS.heroBody)
                      else
                        Wrap(
                          spacing: DS.s16,
                          runSpacing: DS.s20,
                          children: [
                            for (final (i, t) in posters.take(18).indexed)
                              TvPoster(key: ValueKey(t.key), title: t, focusNode: i == 0 ? _firstPoster : null, onSelect: () => _openTitle(t)),
                          ],
                        ),
                    ],

                    // ---- Apps ----
                    if (apps.isNotEmpty) ...[
                      const SizedBox(height: DS.s24),
                      Text('${apps.length} ${apps.length == 1 ? 'app' : 'apps'}', style: TvDS.rowTitleFocused),
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
