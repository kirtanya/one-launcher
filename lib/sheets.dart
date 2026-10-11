import 'package:flutter/material.dart';

import 'apps.dart';
import 'folders.dart';
import 'prefs.dart';
import 'ui/components.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
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
    header: SheetHeader(
      title: app.label,
      subtitle: '${app.work ? 'Work profile · ' : ''}In ${prefs.folderName(folder)}${app.paused ? ' · paused' : ''}',
      leading: AppIcon(app, size: 48),
    ),
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
      for (final f in [...folders, other]) SheetAction(f.icon, prefs.folderName(f), () => pick(f.id), trailing: check(manual != null && current == f.id)),
    ],
  );
}

/// The "•••" on an open folder.
Future<void> showCustomiseFolder(
  BuildContext context, {
  required Prefs prefs,
  required Folder folder,
  required List<AppEntry> allApps,
  List<String> visibleOrder = const [],
}) {
  final isMostUsed = folder.id == mostUsed.id;
  final i = visibleOrder.indexOf(folder.id);
  void then(VoidCallback f) {
    Navigator.pop(context);
    f();
  }

  /// Swap this folder with its neighbour and save the whole order.
  void move(int by) {
    final order = [...visibleOrder];
    final j = i + by;
    order[i] = order[j];
    order[j] = folder.id;
    prefs.setFolderOrder(order);
  }

  return showOneSheet(
    context,
    header: SheetHeader(
      title: 'Customise',
      subtitle: isMostUsed ? 'Pinned & most used' : prefs.folderName(folder),
      leading: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(color: DS.ink, shape: BoxShape.circle),
        child: Icon(folder.icon, color: DS.card),
      ),
    ),
    actions: [
      if (!isMostUsed) ...[
        SheetAction(Icons.edit_outlined, 'Rename', () => then(() => showRenameFolder(context, prefs: prefs, folder: folder))),
        SheetAction(Icons.checklist_rounded, 'Choose apps', () => then(() => showChooseApps(context, prefs: prefs, folder: folder, allApps: allApps))),
        SheetAction(Icons.arrow_upward_rounded, 'Move up', () => then(() => move(-1)), enabled: i > 0),
        SheetAction(Icons.arrow_downward_rounded, 'Move down', () => then(() => move(1)), enabled: i >= 0 && i < visibleOrder.length - 1),
        SheetAction(Icons.restart_alt_rounded, 'Reset folder', () => then(() => prefs.resetFolder(folder.id)), danger: true),
      ] else ...[
        if (prefs.favourites.isNotEmpty) SheetAction(Icons.push_pin_outlined, 'Unpin all', () => then(prefs.unpinAll)),
        SheetAction(Icons.history_rounded, 'Clear most-used history', () => then(prefs.clearLaunches), danger: true),
      ],
    ],
  );
}

/// Rename a folder. Empty name = back to the default.
Future<void> showRenameFolder(BuildContext context, {required Prefs prefs, required Folder folder}) {
  final text = TextEditingController(text: prefs.folderName(folder));
  void save(BuildContext ctx) {
    prefs.renameFolder(folder.id, text.text == folder.name ? null : text.text);
    Navigator.pop(ctx);
  }

  return showOneSheetWith(
    context,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, MediaQuery.viewInsetsOf(ctx).bottom + DS.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: 'Rename folder', subtitle: 'Leave empty to use “${folder.name}”'),
          const SizedBox(height: DS.s16),
          TextField(
            controller: text,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: DS.ink,
            style: DS.title.copyWith(fontSize: 22),
            onSubmitted: (_) => save(ctx),
            decoration: InputDecoration(
              filled: true,
              fillColor: DS.cardMuted,
              contentPadding: const EdgeInsets.symmetric(horizontal: DS.s20, vertical: DS.s16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(DS.rMedia), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: DS.s16),
          Pressable(
            scale: .97,
            child: SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: DS.ink, foregroundColor: DS.card, shape: const StadiumBorder()),
                onPressed: () => save(ctx),
                child: Text('Save', style: DS.rowTitle.copyWith(color: DS.card)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Tick the apps that belong in this folder. Changes apply straight away.
Future<void> showChooseApps(BuildContext context, {required Prefs prefs, required Folder folder, required List<AppEntry> allApps}) {
  final apps = [...allApps]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  void toggle(AppEntry a, bool inside) {
    if (!inside) {
      prefs.setFolder(a.package, folder.id);
      return;
    }
    // Taking it out: back to its automatic folder, or "Everything else" if that's this one.
    final auto = folderFor(a, const {});
    prefs.setFolder(a.package, auto.id == folder.id ? (folder.id == other.id ? null : other.id) : null);
  }

  return showOneSheetWith(
    context,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .75),
      child: ListenableBuilder(
        listenable: prefs,
        builder: (ctx, _) {
          final overrides = prefs.folderOverrides;
          final count = apps.where((a) => folderFor(a, overrides).id == folder.id).length;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
                child: SheetHeader(title: 'Choose apps', subtitle: '${prefs.folderName(folder)} · $count apps'),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: apps.length,
                  itemBuilder: (ctx, i) {
                    final a = apps[i];
                    final current = folderFor(a, overrides);
                    final inside = current.id == folder.id;
                    return InkWell(
                      onTap: () => toggle(a, inside),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: DS.s8),
                        child: Row(
                          children: [
                            AppIcon(a, size: 36),
                            const SizedBox(width: DS.s16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.label,
                                    style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(prefs.folderName(current), style: DS.rowSub.copyWith(fontSize: 13)),
                                ],
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: Motion.snapDuration,
                              switchInCurve: Motion.pop,
                              transitionBuilder: (child, an) => ScaleTransition(scale: an, child: child),
                              child: Icon(
                                inside ? Icons.check_circle_rounded : Icons.circle_outlined,
                                key: ValueKey(inside),
                                color: inside ? DS.ink : DS.inkFaint,
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
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
