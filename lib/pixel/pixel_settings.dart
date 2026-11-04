import 'package:flutter/material.dart';

import '../apps.dart';
import '../app_lock_ui.dart';
import '../prefs.dart';
import '../sheets.dart' show showHiddenApps;
import 'pixel_icon.dart';
import 'pixel_model.dart';

/// Pixel view → long-press home → "Home settings": a full-screen Android-settings page like
/// Pixel Launcher's own (large collapsing title, plain rows, M3 switches, radio / slider dialogs).
/// Pixel's rows first, in its order, then our extras under small headers. Follows the theme.
Future<void> showPixelHomeSettings(BuildContext context, {required Prefs prefs}) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _PixelSettingsPage(prefs: prefs)));
}

class _PixelSettingsPage extends StatelessWidget {
  const _PixelSettingsPage({required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final s = PixelSettings.of(prefs);
        void set(String k, Object? v) => s.copyWith(k, v).save(prefs);
        return _Page(title: 'Home settings', children: [
          _SwitchRow('Notification dots', s.notifDots ? 'On' : 'Off', s.notifDots, (v) => set('notifDots', v)),
          _SwitchRow('At a Glance', s.glance ? 'On' : 'Off', s.glance, (v) => set('glance', v)),
          _SwitchRow('Add app icons to home screen', 'For new apps', s.addNewApps, (v) => set('addNewApps', v)),
          _SwitchRow('Swipe to access Google app', 'From home screen, swipe right to open Today', s.leftPanel, (v) => set('leftPanel', v)),
          _SwitchRow('Suggestions', 'For all apps and home screen suggestions', s.suggestions, (v) => set('suggestions', v)),
          _Row('Apps list settings', 'Choose appearance and behaviour defaults of the apps list', onTap: () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _AppsListPage(prefs: prefs)));
          }),
          _Row('Home view', 'Pixel', onTap: () => _pick<String>(context, 'Home view', prefs.homeView, const {'classic': 'Classic', 'tiles': 'Tiles', 'third': 'Real', 'pixel': 'Pixel'}, (v) {
            if (v == prefs.homeView) return;
            // After the dialog has closed: leave settings, then swap the home view.
            Future.microtask(() {
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              prefs.setHomeView(v);
            });
          })),
          const _Header('Grid & icons'),
          _Row('Home grid', s.grid.replaceAll('x', ' × '), onTap: () => _pick<String>(context, 'Home grid', s.grid, {for (final g in pixelGrids.keys) g: g.replaceAll('x', ' × ')}, (v) => set('grid', v))),
          _Row('Icon size', '${(s.iconScale * 100).round()}%', onTap: () => _slider(context, 'Icon size', (s.iconScale * 100).round(), 70, 130, 12, '%', (v) => set('iconScale', v / 100))),
          _Row('Icon shape', _cap(s.iconShape), onTap: () => _pick<String>(context, 'Icon shape', s.iconShape, {for (final sh in pixelShapes) sh: _cap(sh)}, (v) => set('iconShape', v), shapes: true)),
          _SwitchRow('Themed icons', 'Tint icons with your wallpaper colours', prefs.themedIcons, prefs.setThemedIcons),
          _SwitchRow('Labels on home', 'Show app names under home icons', s.labels, (v) => set('labels', v)),
          const _Header('Dock & search'),
          _Row('Dock icons', '${s.dockCount}', onTap: () => _slider(context, 'Dock icons', s.dockCount, 3, 7, 4, '', (v) => set('dockCount', v))),
          _SwitchRow('Scrolling dock', 'Swipe the dock sideways when it holds more', s.dockScroll, (v) => set('dockScroll', v)),
          _SwitchRow('Search bar', 'The Google search pill at the bottom', s.searchBar, (v) => set('searchBar', v)),
          const _Header('Home screen'),
          _SwitchRow('Lock home layout', 'Stop icons being moved or removed by accident', s.lockLayout, (v) => set('lockLayout', v)),
          _SwitchRow('Big folders', 'Open folders full screen with a bigger grid', s.bigFolders, (v) => set('bigFolders', v)),
          const _Header('Gestures'),
          _SwitchRow('Swipe down for notifications', 'Pull the shade down from the home screen', s.swipeDownShade, (v) => set('swipeDownShade', v)),
          _Row('Swipe up opens', s.swipeUp == 'search' ? 'Search' : 'All apps', onTap: () => _pick<String>(context, 'Swipe up opens', s.swipeUp, const {'drawer': 'All apps', 'search': 'Search'}, (v) => set('swipeUp', v))),
          const _Header('More'),
          _Row('Hidden apps', 'Apps kept out of home and all apps', onTap: () async {
            final apps = await Apps.instance.list();
            if (context.mounted) await showHiddenApps(context, prefs: prefs, apps: apps);
          }),
          _Row('App lock', 'Ask for a PIN to open chosen apps', onTap: () async {
            final apps = await Apps.instance.list();
            if (context.mounted) await showAppLockPage(context, prefs: prefs, apps: apps);
          }),
          _Row('Wallpaper & style', 'Change wallpaper, colours and themes', onTap: Apps.instance.openWallpaperPicker),
          _Row('Reset home layout', 'Clear pages, dock and folders; start fresh', onTap: () => _confirmReset(context)),
        ]);
      },
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset home layout?'),
        content: const Text('Your home pages, dock and folders go back to how a new home starts. Apps stay installed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) await prefs.setPixelLayout({});
  }
}

class _AppsListPage extends StatelessWidget {
  const _AppsListPage({required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final s = PixelSettings.of(prefs);
        void set(String k, Object? v) => s.copyWith(k, v).save(prefs);
        const sorts = {'az': 'A–Z', 'recent': 'Recent', 'most': 'Most used'};
        return _Page(title: 'Apps list settings', children: [
          _Row('Sort apps', sorts[s.drawerSort] ?? 'A–Z', onTap: () => _pick<String>(context, 'Sort apps', s.drawerSort, sorts, (v) => set('drawerSort', v))),
          _Row('Columns', '${s.drawerCols}', onTap: () => _slider(context, 'Columns', s.drawerCols, 4, 6, 2, '', (v) => set('drawerCols', v))),
          _SwitchRow('Labels in all apps', 'Show app names in the app drawer', s.drawerLabels, (v) => set('drawerLabels', v)),
          _SwitchRow('Keyboard on open', 'Start typing as soon as all apps opens', s.keyboardOnOpen, (v) => set('keyboardOnOpen', v)),
          _SwitchRow('Letter scroller', 'A–Z strip on the edge to jump around', s.letterScroller, (v) => set('letterScroller', v)),
        ]);
      },
    );
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ---- Android-settings look ----

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // The launcher's theme has a see-through scaffold (wallpaper behind home); settings is opaque, like Android's.
    final bg = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1B1B1B) : const Color(0xFFFEF7FF);
    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(slivers: [
        SliverAppBar.large(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          title: Text(title),
        ),
        SliverList(delegate: SliverChildListDelegate([...children, const SizedBox(height: 48)])),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 4),
    child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.sub, {this.trailing, this.onTap});
  final String title, sub;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 18, color: cs.onSurface)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 14, height: 1.3, color: cs.onSurfaceVariant)),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          ]),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(this.title, this.sub, this.value, this.onChanged);
  final String title, sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => _Row(title, sub, onTap: () => onChanged(!value), trailing: _pixelSwitch(context, value, onChanged));
}

/// Pixel's switch: in dark, an "on" switch is a white track with a black thumb; light keeps M3's primary.
Widget _pixelSwitch(BuildContext context, bool value, ValueChanged<bool> onChanged) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (!dark) return Switch(value: value, onChanged: onChanged);
  return Switch(
    value: value,
    onChanged: onChanged,
    activeTrackColor: Colors.white,
    activeThumbColor: Colors.black,
    inactiveTrackColor: const Color(0xFF3A3A3A),
    inactiveThumbColor: const Color(0xFF8E8E8E),
    trackOutlineColor: WidgetStatePropertyAll(value ? Colors.white : const Color(0xFF8E8E8E)),
  );
}

/// Radio dialog, like Android settings' list preferences.
Future<void> _pick<T>(BuildContext context, String title, T value, Map<T, String> options, ValueChanged<T> onPick, {bool shapes = false}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in options.entries)
            ListTile(
              onTap: () {
                onPick(e.key);
                Navigator.pop(ctx);
              },
              leading: Icon(e.key == value ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: e.key == value ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.onSurfaceVariant),
              title: Text(e.value),
              trailing: shapes
                  ? SizedBox.square(
                      dimension: 28,
                      child: ClipPath(clipper: PixelShape(e.key as String), child: ColoredBox(color: Theme.of(ctx).colorScheme.primary)),
                    )
                  : null,
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
    ),
  );
}

/// Dialog with a slider for a number.
Future<void> _slider(BuildContext context, String title, int value, int min, int max, int divisions, String unit, ValueChanged<int> onDone) {
  var v = value.toDouble();
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${v.round()}$unit', style: Theme.of(ctx).textTheme.headlineSmall),
          Slider(min: min.toDouble(), max: max.toDouble(), divisions: divisions, value: v, label: '${v.round()}$unit', onChanged: (x) => setState(() => v = x)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              onDone(v.round());
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}
