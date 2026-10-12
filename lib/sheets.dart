import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'folders.dart';
import 'quick_chips.dart';
import 'prefs.dart';
import 'photo_wallpaper.dart';
import 'quick_actions.dart';
import 'tv_remote.dart';
import 'remote_sheet.dart';
import 'top/header_fonts.dart';
import 'ui/palette.dart';
import 'ui/theme.dart';
import 'top/top_widgets.dart';
import 'ui/components.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'ui/perf.dart';
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
/// Long-press the top of home (or Settings → Top widgets): everything about the top area in
/// one place — its pages and app widgets, clock style, size & spacing, wallpaper and the quick
/// chips. Short enough that the top stays in view and every change shows live above it.
Future<Object?> showCustomiseTop(BuildContext context, {required Prefs prefs, bool back = false}) async {
  final r = await showOneSheetWith(
    context,
    back: back,
    height: drawerHeight(context, prefs),
    builder: (ctx) => ListenableBuilder(
      listenable: prefs,
      builder: (ctx, _) {
        final order = prefs.topOrder;
        final on = prefs.topEnabled;
        final w0 = prefs.clockWeight, wd0 = prefs.clockWidth;
        final preset = clockPresets.where((p) => isClockPreset(p, prefs)).firstOrNull;
        Widget label(String text, [String? hint]) => Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s8),
          child: Row(
            children: [
              Expanded(
                child: Text(text, style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 13)),
              ),
              if (hint != null) Text(hint, style: DS.rowSub.copyWith(fontSize: 12)),
            ],
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, 0),
              child: SheetHeader(title: 'Top of home', subtitle: 'Changes show live above'),
            ),
            label('Pages', 'Drag to reorder'),
            // Pages: one rounded group, like Settings.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DS.s16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DS.rMedia),
                child: Material(
                  color: DS.cardMuted,
                  child: Column(
                    children: [
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
                      Divider(height: 1, thickness: 1, color: DS.hairline),
                      _NavRow(Icons.add_rounded, 'Add app widget', 'Any app’s widget becomes a page', () => showWidgetPicker(ctx, prefs: prefs)),
                    ],
                  ),
                ),
              ),
            ),
            _Group('Clock', [
              _NavRow(
                Icons.text_fields_rounded,
                'Clock style',
                preset?.$1 ?? 'Custom · weight ${w0.round()}, width ${wd0.round()}',
                () => _showClockStyle(ctx, prefs: prefs),
              ),
            ]),
            label('Size & spacing'),
            _SplitSlider(prefs: prefs),
            _PaddingSlider(prefs: prefs),
            _Group('Around it', [
              _NavRow(
                Icons.wallpaper_rounded,
                'Wallpaper',
                '${prefs.wallpaperPhoto != null ? 'Your photo' : 'Phone wallpaper'} · dim ${(prefs.wallpaperDim * 100).round()}%',
                () => _showWallpaperSheet(ctx, prefs: prefs),
              ),
              _NavRow(Icons.bolt_rounded, 'Quick actions', '${prefs.quickChips.length} chips above the apps', () => showCustomiseChips(ctx, prefs: prefs)),
            ]),
            const SizedBox(height: DS.s8),
          ],
        );
      },
    ),
  );
  return r;
}

/// Top of home → Clock style (2nd level): presets + weight / width / slant, live on the clock.
Future<Object?> _showClockStyle(BuildContext context, {required Prefs prefs}) => showOneSheetWith(
  context,
  back: true,
  height: drawerHeight(context, prefs),
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s16),
          child: SheetHeader(title: 'Clock style', subtitle: 'One font you shape yourself'),
        ),
        _ClockStyleEditor(prefs: prefs),
        const SizedBox(height: DS.s12),
      ],
    ),
  ),
);

/// Choose, order and remove the quick-action chips. Built-in actions and apps' own shortcuts.

Future<Object?> showCustomiseChips(BuildContext context, {required Prefs prefs, bool back = false}) async {
  final shortcuts = Apps.instance.shortcuts(); // load once while the sheet is open
  var query = '';
  final r = await showOneSheetWith(
    context,
    back: back,
    keyboard: true,
    height: drawerHeight(context, prefs), // chips (above the drawer) stay in view
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setQuery) => ListenableBuilder(
        listenable: prefs,
        builder: (ctx, _) {
          // While searching, only the actions you can add show (matching the search).
          final searching = query.trim().isNotEmpty;
          final chips = prefs.quickChips;
          final labels = prefs.quickLabels;
          String nameOf(String id) => builtInActions[id]?.$1 ?? labels[id]?.split('|').first ?? id;
          Widget iconOf(String id, {double size = 22}) =>
              builtInActions.containsKey(id) ? Icon(builtInActions[id]!.$2, color: DS.ink, size: size) : ShortcutIcon(id: id, size: size);
          Widget section(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s8),
            child: Text(text, style: DS.rowTitle),
          );
          Widget addRow(String id, String label, {String? subtitle, String? app}) {
            final added = chips.contains(id);
            return InkWell(
              onTap: added ? () => prefs.removeQuickChip(id) : () => prefs.addQuickChip(id, label: id.startsWith('s:') ? label : null, app: app),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: DS.s8),
                child: Row(
                  children: [
                    iconOf(id),
                    const SizedBox(width: DS.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null) Text(subtitle, style: DS.rowSub.copyWith(fontSize: 13)),
                        ],
                      ),
                    ),
                    Icon(added ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: added ? DS.ink : DS.inkFaint),
                  ],
                ),
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
                child: SheetHeader(title: 'Quick actions', subtitle: 'Chips above your apps · drag to reorder'),
              ),
              SheetSearchField(hint: 'Search actions & app shortcuts', onChanged: (q) => setQuery(() => query = q)),
              if (!searching) ...[
                _Group(null, [_NavRow(Icons.style_outlined, 'Chip look', ChipLook.of(prefs).summary, () => _showChipLook(ctx, prefs: prefs))]),
                const SizedBox(height: DS.s8),
                // Current chips.
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: chips.length,
                  onReorderItem: (from, to) {
                    final list = [...chips];
                    list.insert(to, list.removeAt(from));
                    prefs.setQuickChips(list);
                  },
                  proxyDecorator: (child, _, _) => Material(color: DS.card, elevation: 6, borderRadius: BorderRadius.circular(DS.rMedia), child: child),
                  itemBuilder: (ctx, i) => Padding(
                    key: ValueKey(chips[i]),
                    padding: const EdgeInsets.fromLTRB(DS.s8, 0, DS.s8, 0),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: SizedBox.square(
                            dimension: DS.tap,
                            child: Icon(Icons.drag_indicator_rounded, color: DS.inkFaint),
                          ),
                        ),
                        iconOf(chips[i]),
                        const SizedBox(width: DS.s16),
                        Expanded(
                          child: Text(
                            nameOf(chips[i]),
                            style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove ${nameOf(chips[i])}',
                          icon: Icon(Icons.remove_circle_outline_rounded, color: DS.inkMuted),
                          onPressed: () => prefs.removeQuickChip(chips[i]),
                        ),
                      ],
                    ),
                  ),
                ),
                if (chips.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                    child: Text('No quick actions yet. Add some below.', style: DS.rowSub),
                  ),
                const Padding(padding: EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, 0), child: CardDivider()),
              ],
              if (!searching || builtInActions.entries.any((e) => !chips.contains(e.key) && matchesQuery(query, [e.value.$1]))) section('Built-in'),
              for (final e in builtInActions.entries)
                if (!chips.contains(e.key) && matchesQuery(query, [e.value.$1])) addRow(e.key, e.value.$1),
              section('From your apps'),
              FutureBuilder<List<AppShortcut>?>(
                future: shortcuts,
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(DS.s24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final all = snap.data;
                  if (all == null) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s16),
                      child: Text(
                        'Android only shares app shortcuts (like Paytm → Scan QR) with your home app. Set One Launcher as your home app to add them.',
                        style: DS.rowSub,
                      ),
                    );
                  }
                  if (all.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(DS.s24),
                      child: Text('No app shortcuts found.', style: DS.rowSub),
                    );
                  }
                  final found = [
                    for (final sc in all)
                      if (matchesQuery(query, [sc.label, sc.app])) sc,
                  ];
                  if (found.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s16),
                      child: Text('No app shortcuts match “${query.trim()}”.', style: DS.rowSub),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final sc in found) addRow(sc.id, sc.label, subtitle: sc.work ? '${sc.app} · Work' : sc.app, app: sc.app)],
                  );
                },
              ),
              const SizedBox(height: DS.s8),
            ],
          );
        },
      ),
    ),
  );
  return r;
}

/// Quick actions → Chip look: colour, opacity, shape, size, what to show, outline. Short and
/// lightly shaded so the chips above it — on the home screen — show every change live.
Future<Object?> _showChipLook(BuildContext context, {required Prefs prefs}) => showOneSheetWith(
  context,
  back: true,
  height: drawerHeight(context, prefs),
  barrier: const Color(0x14000000),
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) {
      final look = ChipLook.of(prefs);
      // Each change starts from the saved look (not this build's copy), so quick taps add up.
      void set(ChipLook Function(ChipLook) change) => prefs.setChipLook(change(ChipLook.of(prefs)).toJson());
      Widget label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s8),
        child: Text(text, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
      );
      Widget choices(Map<String, String> options, String current, void Function(String) pick) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: DS.s24),
        child: Wrap(
          spacing: DS.s8,
          runSpacing: DS.s8,
          children: [
            for (final MapEntry(:key, :value) in options.entries)
              _Chip(
                label: value,
                selected: key == current,
                onTap: () {
                  HapticFeedback.selectionClick();
                  pick(key);
                },
              ),
          ],
        ),
      );
      final pct = (look.opacity * 100).round();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, 0),
            child: SheetHeader(title: 'Chip look', subtitle: 'Changes show on the chips above'),
          ),
          label('Colour'),
          choices(ChipLook.tones, look.tone, (t) => set((l) => l.copyWith(tone: t, opacity: ChipLook.defaultOpacity(t)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Opacity', style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
                ),
                Text(pct >= 100 ? 'Solid' : '$pct%', style: DS.rowSub),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s16, 0),
            child: Row(
              children: [
                Icon(Icons.blur_on_rounded, size: 18, color: DS.inkMuted),
                Expanded(
                  child: Slider(
                    value: look.opacity,
                    min: .1,
                    max: 1,
                    divisions: 18, // 5% steps
                    label: '$pct%',
                    activeColor: DS.ink,
                    inactiveColor: DS.cardMuted,
                    thumbColor: DS.ink,
                    onChanged: (x) {
                      if ((x - look.opacity).abs() > .01) HapticFeedback.selectionClick();
                      set((l) => l.copyWith(opacity: x));
                    },
                  ),
                ),
                Icon(Icons.circle, size: 18, color: DS.inkMuted),
              ],
            ),
          ),
          label('Shape'),
          choices(ChipLook.shapes, look.shape, (v) => set((l) => l.copyWith(shape: v))),
          label('Size'),
          choices(ChipLook.sizes, look.size, (v) => set((l) => l.copyWith(size: v))),
          label('Show'),
          choices(ChipLook.contents, look.content, (v) => set((l) => l.copyWith(content: v))),
          _Group(null, [
            _SwitchRow(Icons.crop_square_rounded, 'Outline', 'Thin edge around each chip', look.outline, (v) => set((l) => l.copyWith(outline: v))),
            _NavRow(Icons.restart_alt_rounded, 'Reset look', 'Dark see-through pills', () {
              HapticFeedback.lightImpact();
              set((_) => const ChipLook());
            }),
          ]),
          const SizedBox(height: DS.s8),
        ],
      );
    },
  ),
);

/// Every app widget on the phone, grouped by app. Tap one to add it as a top page.
Future<void> showWidgetPicker(BuildContext context, {required Prefs prefs}) async {
  final providers = Apps.instance.widgetProviders(); // load once, not on every keystroke
  var query = '';
  await showOneSheetWith(
    context,
    scrollable: false, // scrolls its own list
    keyboard: true,
    height: MediaQuery.sizeOf(context).height * .85, // full screen while searching
    builder: (ctx) => ConstrainedBox(
      constraints: const BoxConstraints(), // the sheet sets the height
      child: StatefulBuilder(
        builder: (ctx, setQuery) => FutureBuilder<List<WidgetProvider>>(
          future: providers,
          builder: (ctx, snap) {
            final all = snap.data;
            // Group by app (work-profile apps separately); search matches the app or the widget.
            final groups = <String, List<WidgetProvider>>{};
            for (final p in all ?? const <WidgetProvider>[]) {
              if (!matchesQuery(query, [p.app, p.label])) continue;
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
                if (all != null && all.isNotEmpty) SheetSearchField(hint: 'Search widgets or apps', onChanged: (q) => setQuery(() => query = q)),
                if (all == null)
                  const Padding(
                    padding: EdgeInsets.all(DS.s32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(DS.s24),
                    child: Text(query.trim().isEmpty ? 'No app widgets found.' : 'No widgets match “${query.trim()}”.', style: DS.rowSub),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: groups.length,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
Future<Object?> showBackupSheet(BuildContext context, {required Prefs prefs, bool back = false}) {
  String? message;
  var busy = false;
  return showOneSheetWith(
    context,
    back: back,
    height: back ? drawerHeight(context, prefs) : null,
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
Future<Object?> showColoursSheet(BuildContext context, {required Prefs prefs, required OneTheme theme, bool back = false}) {
  var tab = prefs.themeSource;
  return showOneSheetWith(
    context,
    back: back,
    height: back ? drawerHeight(context, prefs) : null,
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
/// Height of the app drawer at rest: Settings sheets match it, so the top widgets stay in view.
double drawerHeight(BuildContext context, Prefs prefs) => MediaQuery.sizeOf(context).height * (1 - prefs.topShare);

/// One row of Settings: shown in its section, and found by the settings search.
class _Setting {
  const _Setting(this.section, this.icon, this.title, this.subtitle, {this.keywords = '', this.open, this.value, this.onChanged, this.external = false});
  final String section, title, subtitle, keywords;
  final IconData icon;
  final void Function(BuildContext ctx)? open; // opens its page (or a system screen)
  final bool? value; // a switch row
  final ValueChanged<bool>? onChanged;
  final bool external;

  bool matches(String q) => matchesQuery(q, [title, subtitle, keywords, section]);

  Widget row(BuildContext ctx) =>
      value != null ? _SwitchRow(icon, title, subtitle, value!, onChanged!) : _NavRow(icon, title, subtitle, () => open!(ctx), external: external);
}

/// Settings: one sheet (as tall as the app drawer, so the home stays in view above) whose
/// pages slide in and out — tap a row for its page, back to return. A search box finds any
/// setting. Rows say what's set right now.
Future<void> showSettingsSheet(BuildContext context, {required Prefs prefs, required List<AppEntry> apps, required OneTheme theme}) {
  var query = '';
  return showOneSheetWith(
    context,
    height: drawerHeight(context, prefs),
    fill: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setQuery) => ListenableBuilder(
        listenable: prefs,
        builder: (ctx, _) {
          final hidden = apps.where((a) => prefs.hidden.contains(a.package)).length;
          final source = const {'system': 'Wallpaper colours', 'basic': 'Basic colours', 'original': 'One original'}[prefs.themeSource] ?? 'Wallpaper colours';
          final style = OneTheme.styles[prefs.themeStyle]?.$1 ?? 'Tonal';
          final cards = const {'light': 'light cards', 'dark': 'dark cards', 'auto': 'auto cards'}[prefs.cardStyle] ?? 'light cards';
          final top = prefs.topPages.map((id) => topWidgetFor(id, prefs.widgetLabels).name).join(', ');
          final dim = (prefs.wallpaperDim * 100).round();
          final chips = prefs.quickChips.length;
          final preset = clockPresets.where((p) => isClockPreset(p, prefs)).firstOrNull?.$1 ?? 'Custom';
          final all = <_Setting>[
            // Look
            _Setting(
              'Look',
              Icons.palette_outlined,
              'Colours & style',
              '$source · $style · $cards',
              keywords: 'theme material you dark light cards accent',
              open: (c) => showColoursSheet(c, prefs: prefs, theme: theme),
            ),
            _Setting(
              'Look',
              Icons.wallpaper_rounded,
              'Wallpaper',
              '${prefs.wallpaperPhoto != null ? 'Your photo' : 'Phone wallpaper'} · ${dim == 0 ? 'dim off' : 'dim $dim%'}',
              keywords: 'background photo dim blur zoom',
              open: (c) => _showWallpaperSheet(c, prefs: prefs),
            ),
            _Setting(
              'Look',
              Icons.text_fields_rounded,
              'Clock style',
              preset,
              keywords: 'font weight width slant roundness rounded',
              open: (c) => _showClockStyle(c, prefs: prefs),
            ),
            // Home screen
            _Setting(
              'Home screen',
              Icons.view_carousel_outlined,
              'Top widgets',
              top.isEmpty ? 'None' : top,
              keywords: 'pages widgets clock screen time battery calendar now playing',
              open: (c) => showCustomiseTop(c, prefs: prefs),
            ),
            _Setting(
              'Home screen',
              Icons.dashboard_outlined,
              'Layout',
              'Top ${(prefs.topShare * 100).round()}% · padding ${prefs.topPadding == 0 ? 'none' : '${prefs.topPadding.round()} pt'}',
              keywords: 'size split padding spacing',
              open: (c) => _showLayoutSheet(c, prefs: prefs),
            ),
            _Setting(
              'Home screen',
              Icons.bolt_rounded,
              'Quick chips',
              chips == 0 ? 'None' : '$chips ${chips == 1 ? 'chip' : 'chips'} above the apps',
              keywords: 'actions shortcuts pills look',
              open: (c) => showCustomiseChips(c, prefs: prefs),
            ),
            // Apps & search
            _Setting(
              'Apps & search',
              Icons.search_rounded,
              'Search',
              '${prefs.searchPosition == 'top' ? 'Bar at the top' : 'Bar at the bottom'} · pull down ${prefs.pullToSearch ? 'on' : 'off'}',
              keywords: 'google play store settings shortcuts pull',
              open: (c) => _showSearchSettings(c, prefs: prefs),
            ),
            _Setting(
              'Apps & search',
              Icons.unfold_more_rounded,
              'Open folders as you scroll',
              'The folder that stops in the middle opens',
              keywords: 'folders auto',
              value: prefs.autoOpenFolders,
              onChanged: prefs.setAutoOpenFolders,
            ),
            _Setting(
              'Apps & search',
              Icons.visibility_off_outlined,
              'Hidden apps',
              hidden == 0 ? 'None' : '$hidden hidden',
              keywords: 'hide',
              open: (c) => _showHiddenApps(c, prefs: prefs, apps: apps),
            ),
            // TV
            _Setting(
              'TV remote',
              Icons.settings_remote_rounded,
              'Remote button',
              prefs.remoteButton ? 'Next to search' : 'Hidden',
              keywords: 'tv television google tv control',
              value: prefs.remoteButton,
              onChanged: prefs.setRemoteButton,
            ),
            _Setting(
              'TV remote',
              Icons.tv_rounded,
              'Your TV',
              prefs.tvHost == null ? 'Not set up yet' : '${prefs.tvName} · ${prefs.tvHost}',
              keywords: 'pair forget television',
              open: (c) => _showTvSettings(c, prefs: prefs, home: context),
            ),
            // Launcher
            _Setting(
              'Launcher',
              Icons.speed_rounded,
              'Lighter effects',
              switch (prefs.effects) {
                'lite' => 'On · smoothest on any phone',
                'full' => 'Off · all animations',
                _ => Perf.autoSlow ? 'On for this phone (automatic)' : 'Automatic · on if this phone is slow',
              },
              keywords: 'performance smooth animations battery',
              value: Perf.lite.value,
              onChanged: (v) => prefs.setEffects(v ? 'lite' : 'full'),
            ),
            _Setting(
              'Launcher',
              Icons.settings_backup_restore_rounded,
              'Backup & restore',
              'Save all settings to a file',
              keywords: 'export import save',
              open: (c) => showBackupSheet(c, prefs: prefs),
            ),
            _Setting(
              'Launcher',
              Icons.home_outlined,
              'Default home app',
              'Opens your phone’s settings',
              keywords: 'launcher default',
              external: true,
              open: (c) {
                SheetHost.close(c);
                Apps.instance.openHomeSettings();
              },
            ),
          ];
          final q = query.trim();
          final found = q.isEmpty ? const <_Setting>[] : all.where((x) => x.matches(q)).toList();
          final sections = <String>[];
          for (final x in all) {
            if (!sections.contains(x.section)) sections.add(x.section);
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s12),
                child: Text('Settings', style: DS.title.copyWith(fontSize: 28)),
              ),
              SheetSearchField(hint: 'Search settings', onChanged: (v) => setQuery(() => query = v)),
              if (q.isNotEmpty) ...[
                if (found.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(DS.s24),
                    child: Text('No setting matches “$q”', style: DS.rowSub),
                  )
                else
                  _Group(null, [for (final x in found) x.row(ctx)]),
              ] else
                for (final sec in sections) _Group(sec, [for (final x in all.where((x) => x.section == sec)) x.row(ctx)]),
              const SizedBox(height: DS.s16),
            ],
          );
        },
      ),
    ),
  );
}

/// Settings → Your TV (page): remote button on/off, the paired TV, forget it, open the remote.
Future<Object?> _showTvSettings(BuildContext context, {required Prefs prefs, required BuildContext home}) => showOneSheetWith(
  context,
  height: drawerHeight(context, prefs),
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, 0),
          child: SheetHeader(title: 'TV remote', subtitle: 'Control your Google TV from the dock'),
        ),
        _Group(null, [_SwitchRow(Icons.settings_remote_rounded, 'Remote button', 'Between search and settings', prefs.remoteButton, prefs.setRemoteButton)]),
        _Group('Your TV', [
          if (prefs.tvHost == null)
            _NavRow(Icons.add_link_rounded, 'Set up a TV', 'Pair once with the code on your TV', () {
              SheetHost.close(ctx);
              showTvRemote(home, prefs: prefs);
            })
          else ...[
            _NavRow(Icons.tv_rounded, prefs.tvName, prefs.tvHost!, () {
              SheetHost.close(ctx);
              showTvRemote(home, prefs: prefs);
            }),
            _NavRow(Icons.link_off_rounded, 'Forget this TV', 'You’ll pair again next time', () async {
              HapticFeedback.mediumImpact();
              await TvRemote.instance.forget(prefs.tvHost!);
              await prefs.setTv(null);
            }),
          ],
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s16),
          child: Text(
            'Works with Google TV and Android TV on the same Wi-Fi. Only your phone and TV talk to each other.',
            style: DS.rowSub.copyWith(fontSize: 13),
          ),
        ),
      ],
    ),
  ),
);

/// Settings → Layout (2nd level): split + padding. Short sheet, so the home updates in view.
Future<Object?> _showLayoutSheet(BuildContext context, {required Prefs prefs}) => showOneSheetWith(
  context,
  back: true,
  height: drawerHeight(context, prefs),
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
          child: SheetHeader(title: 'Layout', subtitle: 'How the screen is shared'),
        ),
        _SplitSlider(prefs: prefs),
        _PaddingSlider(prefs: prefs),
        const SizedBox(height: DS.s8),
      ],
    ),
  ),
);

/// Settings → Wallpaper (2nd level): phone wallpaper or your own photo; for a photo, frame
/// it (up/down, left/right, zoom, blur). Dim for both. Changes show live behind the sheet.
Future<Object?> _showWallpaperSheet(BuildContext context, {required Prefs prefs}) => showOneSheetWith(
  context,
  back: true,
  height: drawerHeight(context, prefs),
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) {
      final photo = prefs.wallpaperPhoto != null;
      Future<void> pick() async {
        final path = await Apps.instance.pickPhoto();
        if (path == null) return;
        await prefs.setWallpaperPhoto(path);
        if (context.mounted) showPhotoEditor(context, prefs: prefs); // frame it straight away
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s12),
            child: SheetHeader(title: 'Wallpaper', subtitle: 'What sits behind your home screen'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DS.s24),
            child: Wrap(
              spacing: DS.s8,
              runSpacing: DS.s8,
              children: [
                _Chip(
                  label: 'Phone wallpaper',
                  selected: !photo,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    prefs.setWallpaperPhoto(null);
                  },
                ),
                _Chip(
                  label: 'Your photo',
                  selected: photo,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (!photo) pick();
                  },
                ),
              ],
            ),
          ),
          _DimSlider(prefs: prefs),
          _Group(null, [
            if (photo) ...[
              _NavRow(
                Icons.crop_rounded,
                'Adjust photo',
                'Zoom ${prefs.photoZoom.toStringAsFixed(1)}× · blur ${prefs.photoBlur < .5 ? 'off' : prefs.photoBlur.round()}',
                () => showPhotoEditor(context, prefs: prefs),
              ),
              _NavRow(Icons.photo_library_outlined, 'Choose another photo', 'From your gallery', pick),
            ] else
              _NavRow(Icons.image_outlined, 'Change phone wallpaper', 'Opens your phone’s picker', () {
                SheetHost.close(ctx);
                Apps.instance.openWallpaperPicker();
              }, external: true),
          ]),
          const SizedBox(height: DS.s8),
        ],
      );
    },
  ),
);

/// Settings → Search (2nd level): where the bar sits, pull-down gesture, open the only match.
Future<Object?> _showSearchSettings(BuildContext context, {required Prefs prefs}) => showOneSheetWith(
  context,
  back: true,
  height: drawerHeight(context, prefs),
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s4),
          child: SheetHeader(title: 'Search', subtitle: 'Find apps, or search the web'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s8),
          child: Text('Search bar', style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s24),
          child: Wrap(
            spacing: DS.s8,
            runSpacing: DS.s8,
            children: [
              for (final (id, label) in const [('bottom', 'At the bottom'), ('top', 'Top of the app drawer')])
                _Chip(
                  label: label,
                  selected: prefs.searchPosition == id,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    prefs.setSearchPosition(id);
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s24, 0),
          child: Text(
            prefs.searchPosition == 'top'
                ? 'Sits above your pinned apps, next to the settings button.'
                : 'Floats under your thumb; shrinks to a circle while you scroll.',
            style: DS.rowSub.copyWith(fontSize: 13),
          ),
        ),
        _Group(null, [
          _SwitchRow(Icons.swipe_down_alt_rounded, 'Pull down to search', 'Drag the app drawer down at its top', prefs.pullToSearch, prefs.setPullToSearch),
          _SwitchRow(Icons.bolt_rounded, 'Open the only match', 'When search finds just one app', prefs.autoOpenSingleMatch, prefs.setAutoOpenSingleMatch),
        ]),
        _Group('Search in', [
          for (final (id, icon, title, sub) in const [
            ('apps', Icons.apps_rounded, 'Apps', 'Everything installed, work apps too'),
            ('shortcuts', Icons.bolt_rounded, 'App shortcuts', 'Actions apps offer, like Scan QR or New message'),
            ('settings', Icons.settings_rounded, 'Phone settings', 'Wi-Fi, Bluetooth, Battery, Display…'),
            ('google', Icons.travel_explore_rounded, 'Google', 'Search the web for what you type'),
            ('play', Icons.shop_outlined, 'Play Store', 'Find new apps'),
          ])
            _SwitchRow(icon, title, sub, prefs.searchIn.contains(id), (v) => prefs.setSearchIn(id, v)),
        ]),
        const SizedBox(height: DS.s8),
      ],
    ),
  ),
);

/// Settings → Hidden apps (2nd level).
Future<Object?> _showHiddenApps(BuildContext context, {required Prefs prefs, required List<AppEntry> apps}) => showOneSheetWith(
  context,
  back: true,
  height: drawerHeight(context, prefs),
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
            child: SheetHeader(title: 'Hidden apps', subtitle: 'Long-press any app to hide it'),
          ),
          if (hidden.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s24),
              child: Text('No hidden apps.', style: DS.rowSub),
            )
          else
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
          const SizedBox(height: DS.s8),
        ],
      );
    },
  ),
);

/// A titled group of settings rows on one rounded tile, thin lines between rows.
class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);
  final String? title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.s16, DS.s16, DS.s16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s8, 0, DS.s8, DS.s8),
              child: Text(title!.toUpperCase(), style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(DS.rMedia),
            child: Material(
              color: DS.cardMuted,
              child: Column(
                children: [
                  for (final (i, r) in rows.indexed) ...[if (i > 0) Divider(height: 1, thickness: 1, indent: 72, endIndent: DS.s16, color: DS.hairline), r],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon disc + title + one-line summary of the current value; chevron (or ↗ for system screens).
class _NavRow extends StatelessWidget {
  const _NavRow(this.icon, this.title, this.subtitle, this.onTap, {this.external = false});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool external;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(DS.s16, DS.s12, DS.s12, DS.s12),
          child: Row(
            children: [
              _IconDisc(icon),
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: DS.rowSub.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: DS.s8),
              Icon(external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded, size: external ? 18 : 22, color: DS.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(this.icon, this.title, this.subtitle, this.value, this.onChanged);
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s12, DS.s8),
          child: Row(
            children: [
              _IconDisc(icon),
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: DS.rowSub.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Switch(
                value: value,
                activeThumbColor: DS.card,
                activeTrackColor: DS.ink,
                inactiveThumbColor: DS.inkFaint,
                inactiveTrackColor: DS.card,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconDisc extends StatelessWidget {
  const _IconDisc(this.icon);
  final IconData icon;

  // The theme's accent (the green card's colour): rows read at a glance, in any theme.
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(color: DS.hero, borderRadius: BorderRadius.circular(12)),
    child: Icon(icon, size: 21, color: DS.heroInk),
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

/// Clock style like the Pixel / iOS lock screen: one variable font, tuned with sliders
/// (weight, width, slant) plus quick presets. Changes show live behind the sheet too.
class _ClockStyleEditor extends StatelessWidget {
  const _ClockStyleEditor({required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final sample = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final w = prefs.clockWeight, wd = prefs.clockWidth, sl = prefs.clockSlant;

    Widget slider(String label, String low, String high, double value, double min, double max, int steps, void Function(double) set) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(DS.s24, DS.s4, DS.s16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: DS.rowTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w500)),
            Row(
              children: [
                SizedBox(width: 56, child: Text(low, style: DS.rowSub.copyWith(fontSize: 12))),
                Expanded(
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: steps,
                    activeColor: DS.ink,
                    inactiveColor: DS.cardMuted,
                    thumbColor: DS.ink,
                    onChanged: (x) {
                      if ((x - value).abs() > .01) HapticFeedback.selectionClick();
                      set(x);
                    },
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(high, style: DS.rowSub.copyWith(fontSize: 12), textAlign: TextAlign.end),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Live preview.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s24),
          child: Container(
            height: 112,
            padding: const EdgeInsets.symmetric(horizontal: DS.s20, vertical: DS.s8),
            decoration: BoxDecoration(color: DS.canvas, borderRadius: BorderRadius.circular(DS.rMedia)),
            child: FittedBox(
              child: Text(
                sample,
                style: clockStyle(weight: w, width: wd, slant: sl, round: prefs.clockRound).copyWith(shadows: const [], color: DS.onWallpaper),
              ),
            ),
          ),
        ),
        const SizedBox(height: DS.s12),
        // Presets.
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: DS.s24),
            itemCount: clockPresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: DS.s8),
            itemBuilder: (context, i) {
              final (name, pw, pwd, psl, pr) = clockPresets[i];
              return _Chip(
                label: name,
                selected: isClockPreset(clockPresets[i], prefs),
                onTap: () {
                  HapticFeedback.selectionClick();
                  prefs.setClockStyle(weight: pw, width: pwd, slant: psl, round: pr);
                },
              );
            },
          ),
        ),
        const SizedBox(height: DS.s8),
        slider('Weight', 'Thin', 'Heavy', w, 100, 1000, 18, (x) => prefs.setClockStyle(weight: x)),
        slider('Width', 'Narrow', 'Wide', wd, 25, 151, 21, (x) => prefs.setClockStyle(width: x)),
        // Slant runs 0 → −10; the slider shows it upright → italic.
        slider('Slant', 'Upright', 'Italic', -sl, 0, 10, 10, (x) => prefs.setClockStyle(slant: -x)),
        slider('Roundness', 'Sharp', 'Round', prefs.clockRound, 0, 100, 10, (x) => prefs.setClockStyle(round: x)),
      ],
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

/// Settings → Wallpaper dim: black over the wallpaper, 0–60%. Updates live.
class _DimSlider extends StatelessWidget {
  const _DimSlider({required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    final v = prefs.wallpaperDim;
    final pct = (v * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Wallpaper dim', style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
              ),
              Text(pct == 0 ? 'Off' : '$pct%', style: DS.rowSub),
            ],
          ),
          Row(
            children: [
              Icon(Icons.light_mode_outlined, size: 18, color: DS.inkMuted),
              Expanded(
                child: Slider(
                  value: v,
                  max: .6,
                  divisions: 12, // 5% steps
                  label: '$pct%',
                  activeColor: DS.ink,
                  inactiveColor: DS.cardMuted,
                  thumbColor: DS.ink,
                  onChanged: (x) {
                    if ((x - v).abs() > .01) HapticFeedback.selectionClick();
                    prefs.setWallpaperDim(x);
                  },
                ),
              ),
              Icon(Icons.dark_mode_outlined, size: 18, color: DS.inkMuted),
            ],
          ),
        ],
      ),
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
