import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../prefs.dart';
import '../ui/ds.dart';
import 'catalog.dart';
import 'tv_ds.dart';
import 'tv_parts.dart';

/// Customise → Search: the shows & films catalog search uses — update it now, when it last
/// updated, how many titles it has, and where they come from (Sources).
List<TvAction> catalogRows(BuildContext context, Prefs prefs, {required VoidCallback reopen}) {
  final c = Catalog.instance;
  return [
    TvAction(
      Icons.sync_rounded,
      c.syncing ? 'Updating the catalog…' : 'Update catalog now',
      () => c.update(),
      keepOpen: true,
      value: c.syncing ? '${(c.progress * 100).round()}%' : (c.error != null ? 'Didn’t work' : null),
    ),
    TvAction(Icons.history_rounded, 'Last updated', () {}, keepOpen: true, value: agoLabel(c.updated, DateTime.now())),
    TvAction(Icons.movie_filter_outlined, 'Titles in catalog', () {}, keepOpen: true, value: _thousands(c.count)),
    TvAction(
      Icons.hub_outlined,
      'Sources',
      () => showCatalogSources(context, prefs, back: reopen),
      value: '${c.enabledSources.length} of ${c.sources.length} on',
    ),
  ];
}

/// 12345 → "12,345".
String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Sources: the Stremio addons the catalog is built from. OK on one → switch off / remove;
/// "Add a source" takes a manifest link.
void showCatalogSources(BuildContext context, Prefs prefs, {required VoidCallback back}) {
  final c = Catalog.instance;
  void reopen() => showCatalogSources(context, prefs, back: back);
  showTvPanel(
    context,
    title: 'Sources',
    refresh: Listenable.merge([prefs, c]),
    build: () => [
      TvAction(Icons.arrow_back_rounded, 'Back', back),
      for (final url in c.sources)
        TvAction(
          c.isOn(url) ? Icons.toggle_on_rounded : Icons.toggle_off_outlined,
          c.sourceName(url),
          () => _source(context, url, back: reopen),
          value: c.sourceRole(url),
        ),
      TvAction(Icons.add_rounded, 'Add a source', () => Navigator.of(context).push(tvFade(const _AddSource())).then((_) => reopen())),
      TvAction(Icons.restart_alt_rounded, 'Reset sources', () => _confirmReset(context, back: reopen)),
    ],
  );
}

/// Reset sources removes every source the user typed in: ask first. Either way, back to Sources
/// (focus on its Back row).
void _confirmReset(BuildContext context, {required VoidCallback back}) {
  final n = Catalog.buildSources.length;
  showTvPanel(
    context,
    title: 'Reset to $n ${n == 1 ? 'source' : 'sources'}?',
    actions: [
      TvAction(Icons.arrow_back_rounded, 'Cancel', back),
      TvAction(Icons.restart_alt_rounded, 'Reset (removes the sources you added)', () async {
        await Catalog.instance.resetSources();
        back();
      }, danger: true),
    ],
  );
}

/// One source: switch it off / on, or remove it.
void _source(BuildContext context, String url, {required VoidCallback back}) {
  final c = Catalog.instance;
  final on = c.isOn(url);
  showTvPanel(
    context,
    title: c.sourceName(url),
    actions: [
      TvAction(Icons.arrow_back_rounded, 'Back', back),
      TvAction(on ? Icons.toggle_off_outlined : Icons.toggle_on_rounded, on ? 'Switch off' : 'Switch on', () async {
        await c.setSourceOn(url, !on);
        back();
      }),
      TvAction(Icons.delete_outline_rounded, 'Remove', () async {
        await c.removeSource(url);
        back();
      }, danger: true),
    ],
  );
}

/// Add a source: type (or paste from the phone remote) an addon's manifest link; it's checked
/// before it joins the list.
class _AddSource extends StatefulWidget {
  const _AddSource();

  @override
  State<_AddSource> createState() => _AddSourceState();
}

class _AddSourceState extends State<_AddSource> {
  final _link = TextEditingController();
  final _add = FocusNode();
  bool _checking = false;
  String? _problem;

  @override
  void dispose() {
    _link.dispose();
    _add.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _problem = null;
    });
    // Back / Cancel while it's checking: the source isn't added after all.
    final problem = await Catalog.instance.addSource(_link.text, stillWanted: () => mounted);
    if (!mounted) return;
    if (problem == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _checking = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvDS.canvas,
      body: Padding(
        padding: EdgeInsets.fromLTRB(TvDS.safe.left, 64, TvDS.safe.right, TvDS.safe.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a source', style: TvDS.heroTitle.copyWith(fontSize: 32)),
            const SizedBox(height: DS.s12),
            const SizedBox(
              width: 620,
              child: Text(
                'A Stremio addon’s manifest link (it ends with /manifest.json). Its catalogs and details join search. Streams are never used.',
                style: TvDS.heroBody,
              ),
            ),
            const SizedBox(height: DS.s24),
            Focus(
              // The field keeps ↓ for itself; send it to the buttons instead.
              onKeyEvent: (_, e) {
                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _add.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _link,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _submit(),
                style: TvDS.panelRow,
                cursorColor: TvDS.ink,
                decoration: InputDecoration(
                  hintText: 'https://…/manifest.json',
                  hintStyle: TvDS.panelRow.copyWith(color: TvDS.inkMuted),
                  prefixIcon: const Icon(Icons.link_rounded, color: TvDS.inkMuted, size: 24),
                  filled: true,
                  fillColor: TvDS.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: DS.s16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: const BorderSide(color: TvDS.ink, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: DS.s16),
            Row(
              children: [
                TvActionPill(focusNode: _add, icon: Icons.add_rounded, label: _checking ? 'Checking…' : 'Add', onSelect: _submit),
                const SizedBox(width: DS.s12),
                TvActionPill(icon: Icons.close_rounded, label: 'Cancel', onSelect: () => Navigator.pop(context)),
              ],
            ),
            if (_problem != null) ...[const SizedBox(height: DS.s16), Text(_problem!, style: TvDS.heroBody.copyWith(color: TvDS.ink))],
          ],
        ),
      ),
    );
  }
}
