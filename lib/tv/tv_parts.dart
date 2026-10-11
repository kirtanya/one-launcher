import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';

/// Shared TV pieces: app tiles + artwork, the options side panel, search.

PageRoute<void> tvFade(Widget page) => PageRouteBuilder(
  pageBuilder: (_, _, _) => page,
  transitionDuration: const Duration(milliseconds: 220),
  reverseTransitionDuration: const Duration(milliseconds: 160),
  transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
);

// ---- Tiles -------------------------------------------------------------------

class TvAppTile extends StatelessWidget {
  const TvAppTile({super.key, required this.app, required this.focusNode, required this.onSelect, required this.onOptions, this.onMove, this.onFocus});
  final AppEntry app;
  final FocusNode? focusNode;
  final VoidCallback onSelect, onOptions;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: app.label,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onLongSelect: onOptions,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => SizedBox(
          width: TvDS.tileW,
          child: Column(
            children: [
              const SizedBox(height: TvDS.rowPadTop),
              AnimatedScale(
                scale: f ? TvDS.focusScale : 1,
                duration: Motion.popDuration,
                curve: Motion.pop,
                child: AnimatedContainer(
                  duration: Motion.pressIn * 2,
                  width: TvDS.tileW,
                  height: TvDS.tileH,
                  // Ring + glow only on the focused tile (one blur on screen at a time).
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    border: Border.all(color: f ? TvDS.surfaceFocused : Colors.transparent, width: TvDS.focusRing),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    boxShadow: f ? const [BoxShadow(color: TvDS.glow, blurRadius: 18)] : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    child: TvAppArt(app: app, width: TvDS.tileW),
                  ),
                ),
              ),
              const SizedBox(height: DS.s12),
              // Name under the focused tile — banners are just artwork; icon tiles already show it.
              AnimatedOpacity(
                opacity: f && (TvApps.instance.artNow(app.package)?.banner ?? false) ? 1 : 0,
                duration: Motion.pressIn * 2,
                child: Text(app.label, style: TvDS.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app's banner, or (no banner) its icon + name on a soft tile.
class TvAppArt extends StatelessWidget {
  const TvAppArt({super.key, required this.app, required this.width});
  final AppEntry app;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ready = TvApps.instance.artNow(app.package);
    return SizedBox(
      width: width,
      height: width * 9 / 16,
      child: ready != null
          ? _view(ready)
          : FutureBuilder<TvArt?>(future: TvApps.instance.art(app.package), builder: (context, s) => s.data != null ? _view(s.data!) : _fallback(null)),
    );
  }

  Widget _view(TvArt art) =>
      art.banner ? Image(image: art.image, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium) : _fallback(art.image);

  Widget _fallback(ImageProvider? icon) {
    final s = width / TvDS.tileW;
    return ColoredBox(
      color: TvDS.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 44 * s,
            child: icon != null
                ? Image(image: icon, gaplessPlayback: true, filterQuality: FilterQuality.medium)
                : DecoratedBox(
                    decoration: BoxDecoration(color: DS.hero, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        app.label.isEmpty ? '?' : app.label[0].toUpperCase(),
                        style: TvDS.tileName.copyWith(color: DS.heroInk, fontSize: 20 * s),
                      ),
                    ),
                  ),
          ),
          SizedBox(height: DS.s8 * s),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: DS.s8 * s),
            child: Text(
              app.label,
              style: TvDS.tileName.copyWith(fontSize: 13 * s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Side panel (options) ------------------------------------------------------

class TvAction {
  const TvAction(this.icon, this.label, this.onSelect, {this.danger = false, this.keepOpen = false});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool danger;
  final bool keepOpen; // e.g. clock presets: try several without reopening
}

/// Options slide in from the right, like the TV's own menus. Back closes.
Future<void> showTvPanel(BuildContext context, {required String title, Widget? leading, required List<TvAction> actions}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: const Color(0xFF1C1C1C),
        child: SizedBox(
          width: 380,
          height: double.infinity,
          child: FocusTraversalGroup(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(DS.s32, 40, DS.s32, 40),
              children: [
                if (leading != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(borderRadius: BorderRadius.circular(TvDS.rTile), child: leading),
                  ),
                  const SizedBox(height: DS.s16),
                ],
                Text(title, style: TvDS.panelTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: DS.s24),
                for (final (i, a) in actions.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DS.s8),
                    child: TvFocusable(
                      autofocus: i == 0,
                      onSelect: () {
                        if (!a.keepOpen) Navigator.pop(ctx);
                        a.onSelect();
                      },
                      builder: (context, f) => AnimatedContainer(
                        duration: Motion.pressIn * 2,
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                        decoration: BoxDecoration(color: f ? TvDS.surfaceFocused : Colors.transparent, borderRadius: BorderRadius.circular(26)),
                        child: Row(
                          children: [
                            Icon(a.icon, size: 22, color: f ? (a.danger ? DS.alert : DS.ink) : (a.danger ? DS.alert : TvDS.inkMuted)),
                            const SizedBox(width: DS.s16),
                            Expanded(
                              child: Text(
                                a.label,
                                style: TvDS.panelRow.copyWith(color: f ? DS.ink : TvDS.ink),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(.3, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: a, child: child),
    ),
  );
}

// ---- Search --------------------------------------------------------------------

/// Type with the TV keyboard (or voice), results fill in as tiles; ↓ moves into them.
class TvSearch extends StatefulWidget {
  const TvSearch({super.key, required this.apps, required this.onLaunch});
  final List<AppEntry> apps;
  final void Function(AppEntry) onLaunch;

  @override
  State<TvSearch> createState() => _TvSearchState();
}

/// Type a show, film or app. Shows & films: "Search everywhere" hands the words to Google TV's
/// own search (results from every streaming app), or straight to an app that takes searches.
/// Apps: matching tiles below. ↓ from the field moves into the results.
class _TvSearchState extends State<TvSearch> {
  final _q = TextEditingController();
  final _firstAction = FocusNode();
  final _firstApp = FocusNode();
  List<String> _targets = const []; // apps that accept a search

  @override
  void initState() {
    super.initState();
    TvApps.instance.searchTargets().then((t) {
      if (mounted) setState(() => _targets = t);
    });
  }

  @override
  void dispose() {
    _q.dispose();
    _firstAction.dispose();
    _firstApp.dispose();
    super.dispose();
  }

  void _go(VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final raw = _q.text.trim();
    final q = raw.toLowerCase();
    final results = q.isEmpty
        ? (widget.apps.toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())))
        : (widget.apps.where((a) => a.label.toLowerCase().contains(q)).toList()
            ..sort((a, b) => (a.label.toLowerCase().startsWith(q) ? 0 : 1).compareTo(b.label.toLowerCase().startsWith(q) ? 0 : 1)));
    final byPkg = {for (final a in widget.apps) a.package: a};
    final targets = [for (final p in _targets) ?byPkg[p]];
    final hasActions = raw.isNotEmpty;
    void down() => (hasActions ? _firstAction : _firstApp).requestFocus();

    return Scaffold(
      backgroundColor: TvDS.canvas,
      body: Padding(
        padding: TvDS.safe,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              // The field keeps ↓ for itself; send it to the results instead.
              onKeyEvent: (_, e) {
                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown && (hasActions || results.isNotEmpty)) {
                  down();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (hasActions || results.isNotEmpty) down();
                },
                style: TvDS.panelTitle,
                cursorColor: TvDS.ink,
                decoration: InputDecoration(
                  hintText: 'Search shows, films and apps',
                  hintStyle: TvDS.panelTitle.copyWith(color: TvDS.inkMuted),
                  prefixIcon: const Icon(Icons.search_rounded, color: TvDS.inkMuted, size: 28),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasActions) ...[
                      const SizedBox(height: DS.s20),
                      const Text('Shows & films', style: TvDS.rowTitle),
                      const SizedBox(height: DS.s12),
                      Wrap(
                        spacing: DS.s12,
                        runSpacing: DS.s12,
                        children: [
                          _SearchPill(
                            focusNode: _firstAction,
                            icon: Icons.travel_explore_rounded,
                            label: 'Search everywhere for “$raw”',
                            onSelect: () => _go(() => TvApps.instance.searchEverywhere(raw)),
                          ),
                          for (final a in targets)
                            _SearchPill(app: a, label: 'Search in ${a.label}', onSelect: () => _go(() => TvApps.instance.searchIn(a.package, raw))),
                        ],
                      ),
                    ],
                    const SizedBox(height: DS.s20),
                    Text(q.isEmpty ? 'All apps' : '${results.length} ${results.length == 1 ? 'app' : 'apps'}', style: TvDS.rowTitle),
                    Wrap(
                      spacing: TvDS.gap,
                      children: [
                        for (final (i, a) in results.indexed)
                          TvAppTile(
                            key: ValueKey(a.package),
                            app: a,
                            focusNode: i == 0 ? _firstApp : null,
                            onSelect: () => _go(() => widget.onLaunch(a)),
                            onOptions: () {},
                          ),
                      ],
                    ),
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

/// A search action: icon (or the app's own icon) + label; white when focused.
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.label, required this.onSelect, this.icon, this.app, this.focusNode});
  final String label;
  final VoidCallback onSelect;
  final IconData? icon;
  final AppEntry? app;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      onSelect: onSelect,
      builder: (context, f) => AnimatedScale(
        scale: f ? 1.06 : 1,
        duration: Motion.popDuration,
        curve: Motion.pop,
        child: AnimatedContainer(
          duration: Motion.pressIn * 2,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: DS.s16),
          decoration: BoxDecoration(color: f ? TvDS.surfaceFocused : TvDS.surface, borderRadius: BorderRadius.circular(24)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (app != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(width: 40, height: 22.5, child: TvAppArt(app: app!, width: 40)),
                )
              else
                Icon(icon, size: 22, color: f ? DS.ink : TvDS.ink),
              const SizedBox(width: DS.s12),
              Text(label, style: TvDS.panelRow.copyWith(fontSize: 15, color: f ? DS.ink : TvDS.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
