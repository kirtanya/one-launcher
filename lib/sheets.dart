import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'folders.dart';
import 'prefs.dart';
import 'top/header_fonts.dart';
import 'ui/palette.dart';
import 'ui/theme.dart';
import 'top/top_widgets.dart';
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

  Widget check(bool on) => on ? Icon(Icons.check_rounded, color: DS.ink) : const SizedBox.shrink();

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
        decoration: BoxDecoration(color: DS.ink, shape: BoxShape.circle),
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
    scrollable: false, // scrolls its own list
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

/// Choose and order the pages of the swipeable top half.
Future<void> showCustomiseTop(BuildContext context, {required Prefs prefs}) {
  return showOneSheetWith(
    context,
    builder: (ctx) => ListenableBuilder(
      listenable: prefs,
      builder: (ctx, _) {
        final order = prefs.topOrder;
        final on = prefs.topEnabled;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
              child: SheetHeader(title: 'Top widgets', subtitle: 'Swipe the clock sideways · drag to reorder'),
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: order.length,
              onReorderItem: (from, to) {
                final list = [...order];
                list.insert(to, list.removeAt(from));
                prefs.setTopOrder(list);
              },
              proxyDecorator: (child, _, _) => Material(color: DS.card, elevation: 6, borderRadius: BorderRadius.circular(DS.rMedia), child: child),
              itemBuilder: (ctx, i) {
                final w = topWidgetFor(order[i], prefs.widgetLabels);
                final enabled = on.contains(w.id);
                final last = enabled && on.length == 1; // keep at least one page
                return Padding(
                  key: ValueKey(w.id),
                  padding: const EdgeInsets.fromLTRB(DS.s8, 0, DS.s16, 0),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: SizedBox.square(
                          dimension: DS.tap,
                          child: Icon(Icons.drag_indicator_rounded, color: DS.inkFaint),
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: enabled ? DS.ink : DS.cardMuted, shape: BoxShape.circle),
                        child: Icon(w.icon, size: 20, color: enabled ? DS.card : DS.inkMuted),
                      ),
                      const SizedBox(width: DS.s16),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: DS.s12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(w.name, style: DS.rowTitle),
                              Text(w.description, style: DS.rowSub.copyWith(fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                      Switch(
                        value: enabled,
                        activeThumbColor: DS.card,
                        activeTrackColor: DS.ink,
                        inactiveThumbColor: DS.inkFaint,
                        inactiveTrackColor: DS.cardMuted,
                        onChanged: last ? null : (v) => prefs.setTopEnabled(w.id, v),
                      ),
                      // App widgets can be removed altogether.
                      if (w.id.startsWith('widget:'))
                        IconButton(
                          tooltip: 'Remove ${w.name}',
                          icon: Icon(Icons.delete_outline_rounded, color: DS.inkMuted),
                          onPressed: () {
                            Apps.instance.removeWidget(int.parse(w.id.substring(7)));
                            prefs.removeWidgetPage(w.id);
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
            _Row(Icons.add_circle_outline_rounded, 'Add app widget', () => showWidgetPicker(context, prefs: prefs)),
            const Padding(padding: EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s24, DS.s4), child: CardDivider()),
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s24, DS.s12),
              child: Text('Font', style: DS.rowTitle),
            ),
            _FontPicker(prefs: prefs),
            const SizedBox(height: DS.s8),
          ],
        );
      },
    ),
  );
}

/// Every app widget on the phone, grouped by app. Tap one to add it as a top page.
Future<void> showWidgetPicker(BuildContext context, {required Prefs prefs}) {
  return showOneSheetWith(
    context,
    scrollable: false, // scrolls its own list
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .8),
      child: FutureBuilder<List<WidgetProvider>>(
        future: Apps.instance.widgetProviders(),
        builder: (ctx, snap) {
          final all = snap.data;
          // Group by app (work-profile apps separately).
          final groups = <String, List<WidgetProvider>>{};
          for (final p in all ?? const <WidgetProvider>[]) {
            groups.putIfAbsent(p.package, () => []).add(p);
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
                child: SheetHeader(title: 'Add app widget', subtitle: 'It becomes a page you swipe to at the top'),
              ),
              if (all == null)
                const Padding(
                  padding: EdgeInsets.all(DS.s32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(DS.s24),
                  child: Text('No app widgets found.', style: DS.rowSub),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: groups.length,
                    itemBuilder: (ctx, i) {
                      final list = groups.values.elementAt(i);
                      final first = list.first;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: DS.s16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s24, DS.s8),
                              child: Row(
                                children: [
                                  AppIcon(AppEntry(package: first.package, label: first.app, work: first.work), size: 28),
                                  const SizedBox(width: DS.s12),
                                  Expanded(child: Text(first.app, style: DS.rowTitle)),
                                  if (first.work) Text('Work', style: DS.rowSub),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 168,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                                itemCount: list.length,
                                separatorBuilder: (_, _) => const SizedBox(width: DS.s12),
                                itemBuilder: (ctx, j) => _WidgetTile(
                                  provider: list[j],
                                  onTap: () async {
                                    final p = list[j];
                                    final id = await Apps.instance.addWidget(p);
                                    if (id == null) return; // cancelled
                                    HapticFeedback.mediumImpact();
                                    await prefs.addWidgetPage(id, p.label == p.app ? p.label : '${p.app} · ${p.label}');
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                ),
                              ),
                            ),
                          ],
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

/// Preview + name + grid size of one widget.
class _WidgetTile extends StatelessWidget {
  const _WidgetTile({required this.provider, required this.onTap});
  final WidgetProvider provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: .95,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 112,
                decoration: BoxDecoration(color: DS.cardMuted, borderRadius: BorderRadius.circular(DS.rMedia)),
                padding: const EdgeInsets.all(DS.s8),
                alignment: Alignment.center,
                child: FutureBuilder<Uint8List?>(
                  future: Apps.instance.widgetPreview(provider),
                  builder: (ctx, snap) => snap.data == null
                      ? Icon(Icons.widgets_outlined, color: DS.inkFaint, size: 32)
                      : Image.memory(snap.data!, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
              const SizedBox(height: 6),
              Text(provider.label, style: DS.iconLabel.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${provider.cols} × ${provider.rows}', style: DS.rowSub.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// First launch of a new install. Either Android already restored the settings from the
/// phone's Google backup ([restoredByAndroid]), or we offer to bring back a backup file:
/// first looking in Downloads, then — if it isn't there — anywhere else.
Future<void> showWelcomeRestore(BuildContext context, {required Prefs prefs, required bool restoredByAndroid}) {
  var step = restoredByAndroid ? 'restored' : 'ask'; // ask → elsewhere → done
  String? message;
  return showOneSheetWith(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Future<void> pick({required bool inDownloads}) async {
          final text = await Apps.instance.openBackup(inDownloads: inDownloads);
          if (text == null) {
            // Nothing picked: maybe it lives somewhere else.
            set(() => step = 'elsewhere');
            return;
          }
          try {
            final n = await prefs.importBackup(text);
            HapticFeedback.mediumImpact();
            set(() {
              step = 'done';
              message = 'Restored $n settings. Welcome back!';
            });
          } on FormatException catch (e) {
            set(() {
              step = 'elsewhere';
              message = '${e.message}. Try another file.';
            });
          }
        }

        final (title, body) = switch (step) {
          'restored' => ('Welcome back', 'Your setup was restored automatically from your phone’s Google backup.'),
          'elsewhere' => (
            'Saved somewhere else?',
            message ?? 'Didn’t see it in Downloads? Your backup might be in another folder, like Documents, Google Drive or WhatsApp Documents.',
          ),
          'done' => ('All set', message ?? 'Restored.'),
          _ => ('Welcome to One Launcher', 'Have a backup from before? Backups are files named OneLauncher-backup-… .json, usually in Downloads.'),
        };
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
              child: SheetHeader(
                title: title,
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: DS.hero, shape: BoxShape.circle),
                  child: Icon(step == 'done' || step == 'restored' ? Icons.check_rounded : Icons.settings_backup_restore_rounded, color: DS.heroInk),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s16),
              child: AnimatedSwitcher(
                duration: Motion.snapDuration,
                child: Text(body, key: ValueKey(body), style: DS.rowSub),
              ),
            ),
            ...switch (step) {
              'restored' => [
                _Row(Icons.check_circle_outline_rounded, 'Looks good', () => Navigator.pop(ctx)),
                _Row(Icons.folder_open_rounded, 'Use a backup file instead', () => pick(inDownloads: true)),
              ],
              'elsewhere' => [
                _Row(Icons.folder_open_rounded, 'Look in another folder', () => pick(inDownloads: false)),
                _Row(Icons.arrow_forward_rounded, 'Start fresh', () => Navigator.pop(ctx)),
              ],
              'done' => [_Row(Icons.check_circle_outline_rounded, 'Done', () => Navigator.pop(ctx))],
              _ => [
                _Row(Icons.search_rounded, 'Find my backup', () => pick(inDownloads: true)),
                _Row(Icons.arrow_forward_rounded, 'Start fresh', () => Navigator.pop(ctx)),
              ],
            },
          ],
        );
      },
    ),
  );
}

/// Save all settings to a file, or bring them back from one.
Future<void> showBackupSheet(BuildContext context, {required Prefs prefs}) {
  String? message;
  var busy = false;
  return showOneSheetWith(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Future<void> save() async {
          set(() => busy = true);
          final d = DateTime.now();
          final name = 'OneLauncher-backup-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.json';
          final ok = await Apps.instance.saveBackup(name, prefs.exportBackup());
          set(() {
            busy = false;
            message = ok ? 'Saved $name' : 'Not saved';
          });
        }

        Future<void> restore() async {
          final text = await Apps.instance.openBackup();
          if (text == null || !ctx.mounted) return;
          // What's in the file, before replacing anything.
          String when = '';
          try {
            final created = DateTime.tryParse((jsonDecode(text) as Map)['created'] as String? ?? '');
            if (created != null) when = ' from ${created.day}/${created.month}/${created.year}';
          } catch (_) {}
          final confirmed = await showDialog<bool>(
            context: ctx,
            builder: (d) => AlertDialog(
              backgroundColor: DS.card,
              title: Text('Restore backup$when?', style: DS.title.copyWith(fontSize: 20)),
              content: Text('Your current pins, folders, pages, layout and colours will be replaced. App widgets on this phone stay.', style: DS.rowSub),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: Text('Cancel', style: DS.rowTitle.copyWith(color: DS.inkMuted)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: Text('Restore', style: DS.rowTitle),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          try {
            final n = await prefs.importBackup(text);
            HapticFeedback.mediumImpact();
            set(() => message = 'Restored $n settings');
          } on FormatException catch (e) {
            set(() => message = e.message);
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
              child: SheetHeader(title: 'Backup & restore', subtitle: 'Pins, folders, pages, layout, fonts and colours'),
            ),
            _Row(Icons.save_alt_rounded, 'Save backup to a file', busy ? () {} : save),
            _Row(Icons.restore_rounded, 'Restore from a backup', restore),
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s24, DS.s16),
              child: AnimatedSwitcher(
                duration: Motion.snapDuration,
                child: Text(
                  message ?? 'You choose where the file goes, like Downloads or Google Drive. App widgets aren’t included; add them again after restoring.',
                  key: ValueKey(message),
                  style: message == null ? DS.rowSub.copyWith(fontSize: 13) : DS.rowTitle.copyWith(fontSize: 14),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Colours & style — modelled on Pixel's "Wallpaper & style".
Future<void> showColoursSheet(BuildContext context, {required Prefs prefs, required OneTheme theme}) {
  var tab = prefs.themeSource;
  return showOneSheetWith(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setTab) => ListenableBuilder(
        listenable: Listenable.merge([prefs, theme]),
        builder: (ctx, _) {
          final source = prefs.themeSource;
          final style = prefs.themeStyle;
          Widget tabChip(String id, String label) => _Chip(label: label, selected: tab == id, onTap: () => setTab(() => tab = id));
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s16),
                child: SheetHeader(title: 'Colours & style', subtitle: 'Follows your phone, or pick your own'),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                child: Row(
                  children: [
                    tabChip('system', 'Wallpaper colours'),
                    const SizedBox(width: DS.s8),
                    tabChip('basic', 'Basic colours'),
                    const SizedBox(width: DS.s8),
                    tabChip('original', 'One original'),
                  ],
                ),
              ),
              const SizedBox(height: DS.s20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                child: switch (tab) {
                  'system' when !theme.hasSystem => Text('Wallpaper colours need Android 12 or newer.', style: DS.rowSub),
                  // Your phone's colours in each style — Pixel's wallpaper colour options.
                  'system' => Wrap(
                    spacing: DS.s16,
                    runSpacing: DS.s16,
                    children: [
                      for (final e in OneTheme.styles.entries)
                        _Swatch(
                          scheme: theme.schemeFor('system', style: e.key),
                          label: e.value.$1,
                          selected: source == 'system' && style == e.key,
                          onTap: () => prefs.setTheme(source: 'system', style: e.key),
                        ),
                    ],
                  ),
                  'basic' => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: DS.s16,
                        runSpacing: DS.s16,
                        children: [
                          for (final c in OneTheme.basicSeeds)
                            _Swatch(
                              scheme: theme.schemeFor('basic', seed: c.toARGB32(), style: style),
                              selected: source == 'basic' && prefs.themeSeed == c.toARGB32(),
                              onTap: () => prefs.setTheme(source: 'basic', seed: c.toARGB32()),
                            ),
                        ],
                      ),
                      const SizedBox(height: DS.s20),
                      Text('Style', style: DS.rowTitle),
                      const SizedBox(height: DS.s8),
                      Wrap(
                        spacing: DS.s8,
                        runSpacing: DS.s8,
                        children: [
                          for (final e in OneTheme.styles.entries)
                            _Chip(
                              label: e.value.$1,
                              selected: style == e.key,
                              onTap: () => prefs.setTheme(source: 'basic', style: e.key),
                            ),
                        ],
                      ),
                    ],
                  ),
                  _ => Row(
                    children: [
                      _Swatch(
                        original: true,
                        label: 'One',
                        selected: source == 'original',
                        onTap: () => prefs.setTheme(source: 'original'),
                      ),
                      const SizedBox(width: DS.s16),
                      Expanded(child: Text('The original green and black look.', style: DS.rowSub)),
                    ],
                  ),
                },
              ),
              // Cards: light / dark / follow the phone's dark theme.
              const Padding(padding: EdgeInsets.fromLTRB(DS.s24, DS.s24, DS.s24, DS.s16), child: CardDivider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cards', style: DS.rowTitle),
                    const SizedBox(height: DS.s8),
                    Wrap(
                      spacing: DS.s8,
                      runSpacing: DS.s8,
                      children: [
                        for (final (id, label) in [('light', 'Light'), ('dark', 'Dark'), ('auto', 'Auto')])
                          _Chip(label: label, selected: prefs.cardStyle == id, onTap: () => prefs.setCardStyle(id)),
                      ],
                    ),
                    const SizedBox(height: DS.s8),
                    Text('Auto follows your phone’s dark theme.', style: DS.rowSub.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: DS.s24),
            ],
          );
        },
      ),
    ),
  );
}

/// Pill choice chip in the One style (ink when selected).
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: .94,
      child: Material(
        color: selected ? DS.ink : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? DS.ink : DS.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: 10),
              child: Text(
                label,
                style: DS.rowTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: selected ? DS.card : DS.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pixel-style colour swatch: top half primary, bottom halves secondary / tertiary.
class _Swatch extends StatelessWidget {
  const _Swatch({this.scheme, this.original = false, this.label, required this.selected, required this.onTap});
  final ColorScheme? scheme;
  final bool original;
  final String? label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = OnePalette.original;
    final (a, b, c) = original || scheme == null ? (o.hero, o.card, o.canvas) : (scheme!.primary, scheme!.secondaryContainer, scheme!.tertiaryContainer);
    return Pressable(
      scale: .9,
      child: GestureDetector(
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: selected,
          label: label ?? 'Colour',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Motion.snapDuration,
                curve: Motion.settle,
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? DS.ink : Colors.transparent, width: 2.5),
                ),
                child: Stack(
                  children: [
                    CustomPaint(size: const Size.square(48), painter: _SwatchPainter(a, b, c)),
                    if (selected)
                      Center(
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(color: DS.card, shape: BoxShape.circle),
                          child: Icon(Icons.check_rounded, size: 16, color: DS.ink),
                        ),
                      ),
                  ],
                ),
              ),
              if (label != null) ...[const SizedBox(height: 4), Text(label!, style: DS.iconLabel)],
            ],
          ),
        ),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.top, this.left, this.right);
  final Color top, left, right;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawArc(r, 3.14159, 3.14159, true, Paint()..color = top); // top half
    canvas.drawArc(r, 1.5708, 1.5708, true, Paint()..color = left); // bottom-left quarter
    canvas.drawArc(r, 0, 1.5708, true, Paint()..color = right); // bottom-right quarter
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.top != top || old.left != left || old.right != right;
}

/// Long-press empty space on the home screen, or the settings button in the app view.
Future<void> showSettingsSheet(BuildContext context, {required Prefs prefs, required List<AppEntry> apps, required OneTheme theme}) {
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
              child: SheetHeader(title: 'One Launcher', subtitle: 'Settings for your launcher'),
            ),
            _Toggle('Open app when search finds only one', prefs.autoOpenSingleMatch, prefs.setAutoOpenSingleMatch),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: DS.s8),
              child: CardDivider(),
            ),
            _SplitSlider(prefs: prefs),
            _PaddingSlider(prefs: prefs),
            _Row(Icons.settings_backup_restore_rounded, 'Backup & restore', () {
              Navigator.pop(ctx);
              showBackupSheet(context, prefs: prefs);
            }),
            _Row(Icons.palette_outlined, 'Colours & style', () {
              Navigator.pop(ctx);
              showColoursSheet(context, prefs: prefs, theme: theme);
            }),
            _Row(Icons.view_carousel_outlined, 'Top widgets', () {
              Navigator.pop(ctx);
              showCustomiseTop(context, prefs: prefs);
            }),
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

/// Settings → Layout: how much of the screen the top widgets take. Updates live behind the sheet.
class _SplitSlider extends StatelessWidget {
  const _SplitSlider({required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    final v = prefs.topShare;
    final pct = (v * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Top widgets size', style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
              ),
              Text('$pct% · apps ${100 - pct}%', style: DS.rowSub),
            ],
          ),
          Row(
            children: [
              Icon(Icons.crop_portrait_rounded, size: 18, color: DS.inkMuted),
              Expanded(
                child: Slider(
                  value: v,
                  min: Prefs.topShareMin,
                  max: Prefs.topShareMax,
                  divisions: 6, // 20, 25, 30 … 50 %
                  label: '$pct%',
                  activeColor: DS.ink,
                  inactiveColor: DS.cardMuted,
                  thumbColor: DS.ink,
                  onChanged: (x) {
                    if ((x - v).abs() > .001) HapticFeedback.selectionClick();
                    prefs.setTopShare(x);
                  },
                ),
              ),
              Icon(Icons.splitscreen_rounded, size: 18, color: DS.inkMuted),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live previews of each big-figure font; tap to choose.
class _FontPicker extends StatelessWidget {
  const _FontPicker({required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final sample = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DS.s24),
        itemCount: headerFonts.length,
        separatorBuilder: (_, _) => const SizedBox(width: DS.s12),
        itemBuilder: (context, i) {
          final f = headerFonts[i];
          final selected = prefs.headerFont == f.id;
          return Pressable(
            scale: .94,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                prefs.setHeaderFont(f.id);
              },
              child: Semantics(
                selected: selected,
                button: true,
                label: '${f.name} font',
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: Motion.snapDuration,
                      curve: Motion.settle,
                      width: 96,
                      height: 72,
                      padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: DS.s4),
                      decoration: BoxDecoration(
                        color: DS.canvas,
                        borderRadius: BorderRadius.circular(DS.rMedia),
                        border: Border.all(color: selected ? DS.hero : DS.canvas, width: 3),
                      ),
                      child: FittedBox(
                        child: Text(
                          sample,
                          style: f.style.copyWith(shadows: const [], color: DS.onWallpaper),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(f.name, style: DS.iconLabel.copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Settings → Layout: breathing room around the top widgets. Updates live.
class _PaddingSlider extends StatelessWidget {
  const _PaddingSlider({required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    final v = prefs.topPadding;
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Top widgets padding', style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
              ),
              Text(v == 0 ? 'None' : '${v.round()} pt', style: DS.rowSub),
            ],
          ),
          Row(
            children: [
              Icon(Icons.fullscreen_rounded, size: 18, color: DS.inkMuted),
              Expanded(
                child: Slider(
                  value: v,
                  max: Prefs.topPaddingMax,
                  divisions: 5, // 0, 8, 16 … 40
                  label: '${v.round()} pt',
                  activeColor: DS.ink,
                  inactiveColor: DS.cardMuted,
                  thumbColor: DS.ink,
                  onChanged: (x) {
                    if ((x - v).abs() > .5) HapticFeedback.selectionClick();
                    prefs.setTopPadding(x);
                  },
                ),
              ),
              Icon(Icons.fullscreen_exit_rounded, size: 18, color: DS.inkMuted),
            ],
          ),
        ],
      ),
    );
  }
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
