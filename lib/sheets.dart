import 'package:flutter/material.dart';

import 'apps.dart';
import 'folders.dart';
import 'prefs.dart';
import 'ui/components.dart';
import 'ui/ds.dart';
import 'widgets.dart';

/// Long-press an app in the app view.
Future<void> showAppSheet(BuildContext context, {required Prefs prefs, required AppEntry app}) {
  final fav = prefs.isFavourite(app.package);
  final hidden = prefs.hidden.contains(app.package);
  final full = !fav && prefs.favouritesFull;
  final folder = folderFor(app, prefs.folderOverrides);
  void done(Future<void> Function() f) {
    Navigator.pop(context);
    f();
  }

  return showOneSheet(
    context,
    header: SheetHeader(title: app.label, subtitle: 'In ${folder.name}', leading: AppIcon(app, size: 48)),
    actions: [
      SheetAction(
        fav ? Icons.push_pin : Icons.push_pin_outlined,
        fav ? 'Unpin' : (full ? 'Pins are full (${Prefs.maxFavourites})' : 'Pin to top'),
        () => done(() => prefs.toggleFavourite(app.package)),
        enabled: !full,
      ),
      SheetAction(Icons.drive_file_move_outline, 'Move to folder', () {
        Navigator.pop(context);
        showFolderPicker(context, prefs: prefs, app: app);
      }),
      SheetAction(
        hidden ? Icons.visibility_rounded : Icons.visibility_off_outlined,
        hidden ? 'Show in app list' : 'Hide from app list',
        () => done(() => prefs.toggleHidden(app.package)),
      ),
      SheetAction(Icons.info_outline_rounded, 'App info', () => done(() => Apps.instance.appInfo(app.package))),
      if (!app.system) SheetAction(Icons.delete_outline_rounded, 'Uninstall', () => done(() => Apps.instance.uninstall(app.package)), danger: true),
    ],
  );
}

/// Pick which folder an app lives in. "Automatic" goes back to the smart guess.
Future<void> showFolderPicker(BuildContext context, {required Prefs prefs, required AppEntry app}) {
  final manual = prefs.folderOverrides[app.package];
  final current = folderFor(app, prefs.folderOverrides).id;
  void pick(String? id) {
    Navigator.pop(context);
    prefs.setFolder(app.package, id);
  }

  Widget check(bool on) => on ? const Icon(Icons.check_rounded, color: DS.ink) : const SizedBox.shrink();

  return showOneSheet(
    context,
    header: SheetHeader(title: 'Move ${app.label}', subtitle: 'Choose a folder', leading: AppIcon(app, size: 48)),
    actions: [
      SheetAction(Icons.auto_awesome_outlined, 'Automatic', () => pick(null), trailing: check(manual == null)),
      for (final f in [...folders, other]) SheetAction(f.icon, f.name, () => pick(f.id), trailing: check(manual != null && current == f.id)),
    ],
  );
}

/// Long-press empty space on the home screen, or the settings button in the app view.
Future<void> showSettingsSheet(BuildContext context, {required Prefs prefs, required List<AppEntry> apps}) {
  return showOneSheetWith(
    context,
    builder: (ctx) => ListenableBuilder(
      listenable: prefs,
      builder: (ctx, _) {
        final hidden = apps.where((a) => prefs.hidden.contains(a.package)).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
              child: SheetHeader(title: 'One Launcher', subtitle: 'Long-press the clock to come back here'),
            ),
            _Toggle('Open app when search finds only one', prefs.autoOpenSingleMatch, prefs.setAutoOpenSingleMatch),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: DS.s8),
              child: CardDivider(),
            ),
            _Row(Icons.wallpaper_rounded, 'Change wallpaper', () {
              Navigator.pop(ctx);
              Apps.instance.openWallpaperPicker();
            }),
            _Row(Icons.home_outlined, 'Make One Launcher your home app', () {
              Navigator.pop(ctx);
              Apps.instance.openHomeSettings();
            }),
            if (hidden.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: DS.s8),
                child: CardDivider(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s24, DS.s4),
                child: Text('Hidden apps', style: DS.eyebrow.copyWith(color: DS.inkMuted)),
              ),
              for (final a in hidden)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: DS.s24),
                  leading: AppIcon(a, size: 36),
                  title: Text(a.label, style: DS.rowTitle),
                  trailing: TextButton(
                    onPressed: () => prefs.toggleHidden(a.package),
                    child: Text('Show', style: DS.rowTitle.copyWith(fontSize: 14)),
                  ),
                ),
            ],
            const SizedBox(height: DS.s12),
          ],
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
      contentPadding: const EdgeInsets.symmetric(horizontal: DS.s24),
      title: Text(label, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
      value: value,
      activeThumbColor: DS.card,
      activeTrackColor: DS.ink,
      inactiveThumbColor: DS.inkFaint,
      inactiveTrackColor: DS.cardMuted,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: DS.s24),
      leading: Icon(icon, color: DS.ink),
      title: Text(label, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}
