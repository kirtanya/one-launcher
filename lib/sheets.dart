import 'package:flutter/material.dart';

import 'apps.dart';
import 'prefs.dart';
import 'tokens.dart';
import 'widgets.dart';

/// Long-press an app in the drawer.
Future<void> showAppSheet(BuildContext context, {required Prefs prefs, required AppEntry app}) {
  final fav = prefs.isFavourite(app.package);
  final hidden = prefs.hidden.contains(app.package);
  final full = !fav && prefs.favouritesFull;
  void done(Future<void> Function() f) {
    Navigator.pop(context);
    f();
  }

  return showOneSheet(
    context,
    header: SheetHeader(title: app.label, leading: AppIcon(app, size: 44)),
    actions: [
      SheetAction(
        fav ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
        fav ? 'Remove from home' : (full ? 'Home is full (${Prefs.maxFavourites})' : 'Add to home'),
        () => done(() => prefs.toggleFavourite(app.package)),
        enabled: !full,
      ),
      SheetAction(
        hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        hidden ? 'Show in app list' : 'Hide from app list',
        () => done(() => prefs.toggleHidden(app.package)),
      ),
      SheetAction(Icons.info_outline_rounded, 'App info', () => done(() => Apps.instance.appInfo(app.package))),
      if (!app.system) SheetAction(Icons.delete_outline_rounded, 'Uninstall', () => done(() => Apps.instance.uninstall(app.package)), danger: true),
    ],
  );
}

/// Long-press a favourite on the home screen.
Future<void> showFavouriteSheet(BuildContext context, {required Prefs prefs, required AppEntry app}) {
  final i = prefs.favourites.indexOf(app.package);
  final last = prefs.favourites.length - 1;
  void done(Future<void> Function() f) {
    Navigator.pop(context);
    f();
  }

  return showOneSheet(
    context,
    header: SheetHeader(title: app.label, subtitle: 'On your home screen', leading: AppIcon(app, size: 44)),
    actions: [
      SheetAction(Icons.arrow_upward_rounded, 'Move up', () => done(() => prefs.moveFavourite(app.package, -1)), enabled: i > 0),
      SheetAction(Icons.arrow_downward_rounded, 'Move down', () => done(() => prefs.moveFavourite(app.package, 1)), enabled: i < last),
      SheetAction(Icons.info_outline_rounded, 'App info', () => done(() => Apps.instance.appInfo(app.package))),
      SheetAction(Icons.remove_circle_outline_rounded, 'Remove from home', () => done(() => prefs.toggleFavourite(app.package)), danger: true),
    ],
  );
}

/// Long-press empty space on the home screen.
Future<void> showSettingsSheet(BuildContext context, {required Prefs prefs, required List<AppEntry> apps}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: T.sheet,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(T.rSheet))),
    builder: (ctx) => ListenableBuilder(
      listenable: prefs,
      builder: (ctx, _) {
        final hidden = apps.where((a) => prefs.hidden.contains(a.package)).toList();
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(T.s24, 0, T.s24, T.s8),
              child: SheetHeader(title: 'One Launcher', subtitle: 'Long-press the home screen to come back here'),
            ),
            _Toggle('Show icons on home', prefs.showHomeIcons, prefs.setShowHomeIcons),
            _Toggle('Open app when search finds only one', prefs.autoOpenSingleMatch, prefs.setAutoOpenSingleMatch),
            const Divider(color: T.divider, height: T.s16),
            _Row(Icons.wallpaper_rounded, 'Change wallpaper', () {
              Navigator.pop(ctx);
              Apps.instance.openWallpaperPicker();
            }),
            _Row(Icons.home_outlined, 'Make One Launcher your home app', () {
              Navigator.pop(ctx);
              Apps.instance.openHomeSettings();
            }),
            if (hidden.isNotEmpty) ...[
              const Divider(color: T.divider, height: T.s16),
              const Padding(
                padding: EdgeInsets.fromLTRB(T.s24, T.s8, T.s24, T.s4),
                child: Text('HIDDEN APPS', style: T.label),
              ),
              for (final a in hidden)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: T.s24),
                  leading: AppIcon(a, size: 32),
                  title: Text(a.label, style: T.appName),
                  trailing: TextButton(onPressed: () => prefs.toggleHidden(a.package), child: const Text('Show')),
                ),
            ],
            const SizedBox(height: T.s12),
          ]),
        );
      },
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: T.s24),
      title: Text(label, style: T.appName),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: T.s24),
      leading: Icon(icon, color: T.ink),
      title: Text(label, style: T.appName),
      onTap: onTap,
    );
  }
}
