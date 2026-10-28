import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'folders.dart';
import 'one_stream.dart';
import 'quick_chips.dart';
import 'prefs.dart';
import 'photo_wallpaper.dart';
import 'quick_actions.dart';
import 'tv_remote.dart';
import 'tiles/landing.dart';
import 'home.dart' show HomeScreen;
import 'tiles/tiles_home.dart' show TilesHome, addActionTile;
import 'tiles/day_line.dart' show showDaySlots;
import 'tiles/today_panel.dart' show openToday;
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

/// One of an app menu's main actions (the strip at the top of the menu).
class AppAction {
  const AppAction(this.icon, this.label, this.onTap, {this.danger = false, this.enabled = true});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger, enabled;
}

/// An app's long-press menu, in both views. A clear hierarchy so nothing gets lost however
/// many shortcuts an app has:
///  1. the app (icon, name, where it lives),
///  2. its main actions as one strip of big buttons — always at the top,
///  3. its shortcuts (New message, Scan QR, contacts…): the first four, then "Show all".
/// Classic: rounded buttons on the card; Metro (Tiles): flat boxes, lowercase.
Future<void> showAppActions(BuildContext context, {required AppEntry app, String? subtitle, required List<AppAction> actions, bool shortcuts = true}) async {
  final all = shortcuts ? await Apps.instance.shortcuts() ?? const <AppShortcut>[] : const <AppShortcut>[];
  final pkg = app.package.split('@').first;
  final mine = [
    for (final sc in all)
      if (sc.package == pkg && sc.work == app.work) sc,
  ];
  if (!context.mounted) return;
  HapticFeedback.mediumImpact();
  await showOneSheetWith(
    context,
    builder: (ctx) => _AppActionsBody(app: app, subtitle: subtitle, actions: actions, shortcuts: mine),
  );
}

class _AppActionsBody extends StatefulWidget {
  const _AppActionsBody({required this.app, required this.subtitle, required this.actions, required this.shortcuts});
  final AppEntry app;
  final String? subtitle;
  final List<AppAction> actions;
  final List<AppShortcut> shortcuts;

  @override
  State<_AppActionsBody> createState() => _AppActionsBodyState();
}

class _AppActionsBodyState extends State<_AppActionsBody> {
  static const _first = 4;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final metro = DS.metro;
    final shown = _all ? widget.shortcuts : widget.shortcuts.take(_first).toList();
    final more = widget.shortcuts.length - _first;
    Widget action(AppAction a) {
      final colour = !a.enabled ? DS.inkFaint : (a.danger ? DS.alert : DS.ink);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: metro ? Colors.transparent : DS.cardMuted,
            shape: metro
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DS.rMedia),
                    side: BorderSide(color: DS.hairline),
                  )
                : RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: a.enabled
                  ? () {
                      Navigator.pop(context);
                      a.onTap();
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: DS.s12, horizontal: 4),
                child: Column(
                  children: [
                    Icon(a.icon, color: colour),
                    const SizedBox(height: 6),
                    Text(
                      DS.cased(a.label),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: DS.rowSub.copyWith(color: colour, fontSize: 12, height: 1.2, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. The app.
        Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s16),
          child: SheetHeader(title: widget.app.label, subtitle: widget.subtitle, leading: AppIcon(widget.app, size: 48), yours: true),
        ),
        // 2. Its main actions: one strip, always at the top.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s16 - 4),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final a in widget.actions) action(a)]),
          ),
        ),
        // 3. Its shortcuts: the first few, the rest on request.
        if (widget.shortcuts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(DS.s24, DS.s20, DS.s24, DS.s4),
            child: Text(
              metro ? 'shortcuts' : 'SHORTCUTS',
              style: metro ? DS.eyebrow : DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w600),
            ),
          ),
          for (final sc in shown)
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Apps.instance.quickAction(sc.id);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: DS.s12),
                child: Row(
                  children: [
                    ShortcutIcon(id: sc.id, size: 28, color: DS.ink),
                    const SizedBox(width: DS.s16),
                    Expanded(
                      child: Text(
                        sc.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DS.rowTitle.copyWith(fontWeight: FontWeight.w400),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (more > 0 && !_all)
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _all = true);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: DS.s12),
                child: Row(
                  children: [
                    SizedBox(width: 28, child: Icon(Icons.expand_more_rounded, color: metro ? DS.accentText : DS.inkMuted)),
                    const SizedBox(width: DS.s16),
                    Text(
                      DS.cased('Show all ($more more)'),
                      style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500, color: metro ? DS.accentText : DS.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: DS.s8),
      ],
    );
  }
}

/// Long-press an app in the app view.
Future<void> showAppSheet(BuildContext context, {required Prefs prefs, required AppEntry app}) {
  final fav = prefs.isFavourite(app.package);
  final hidden = prefs.hidden.contains(app.package);
  final full = !fav && prefs.favouritesFull;
  final folder = folderFor(app, prefs.folderOverrides);
  return showAppActions(
    context,
    app: app,
    subtitle: '${app.work ? 'Work profile · ' : ''}In ${prefs.folderName(folder)}${app.paused ? ' · paused' : ''}',
    actions: [
      AppAction(
        fav ? Icons.push_pin : Icons.push_pin_outlined,
        fav ? 'Unpin' : (full ? 'Pins full' : 'Pin to top'),
        () => prefs.toggleFavourite(app.package),
        enabled: !full,
      ),
      AppAction(Icons.drive_file_move_outline, 'Move to folder', () => showFolderPicker(context, prefs: prefs, app: app)),
      AppAction(hidden ? Icons.visibility_rounded : Icons.visibility_off_outlined, hidden ? 'Show in list' : 'Hide', () => prefs.toggleHidden(app.package)),
      AppAction(Icons.info_outline_rounded, 'App info', () => Apps.instance.appInfo(app.package)),
      if (!app.system) AppAction(Icons.delete_outline_rounded, 'Uninstall', () => Apps.instance.uninstall(app.package), danger: true),
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
  if (folder.id == recentlyInstalled.id) return _customiseRecent(context, prefs: prefs);
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
        SheetAction(
          Icons.restart_alt_rounded,
          'Reset folder',
          () => then(() async {
            if (await confirmReset(context, title: 'Reset ${folder.name}?', body: 'Its name goes back to the automatic one, and apps you moved in go back to their own folders.')) {
              await prefs.resetFolder(folder.id);
            }
          }),
          danger: true,
        ),
      ] else ...[
        if (prefs.favourites.isNotEmpty) SheetAction(Icons.push_pin_outlined, 'Unpin all', () => then(prefs.unpinAll)),
        SheetAction(
          Icons.history_rounded,
          'Clear most-used history',
          () => then(() async {
            if (await confirmReset(context, title: 'Clear most-used history?', body: 'Most used starts learning again from scratch.', action: 'Clear')) {
              await prefs.clearLaunches();
            }
          }),
          danger: true,
        ),
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
  final r = await showEditor(
    context,
    title: 'Top of home',
    prefs: prefs,
    view: 'classic',
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
Future<Object?> _showClockStyle(BuildContext context, {required Prefs prefs}) => showEditor(
  context,
  title: 'Clock style',
  prefs: prefs,
  view: 'classic',
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
  final r = await showEditor(
    context,
    title: 'Quick actions',
    prefs: prefs,
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

/// Quick actions → Chip look: colour, opacity, shape, what to show, size, padding, gaps, outline. Short and
/// lightly shaded so the chips above it — on the home screen — show every change live.
Future<Object?> _showChipLook(BuildContext context, {required Prefs prefs}) => showEditor(
  context,
  title: 'Chip look',
  prefs: prefs,
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
      // A labelled slider in whole steps, with its value on the right.
      Widget slider(String title, double value, double min, double max, void Function(double) changed) {
        final v = value.clamp(min, max).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
                  ),
                  Text('${v.round()}', style: DS.rowSub),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DS.s8),
              child: Slider(
                value: v,
                min: min,
                max: max,
                divisions: (max - min).round(), // 1 dp steps
                label: '${v.round()}',
                activeColor: DS.ink,
                inactiveColor: DS.cardMuted,
                thumbColor: DS.ink,
                onChanged: (x) {
                  if (x.round() != v.round()) HapticFeedback.selectionClick();
                  changed(x.roundToDouble());
                },
              ),
            ),
          ],
        );
      }

      final pct = (look.opacity * 100).round();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, 0),
            child: SheetHeader(title: 'Chip look', subtitle: 'Changes show on the chips above'),
          ),
          // Tiles: chips are tiles — colour, corners and glass come from the tile look, so
          // only what they show and how big they are is theirs.
          if (DS.metro) ...[
            label('Size'),
            choices(ChipLook.sizes, look.size, (v) => set((l) => l.copyWith(size: v))),
            label('Show'),
            choices(ChipLook.contents, look.content, (v) => set((l) => l.copyWith(content: v))),
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, 0),
              child: Text('Colour, corners and glass follow your tiles (Home view → Look).', style: DS.rowSub.copyWith(fontSize: 13)),
            ),
            const SizedBox(height: DS.s8),
          ] else ...[
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
            label('Show'),
            choices(ChipLook.contents, look.content, (v) => set((l) => l.copyWith(content: v))),
            slider('Size', look.height, ChipLook.minHeight, ChipLook.maxHeight, (x) => set((l) => l.copyWith(height: x))),
            // Icon only: the space around the icon (0 = it fills the chip); otherwise around the label.
            look.content == 'icon'
                ? slider('Padding inside', look.iconPadding, 0, ChipLook.maxIconPadding, (x) => set((l) => l.copyWith(iconPadding: x)))
                : slider('Padding inside', look.padEnd, 0, ChipLook.maxPadding, (x) => set((l) => l.copyWith(padding: x))),
            slider('Gap between chips', look.gap, 0, ChipLook.maxGap, (x) => set((l) => l.copyWith(gap: x))),
            slider('Space above & below', look.rowPad, 0, ChipLook.maxSpace, (x) => set((l) => l.copyWith(space: x))),
            const SizedBox(height: DS.s8),
            _Group(null, [
              _SwitchRow(Icons.crop_square_rounded, 'Outline', 'Thin edge around each chip', look.outline, (v) => set((l) => l.copyWith(outline: v))),
              _NavRow(Icons.restart_alt_rounded, 'Reset look', 'Dark see-through pills', () async {
                if (!await confirmReset(ctx, title: 'Reset the chips’ look?', body: 'Back to dark see-through pills. Your chips stay.')) return;
                HapticFeedback.lightImpact();
                set((_) => const ChipLook());
              }),
            ]),
            const SizedBox(height: DS.s8),
          ],
        ],
      );
    },
  ),
);

/// Every app widget on the phone, grouped by app. Tap one to add it as a top page.
/// [onAdded]: where the new widget goes (the Tiles today page); default: a new top page.
Future<void> showWidgetPicker(BuildContext context, {required Prefs prefs, void Function(int id, String label)? onAdded}) async {
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
                                      final label = p.label == p.app ? p.label : '${p.app} · ${p.label}';
                                      onAdded != null ? onAdded(id, label) : await prefs.addWidgetPage(id, label);
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
  return showEditor(
    context,
    title: 'Colours & style',
    prefs: prefs,
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
              _Group(null, [
                _SwitchRow(
                  Icons.format_color_fill_rounded,
                  'Themed icons',
                  'One-colour icons in your theme’s colours, like Pixel',
                  prefs.themedIcons,
                  prefs.setThemedIcons,
                ),
              ]),
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
        // Classic: an ink pill. Metro: a flat box, the accent when chosen.
        color: selected ? (DS.metro ? DS.hero : DS.ink) : Colors.transparent,
        shape: DS.metro
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DS.rMedia),
                side: BorderSide(color: selected ? DS.hero : DS.inkFaint, width: 1.5),
              )
            : StadiumBorder(side: BorderSide(color: selected ? DS.ink : DS.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: 10),
              child: Text(
                label,
                style: DS.rowTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: selected ? (DS.metro ? Colors.white : DS.card) : DS.ink),
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
    height: MediaQuery.sizeOf(context).height, // full screen (its pages too)
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
              Icons.space_dashboard_outlined,
              'Home view',
              prefs.homeView == 'tiles' ? 'Tiles · Start + all apps A–Z' : 'Classic · clock on top, apps below',
              keywords: 'tiles lumia windows start grid classic layout view face',
              open: (c) {
                // A full-screen editor with your home screen live in the middle.
                SheetHost.close(c);
                showHomeEditor(context, prefs: prefs, theme: theme);
              },
            ),
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
              Icons.view_sidebar_outlined,
              'Today panel',
              prefs.homeView == 'tiles'
                  ? '${prefs.todayLayout == 'list' ? 'List' : 'Tiles'} · swipe right from Start'
                  : (prefs.classicToday ? '${prefs.todayLayout == 'list' ? 'List' : 'Cards'} · swipe right on home' : 'Off'),
              keywords: 'today side panel left swipe widgets your day week notes calendar music',
              open: (c) => _showTodaySettings(c, prefs: prefs),
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
              Icons.new_releases_outlined,
              'Recently installed',
              prefs.recentInstalls ? 'Folder on · last ${recentPeriodName(prefs.recentDays)}' : 'Folder hidden',
              keywords: 'new apps installed folder dot week',
              open: (c) => _showRecentSettings(c, prefs: prefs),
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
                // Metro: the big light lowercase page title.
                child: Text(DS.cased('Settings'), style: DS.title.copyWith(fontSize: DS.metro ? 44 : 28)),
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

/// Settings → Look → Home view: a full-screen editor (like Pixel's wallpaper & style): your
/// home screen live in the middle, the controls below in tabs. Every change applies at once.
Future<void> showHomeEditor(BuildContext context, {required Prefs prefs, required OneTheme theme}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    transitionDuration: Motion.snapDuration,
    reverseTransitionDuration: Motion.snapDuration,
    pageBuilder: (_, _, _) => _HomeEditor(prefs: prefs, theme: theme),
    transitionsBuilder: (_, a, _, child) => FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  ),
);

class _HomeEditor extends StatefulWidget {
  const _HomeEditor({required this.prefs, required this.theme});
  final Prefs prefs;
  final OneTheme theme;

  @override
  State<_HomeEditor> createState() => _HomeEditorState();
}

class _HomeEditorState extends State<_HomeEditor> {
  String _tab = 'view';
  Prefs get prefs => widget.prefs;
  bool get _tiles => prefs.homeView == 'tiles';

  List<(String, IconData, String)> get _tabs => _tiles
      ? const [
          ('view', Icons.space_dashboard_outlined, 'View'),
          ('layout', Icons.grid_view_rounded, 'Layout'),
          ('look', Icons.palette_outlined, 'Look'),
          ('clock', Icons.schedule_rounded, 'Clock'),
          ('motion', Icons.animation_rounded, 'Motion'),
          ('touch', Icons.touch_app_outlined, 'Interactions'),
        ]
      : const [('view', Icons.space_dashboard_outlined, 'View'), ('look', Icons.palette_outlined, 'Look'), ('clock', Icons.schedule_rounded, 'Clock')];

  // ---- small building blocks ----

  Widget _label(String t, [String? value]) => Padding(
    padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s8),
    child: Row(
      children: [
        Expanded(
          child: Text(t, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
        ),
        if (value != null) Text(value, style: DS.rowSub),
      ],
    ),
  );

  Widget _chips(List<(String, String)> options, String current, ValueChanged<String> pick) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: DS.s24),
    child: Wrap(
      spacing: DS.s8,
      runSpacing: DS.s8,
      children: [
        for (final (id, name) in options)
          _Chip(
            label: name,
            selected: current == id,
            onTap: () {
              HapticFeedback.selectionClick();
              pick(id);
            },
          ),
      ],
    ),
  );

  Widget _slider(double value, double max, int steps, ValueChanged<double> set, {String? low, String? high}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: DS.s12),
    child: Row(
      children: [
        if (low != null)
          Padding(
            padding: const EdgeInsets.only(left: DS.s12),
            child: Text(low, style: DS.rowSub.copyWith(fontSize: 12)),
          ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            divisions: steps,
            activeColor: DS.ink,
            inactiveColor: DS.cardMuted,
            thumbColor: DS.ink,
            onChanged: set,
          ),
        ),
        if (high != null)
          Padding(
            padding: const EdgeInsets.only(right: DS.s12),
            child: Text(high, style: DS.rowSub.copyWith(fontSize: 12)),
          ),
      ],
    ),
  );

  Widget _hint(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(DS.s24, DS.s12, DS.s24, 0),
    child: Text(t, style: DS.rowSub.copyWith(fontSize: 13)),
  );

  Widget _viewCard(String id, IconData icon, String title, String sub) {
    final on = prefs.homeView == id;
    return Expanded(
      child: Material(
        color: on ? DS.hero : DS.cardMuted,
        borderRadius: BorderRadius.circular(DS.rMedia),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            prefs.setHomeView(id);
          },
          child: Padding(
            padding: const EdgeInsets.all(DS.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 32, color: on ? DS.heroInk : DS.ink),
                const SizedBox(height: DS.s12),
                Text(title, style: DS.rowTitle.copyWith(color: on ? DS.heroInk : DS.ink)),
                const SizedBox(height: 2),
                Text(sub, style: DS.rowSub.copyWith(fontSize: 12, color: on ? DS.heroInk.withValues(alpha: .75) : DS.inkMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Frost, tint, edge, sheen — shared by glass tiles and the glass Classic home.
  List<Widget> _glassControls(BuildContext context) => [
    _label('Frost'),
    _slider(
      prefs.glassBlur,
      40,
      16,
      (x) => prefs.setGlass(blur: x),
      low: 'Clear',
      high: 'Frosted',
    ),
    _label('Tint'),
    _slider(
      prefs.glassTint,
      .7,
      14,
      (x) => prefs.setGlass(tint: x),
      low: 'None',
      high: 'Strong',
    ),
    _Group(null, [
      _SwitchRow(Icons.crop_square_rounded, 'Bright edge', 'A thin light border, like a glass pane', prefs.glassEdge, (v) => prefs.setGlass(edge: v)),
      _SwitchRow(Icons.gradient_rounded, 'Sheen', 'A soft light across the top corner', prefs.glassSheen, (v) => prefs.setGlass(sheen: v)),
    ]),
    if (prefs.wallpaperPhoto == null)
      _hint('Frost blurs “Your photo” wallpaper (Settings → Wallpaper). With the phone’s own wallpaper, glass shows the tint and highlights only.'),
  ];

  // ---- tabs ----

  List<Widget> _section(BuildContext context) => switch (_tab) {
    'view' => [
      Padding(
        padding: const EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s16, 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _viewCard('classic', Icons.view_agenda_outlined, 'Classic', 'Clock on top, app drawer with folders below'),
              const SizedBox(width: DS.s12),
              _viewCard('tiles', Icons.grid_view_rounded, 'Tiles', 'Live tiles; swipe left for all apps A–Z'),
            ],
          ),
        ),
      ),
      _Group(null, [
        _SwitchRow(
          Icons.format_color_fill_rounded,
          'Themed icons',
          'One-colour icons in your theme’s colours, like Pixel',
          prefs.themedIcons,
          prefs.setThemedIcons,
        ),
        // Classic: the today panel left of home (Tiles always has its today page).
        if (!_tiles) _SwitchRow(Icons.view_sidebar_outlined, 'Today panel', 'Your widgets · swipe right on home', prefs.classicToday, prefs.setClassicToday),
      ]),
    ],
    'layout' => [
      _label('Columns'),
      _chips(const [('4', '4 · bigger tiles'), ('6', '6 · more tiles')], '${prefs.tileColumns}', (v) => prefs.setTileLook(columns: int.parse(v))),
      _label('Icons'),
      _chips(const [('glyph', 'Themed glyphs'), ('icon', 'App icons')], prefs.tileIcons, (v) => prefs.setTileLook(icons: v)),
      _label('Corner roundness', prefs.tileRadius == 0 ? 'Square' : '${prefs.tileRadius.round()} dp'),
      _slider(prefs.tileRadius, 32, 16, (x) => prefs.setTileLook(radius: x)),
      _Group(null, [
        _SwitchRow(Icons.label_outline_rounded, 'Names on tiles', 'On medium and bigger tiles', prefs.tileLabels, (v) => prefs.setTileLook(labels: v)),
        _NavRow(Icons.add_box_outlined, 'Add a quick action tile', 'Quick actions row, flashlight, timer, app shortcuts…', () => addActionTile(context, prefs)),
        _NavRow(Icons.restart_alt_rounded, 'Reset Start', 'Back to the starting tiles', () async {
          if (!await confirmReset(context, title: 'Reset Start?', body: 'Your tiles, their sizes and colours go back to the starting set.')) return;
          HapticFeedback.mediumImpact();
          await prefs.resetTiles();
        }),
      ]),
      _hint('On Start, long-press a tile to resize, recolour, unpin or drag it. In all apps, long-press an app to pin it.'),
    ],
    'look' when _tiles => [
      _label('Tile look'),
      _chips(const [('solid', 'Solid'), ('glass', 'Glass')], prefs.tileStyle, (v) => prefs.setGlass(style: v)),
      if (prefs.tileStyle == 'glass') ..._glassControls(context),
      _label('Tile colours'),
      _chips(const [('accent', 'Accent'), ('colourful', 'Each app’s colour')], prefs.tileColours, prefs.setTileColours),
      _label('Tile transparency', prefs.tileOpacity >= .99 ? 'Solid' : '${((1 - prefs.tileOpacity) * 100).round()}% see-through'),
      _slider(1 - prefs.tileOpacity, .7, 14, (x) => prefs.setTileLook(opacity: 1 - x)),
      _Group(null, [
        _NavRow(
          Icons.wallpaper_rounded,
          'Wallpaper',
          prefs.wallpaperPhoto != null ? 'Your photo' : 'Phone wallpaper',
          () => _showWallpaperSheet(context, prefs: prefs),
        ),
      ]),
    ],
    'look' => [
      // Glass: the drawer, its cards, the chips and the dock become frosted panes.
      _label('Home look'),
      _chips(const [('solid', 'Solid'), ('glass', 'Glass')], prefs.classicStyle, (v) => prefs.setGlass(classic: v)),
      if (prefs.classicStyle == 'glass') ..._glassControls(context),
      _Group(null, [
        _NavRow(Icons.palette_outlined, 'Colours & style', 'Theme, accent, cards', () => showColoursSheet(context, prefs: prefs, theme: widget.theme)),
        _NavRow(
          Icons.wallpaper_rounded,
          'Wallpaper',
          prefs.wallpaperPhoto != null ? 'Your photo' : 'Phone wallpaper',
          () => _showWallpaperSheet(context, prefs: prefs),
        ),
      ]),
    ],
    'clock' => [
      _hint(_tiles ? 'The clock tile’s own style — the classic clock keeps its own.' : 'The classic clock’s style — the Tiles clock tile keeps its own.'),
      const SizedBox(height: DS.s8),
      _ClockStyleEditor(prefs: prefs, tile: _tiles),
    ],
    'motion' => [
      _label('Start animation'),
      _chips(landingStyles, prefs.tileAnim, (v) {
        prefs.setLandingAnims(tiles: v);
        startLanding.play(); // play it in the preview
      }),
      _label('All apps animation'),
      _chips(landingStyles, prefs.listAnim, (v) => prefs.setLandingAnims(list: v)),
      _Group(null, [_NavRow(Icons.replay_rounded, 'Play the landing', 'See Start come in again', startLanding.play)]),
    ],
    _ => [
      _Group(null, [
        for (final (id, icon, title, sub) in const [
          ('tilt', Icons.touch_app_outlined, 'Tilt on press', 'Tiles lean toward your finger'),
          ('live', Icons.flip_rounded, 'Live tiles', 'Flip to what’s playing, new notifications, next alarm'),
          ('turnstile', Icons.door_sliding_outlined, 'Turnstile on launch', 'Start swings away as an app opens'),
          ('window', Icons.wallpaper_rounded, 'Wallpaper through tiles', 'The wallpaper shows only inside tiles'),
          ('folders', Icons.folder_copy_outlined, 'Folders on Start', 'Hold a tile over another to make a folder'),
          ('badges', Icons.mark_chat_unread_outlined, 'Notification badges', 'Unread counts on tiles · needs Notification access'),
          ('lock', Icons.lock_outline_rounded, 'Double-tap to lock', 'Empty space · needs an Accessibility switch'),
          ('shortcuts', Icons.bolt_rounded, 'Shortcuts on tiles', 'App shortcuts in tile and app menus'),
        ])
          _SwitchRow(icon, title, sub, prefs.fx(id), (v) {
            prefs.setFx(id, v);
            // Badges and live tiles read notification counts: ask for access if needed.
            if (v && (id == 'badges' || id == 'live') && Apps.instance.media.value?['granted'] != true) Apps.instance.openNotificationAccess();
            if (v && id == 'badges') Apps.instance.refreshNotifCounts();
          }),
      ]),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        if (!_tabs.any((t) => t.$1 == _tab)) _tab = 'view';
        return _EditorFrame(
          title: 'Home screen',
          prefs: prefs,
          panelKey: ValueKey(_tab), // each tab opens at its top
          panel: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _section(context)),
          // Tabs, like Pixel's Style · Colour · Size.
          // Metro: a pivot — lowercase words, the current one bright, the rest dim.
          tabs: DS.metro
              ? SizedBox(
                  height: 52,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                    child: Row(
                      children: [
                        for (final (id, _, name) in _tabs)
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _tab = id);
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, DS.s8, DS.s20, DS.s8),
                              child: Text(
                                name.toLowerCase(),
                                style: TextStyle(fontFamily: DS.font, fontSize: 24, fontWeight: FontWeight.w300, color: _tab == id ? DS.ink : DS.inkFaint),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              : Container(
                  margin: const EdgeInsets.fromLTRB(DS.s16, 0, DS.s16, DS.s12),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: DS.card, borderRadius: BorderRadius.circular(32)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (id, icon, name) in _tabs)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Material(
                              color: _tab == id ? DS.cardMuted : Colors.transparent,
                              shape: const StadiumBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _tab = id);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s12),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_tab == id) ...[Icon(icon, size: 20, color: DS.ink), const SizedBox(width: DS.s8)],
                                      Text(name, style: DS.rowTitle.copyWith(fontSize: 15, fontWeight: _tab == id ? FontWeight.w600 : FontWeight.w400)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Any look setting as an editor (like the Home screen editor): ✕ · title · Done, your home
/// screen live in the middle, this page's controls below. Changes apply as you make them.
/// [view] previews a particular home ('classic' for its clock, top, layout…), else yours.
Future<Object?> showEditor(BuildContext context, {required String title, required Prefs prefs, String? view, required WidgetBuilder builder}) =>
    Navigator.of(context, rootNavigator: true).push<Object?>(
      _editorRoute(
        (_) => _EditorFrame(
          title: title,
          prefs: prefs,
          view: view,
          panel: Builder(builder: builder),
        ),
      ),
    );

PageRouteBuilder<Object?> _editorRoute(WidgetBuilder page) => PageRouteBuilder<Object?>(
  transitionDuration: Motion.snapDuration,
  reverseTransitionDuration: Motion.snapDuration,
  pageBuilder: (context, _, _) => page(context),
  transitionsBuilder: (_, a, _, child) => FadeTransition(
    opacity: a,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
);

/// The editor layout: ✕ · title · Done; the live preview; the controls panel; optional tabs.
class _EditorFrame extends StatelessWidget {
  const _EditorFrame({required this.title, required this.prefs, required this.panel, this.view, this.tabs, this.panelKey});
  final String title;
  final Prefs prefs;
  final Widget panel;
  final String? view;
  final Widget? tabs;
  final Key? panelKey;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: DS.metro ? DS.canvas : DS.cardMuted,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s16, DS.s8),
              child: Row(
                children: [
                  Material(
                    color: DS.metro ? Colors.transparent : DS.card,
                    shape: const CircleBorder(),
                    // Back to where it was opened from (Settings, or the home screen).
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_rounded, color: DS.ink),
                    ),
                  ),
                  const SizedBox(width: DS.s16),
                  Expanded(
                    child: Text(
                      DS.cased(title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DS.metro ? DS.title : DS.rowTitle.copyWith(fontSize: 24, fontWeight: FontWeight.w500),
                    ),
                  ),
                  FilledButton(
                    // Classic: an ink pill. Metro: a flat accent box.
                    style: FilledButton.styleFrom(
                      backgroundColor: DS.metro ? DS.hero : DS.ink,
                      foregroundColor: DS.metro ? Colors.white : DS.card,
                      shape: DS.metro ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)) : const StadiumBorder(),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(DS.cased('Done')),
                  ),
                ],
              ),
            ),
            // The live preview: your home screen, scaled down.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: DS.s8),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: screen.width / screen.height,
                    child: ListenableBuilder(
                      listenable: prefs,
                      builder: (context, _) => _HomePreview(prefs: prefs, view: view ?? prefs.homeView),
                    ),
                  ),
                ),
              ),
            ),
            // This page's controls.
            Container(
              margin: EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s16, tabs == null ? DS.s12 : DS.s8),
              height: screen.height * (tabs == null ? .4 : .34),
              decoration: BoxDecoration(color: DS.card, borderRadius: BorderRadius.circular(DS.rCard)),
              clipBehavior: Clip.antiAlias,
              child: EditorScope(
                child: SingleChildScrollView(
                  key: panelKey,
                  padding: const EdgeInsets.only(top: DS.s12, bottom: DS.s16),
                  child: panel,
                ),
              ),
            ),
            ?tabs,
          ],
        ),
      ),
    );
  }
}

/// The editor's preview: the real home screen (Classic or Tiles) at full phone size, scaled to
/// fit, not touchable. It follows every setting live.
class _HomePreview extends StatelessWidget {
  const _HomePreview({required this.prefs, required this.view});
  final Prefs prefs;
  final String view;

  @override
  Widget build(BuildContext context) {
    final theme = OneTheme.current!;
    final phone = MediaQueryData.fromView(View.of(context)).copyWith(viewInsets: EdgeInsets.zero);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DS.rCard),
        border: Border.all(color: DS.hairline, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DS.rCard),
        child: IgnorePointer(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox.fromSize(
              size: phone.size,
              child: MediaQuery(
                data: phone,
                child: ColoredBox(
                  color: Colors.black,
                  child: view == 'tiles'
                      ? TilesHome(key: const ValueKey('preview-tiles'), prefs: prefs, theme: theme, preview: true)
                      : HomeScreen(key: const ValueKey('preview-classic'), prefs: prefs, theme: theme, preview: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
              if (!await confirmReset(ctx, title: 'Forget ${prefs.tvName}?', body: 'The remote stops working until you pair again with a code on the TV.', action: 'Forget')) return;
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

/// How far back an install counts as recent (days → name).
const recentPeriods = [(3, '3 days'), (7, '1 week'), (14, '2 weeks'), (30, '1 month')];
String recentPeriodName(int days) => recentPeriods.where((p) => p.$1 == days).firstOrNull?.$2 ?? '$days days';

/// The Recently installed folder's ⋯: rename, its time period, hide it.
Future<void> _customiseRecent(BuildContext context, {required Prefs prefs}) {
  void then(VoidCallback f) {
    Navigator.pop(context);
    f();
  }

  return showOneSheet(
    context,
    header: SheetHeader(
      title: 'Customise',
      subtitle: '${prefs.folderName(recentlyInstalled)} · last ${recentPeriodName(prefs.recentDays)}',
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: DS.ink, shape: BoxShape.circle),
        child: Icon(recentlyInstalled.icon, color: DS.card),
      ),
    ),
    actions: [
      SheetAction(Icons.edit_outlined, 'Rename', () => then(() => showRenameFolder(context, prefs: prefs, folder: recentlyInstalled))),
      SheetAction(Icons.date_range_rounded, 'Time period', () => then(() => _showRecentSettings(context, prefs: prefs))),
      SheetAction(Icons.visibility_off_outlined, 'Hide this folder', () => then(() => prefs.setRecentInstalls(on: false))),
    ],
  );
}

/// Settings → Recently installed: show the folder or not, and how far back it looks.
Future<Object?> _showRecentSettings(BuildContext context, {required Prefs prefs}) => showOneSheetWith(
  context,
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s4),
          child: SheetHeader(title: 'Recently installed', subtitle: 'A folder at the top of your apps'),
        ),
        _Group(null, [
          _SwitchRow(Icons.new_releases_outlined, 'Show the folder', 'Above your other folders', prefs.recentInstalls, (v) => prefs.setRecentInstalls(on: v)),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s8),
          child: Text(DS.cased('Apps installed in the last'), style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s24),
          child: Wrap(
            spacing: DS.s8,
            runSpacing: DS.s8,
            children: [
              for (final (days, name) in recentPeriods)
                _Chip(
                  label: DS.cased(name),
                  selected: prefs.recentDays == days,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    prefs.setRecentInstalls(days: days);
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s16),
          child: Text(
            DS.cased('New apps get a dot on their icon until you open them once. They stay in the folder for the whole period.'),
            style: DS.rowSub.copyWith(fontSize: 13),
          ),
        ),
      ],
    ),
  ),
);

/// Settings → Today panel: the widgets page left of home — on or off (Classic), cards/tiles or a
/// list, the background, your week, reset; "Open the panel" goes there to add and move widgets.
/// One set of widgets for both views (see docs/DESIGN_LANGUAGES.md).
Future<Object?> _showTodaySettings(BuildContext context, {required Prefs prefs}) => showOneSheetWith(
  context,
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) {
      final classic = prefs.homeView != 'tiles';
      final on = !classic || prefs.classicToday;
      Widget label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s8),
        child: Text(DS.cased(t), style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
      );
      Widget chips(List<(String, String)> options, String current, ValueChanged<String> pick) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: DS.s24),
        child: Wrap(
          spacing: DS.s8,
          runSpacing: DS.s8,
          children: [
            for (final (id, name) in options)
              _Chip(
                label: DS.cased(name),
                selected: current == id,
                onTap: () {
                  HapticFeedback.selectionClick();
                  pick(id);
                },
              ),
          ],
        ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s4),
            child: SheetHeader(title: 'Today panel', subtitle: classic ? 'Your widgets, a swipe right from home' : 'Your widgets, a swipe right from Start'),
          ),
          if (classic)
            _Group(null, [
              _SwitchRow(Icons.view_sidebar_outlined, 'Side panel', 'Left of home · swipe right to open', prefs.classicToday, prefs.setClassicToday),
            ]),
          if (on) ...[
            label('Layout'),
            chips([('tiles', classic ? 'Cards' : 'Tiles'), ('list', 'List')], prefs.todayLayout, (v) => prefs.setTodayLook(layout: v)),
            if (prefs.todayLayout != 'list') ...[
              label(classic ? 'Card height' : 'Tile height'),
              chips([('grid', 'Fixed grid'), ('hug', 'Hug content')], prefs.todayHug ? 'hug' : 'grid', (v) => prefs.setTodayLook(hug: v == 'hug')),
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
                child: Text(DS.cased('For all widgets. Each one can have its own: ✎ on the panel → ⋯ → Height.'), style: DS.rowSub.copyWith(fontSize: 13)),
              ),
            ],
            label('Background'),
            chips([('wallpaper', 'Wallpaper'), ('black', classic ? 'Plain' : 'Black')], prefs.todayBg, (v) => prefs.setTodayLook(bg: v)),
            _Group(null, [
              if (classic)
                _NavRow(Icons.arrow_forward_rounded, 'Open the panel', 'Tap ✎ there to add, resize and move widgets', () {
                  SheetHost.close(ctx);
                  openToday.ping();
                }),
              _NavRow(Icons.linear_scale_rounded, 'Your week', 'The slots on the Your day line', () => showDaySlots(ctx, prefs: prefs)),
              _NavRow(Icons.restart_alt_rounded, 'Reset widgets', 'Back to the starting set', () async {
                if (!await confirmReset(ctx, title: 'Reset widgets?', body: 'The Today panel goes back to its starting widgets. Ones you added, sizes and order are lost.')) return;
                HapticFeedback.mediumImpact();
                await prefs.setTodayTiles(null);
              }),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s24, DS.s12, DS.s24, 0),
              child: Text(DS.cased('One set of widgets for both home views — each shows them in its own look.'), style: DS.rowSub.copyWith(fontSize: 13)),
            ),
          ],
          const SizedBox(height: DS.s16),
        ],
      );
    },
  ),
);

/// Settings → Layout (2nd level): split + padding. Short sheet, so the home updates in view.
Future<Object?> _showLayoutSheet(BuildContext context, {required Prefs prefs}) => showEditor(
  context,
  title: 'Layout',
  prefs: prefs,
  view: 'classic',
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
Future<Object?> _showWallpaperSheet(BuildContext context, {required Prefs prefs}) => showEditor(
  context,
  title: 'Wallpaper',
  prefs: prefs,
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
                '${prefs.homeView == 'tiles' ? 'Tiles · full screen' : 'Classic · top area'} · zoom ${prefs.photoFrame(tiles: prefs.homeView == 'tiles').$1.toStringAsFixed(1)}× · blur ${prefs.photoBlur < .5 ? 'off' : prefs.photoBlur.round()}',
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
Future<Object?> _showSearchSettings(BuildContext context, {required Prefs prefs}) => showEditor(
  context,
  title: 'Search',
  prefs: prefs,
  view: 'classic',
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
          // Off: asks first, since the saved searches go too.
          _SwitchRow(Icons.history_rounded, 'Save search history', 'Recent searches show when search opens', prefs.saveSearchHistory, (v) async {
            if (!v && !await confirmReset(ctx, title: 'Stop saving searches?', body: 'Your recent searches are cleared too.', action: 'Turn off')) return;
            prefs.setSaveSearchHistory(v);
          }),
        ]),
        _Group('Search in', [
          for (final (id, icon, title, sub) in [
            ('apps', Icons.apps_rounded, 'Apps', 'Everything installed, work apps too'),
            ('shortcuts', Icons.bolt_rounded, 'App shortcuts', 'Actions apps offer, like Scan QR or New message'),
            ('settings', Icons.settings_rounded, 'Phone settings', 'Wi-Fi, Bluetooth, Battery, Display…'),
            ('google', Icons.travel_explore_rounded, 'Google', 'Search the web for what you type'),
            ('play', Icons.shop_outlined, 'Play Store', 'Find new apps'),
            // Only when One Stream is installed (and answers us).
            if (OneStream.instance.available.value) ('onestream', Icons.movie_outlined, 'Movies & shows', 'From One Stream, as you type'),
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
              // Classic: small caps label. Metro: the accent, lowercase, light.
              child: DS.metro
                  ? Text(title!.toLowerCase(), style: DS.eyebrow)
                  : Text(
                      title!.toUpperCase(),
                      style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w600),
                    ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(DS.rMedia),
            child: Material(
              // Metro groups have no box: rows sit straight on the page, no dividers.
              color: DS.metro ? Colors.transparent : DS.cardMuted,
              child: Column(
                children: [
                  for (final (i, r) in rows.indexed) ...[
                    if (i > 0 && !DS.metro) Divider(height: 1, thickness: 1, indent: 72, endIndent: DS.s16, color: DS.hairline),
                    r,
                  ],
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
                // Metro: the accent when on.
                activeThumbColor: DS.metro ? Colors.white : DS.card,
                activeTrackColor: DS.metro ? DS.hero : DS.ink,
                inactiveThumbColor: DS.inkFaint,
                inactiveTrackColor: DS.metro ? Colors.transparent : DS.card,
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
    // Metro: an accent tile (the tile corner setting) instead of a rounded disc.
    decoration: BoxDecoration(color: DS.hero, borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : 12)),
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
  const _ClockStyleEditor({required this.prefs, this.tile = false});
  final Prefs prefs;
  final bool tile; // the Tiles view's clock tile (its own saved style)

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final sample = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final w = tile ? prefs.tileClockWeight : prefs.clockWeight, wd = tile ? prefs.tileClockWidth : prefs.clockWidth;
    final sl = tile ? prefs.tileClockSlant : prefs.clockSlant, rd = tile ? prefs.tileClockRound : prefs.clockRound;
    final set = tile ? prefs.setTileClockStyle : prefs.setClockStyle;
    bool isPreset((String, double, double, double, double) p) =>
        (w - p.$2).abs() < 1 && (wd - p.$3).abs() < 1 && (sl - p.$4).abs() < .1 && (rd - p.$5).abs() < 1;

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
                style: clockStyle(weight: w, width: wd, slant: sl, round: rd).copyWith(shadows: const [], color: DS.onWallpaper),
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
                selected: isPreset(clockPresets[i]),
                onTap: () {
                  HapticFeedback.selectionClick();
                  set(weight: pw, width: pwd, slant: psl, round: pr);
                },
              );
            },
          ),
        ),
        const SizedBox(height: DS.s8),
        slider('Weight', 'Thin', 'Heavy', w, 100, 1000, 18, (x) => set(weight: x)),
        slider('Width', 'Narrow', 'Wide', wd, 25, 151, 21, (x) => set(width: x)),
        // Slant runs 0 → −10; the slider shows it upright → italic.
        slider('Slant', 'Upright', 'Italic', -sl, 0, 10, 10, (x) => set(slant: -x)),
        slider('Roundness', 'Sharp', 'Round', rd, 0, 100, 10, (x) => set(round: x)),
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
