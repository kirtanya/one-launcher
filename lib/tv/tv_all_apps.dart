import 'package:flutter/material.dart';

import '../apps.dart';
import '../prefs.dart';
import '../ui/ds.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_metro.dart';
import 'tv_parts.dart';
import 'tv_tiles.dart';

/// Every app on the TV in one grid (Your apps → All apps). Sort A–Z or newest first;
/// Hold OK for an app's options. Back returns home.
class TvAllApps extends StatefulWidget {
  const TvAllApps({super.key, required this.apps, required this.prefs, required this.onLaunch});
  final List<AppEntry> apps; // visible apps (hidden ones excluded)
  final Prefs prefs;
  final void Function(AppEntry) onLaunch;

  @override
  State<TvAllApps> createState() => _TvAllAppsState();
}

class _TvAllAppsState extends State<TvAllApps> {
  bool _newest = false;
  final _firstApp = FocusNode();

  Prefs get prefs => widget.prefs;

  @override
  void dispose() {
    _firstApp.dispose();
    super.dispose();
  }

  void _options(AppEntry a) {
    final fav = prefs.favourites.contains(a.package);
    final quick = prefs.tvQuickActions.contains('a:${a.package}');
    showTvPanel(
      context,
      title: a.label,
      leading: TvAppArt(app: a, width: 128),
      actions: [
        TvAction(Icons.open_in_new_rounded, 'Open', () => widget.onLaunch(a)),
        // Tiles view: pin the app to Start as a tile.
        if (prefs.homeView == 'tiles')
          TvAction(
            Icons.push_pin_outlined,
            tvPinned(prefs, widget.apps, a.package) ? 'Unpin from Start' : 'Pin to Start',
            () => tvTogglePin(prefs, widget.apps, a.package),
          ),
        if (fav)
          TvAction(Icons.star_outline_rounded, 'Remove from Your apps', () => prefs.toggleFavourite(a.package))
        else if (!prefs.favouritesFull)
          TvAction(Icons.star_rounded, 'Add to Your apps', () => prefs.toggleFavourite(a.package)),
        TvAction(
          Icons.bolt_rounded,
          quick ? 'Remove from quick actions' : 'Add to quick actions',
          () => prefs.setTvQuickActions(quick ? ([...prefs.tvQuickActions]..remove('a:${a.package}')) : [...prefs.tvQuickActions, 'a:${a.package}']),
        ),
        TvAction(Icons.visibility_off_outlined, 'Hide', () => prefs.toggleHidden(a.package)),
        TvAction(Icons.info_outline_rounded, 'App info', () => TvApps.instance.appInfo(a.package)),
        if (!a.system) TvAction(Icons.delete_outline_rounded, 'Uninstall', () => TvApps.instance.uninstall(a.package), danger: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final hidden = prefs.hidden.toSet();
        final apps = [
          for (final a in widget.apps)
            if (!hidden.contains(a.package)) a,
        ];
        final metro = TvMetro.on;
        apps.sort(_newest ? (a, b) => b.installed.compareTo(a.installed) : (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
        return Scaffold(
          backgroundColor: TvDS.canvas,
          body: SingleChildScrollView(
            clipBehavior: Clip.none,
            padding: EdgeInsets.fromLTRB(TvDS.safe.left, TvDS.safe.top, TvDS.safe.right, TvDS.safe.bottom + DS.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (metro)
                      Text(TvMetro.cased('All apps'), style: TvMetro.title(size: 40).copyWith(height: 1))
                    else
                      Text('All apps', style: TvDS.heroTitle.copyWith(fontSize: 32)),
                    const SizedBox(width: DS.s12),
                    Text('${apps.length}', style: TvDS.heroMeta.copyWith(color: metro ? TvMetro.accentText : TvDS.inkMuted)),
                    const Spacer(),
                    // Sort: A–Z / newest installed first.
                    TvActionPill(
                      icon: _newest ? Icons.schedule_rounded : Icons.sort_by_alpha_rounded,
                      label: _newest ? 'Newest first' : 'A–Z',
                      detail: 'Sort',
                      onSelect: () => setState(() => _newest = !_newest),
                    ),
                  ],
                ),
                const SizedBox(height: DS.s8),
                Wrap(
                  spacing: TvDS.gap,
                  children: [
                    for (final (i, a) in apps.indexed) ...[
                      // Tiles, A–Z: a letter tile opens each letter's group, like Metro's app list.
                      if (metro && !_newest && (i == 0 || _letter(apps[i - 1]) != _letter(a))) _LetterTile(_letter(a)),
                      TvAppTile(
                        key: ValueKey(a.package),
                        app: a,
                        focusNode: i == 0 ? _firstApp : null,
                        onSelect: () => widget.onLaunch(a),
                        onOptions: () => _options(a),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _letter(AppEntry a) {
    final c = a.label.isEmpty ? '#' : a.label[0].toLowerCase();
    return RegExp(r'[a-z]').hasMatch(c) ? c : '#';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstApp.requestFocus());
  }
}

/// Tiles' All apps: the letter that starts a group, as an outlined accent square (not focusable).
class _LetterTile extends StatelessWidget {
  const _LetterTile(this.letter);
  final String letter;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: TvDS.rowPadTop),
    child: Container(
      width: TvDS.tileH,
      height: TvDS.tileH,
      padding: const EdgeInsets.all(DS.s12),
      alignment: Alignment.bottomLeft,
      decoration: BoxDecoration(
        borderRadius: TvMetro.corners(0),
        border: Border.all(color: TvMetro.accentText, width: 2),
      ),
      child: Text(letter, style: TvMetro.title(size: 40).copyWith(color: TvMetro.accentText, height: 1)),
    ),
  );
}
