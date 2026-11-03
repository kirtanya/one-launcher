import 'package:flutter/material.dart';

import '../apps.dart';
import '../app_lock_ui.dart';
import '../prefs.dart';
import '../sheets.dart' show showHiddenApps;
import '../ui/ds.dart';
import '../widgets.dart';
import 'pixel_icon.dart';
import 'pixel_model.dart';

/// Pixel view → long-press home → "Home settings": every [PixelSettings] option, grouped like
/// Pixel Launcher's own Home settings page, under a live mini preview. Rebuilds on [prefs].
Future<void> showPixelHomeSettings(BuildContext context, {required Prefs prefs}) async {
  await showOneSheetWith(context, builder: (ctx) => _PixelSettingsBody(prefs: prefs));
}

class _PixelSettingsBody extends StatelessWidget {
  const _PixelSettingsBody({required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final s = PixelSettings.of(prefs);
        void set(String k, Object? v) => s.copyWith(k, v).save(prefs);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: DS.s24),
              child: SheetHeader(title: 'Home settings', subtitle: 'Pixel home screen'),
            ),
            Center(child: Padding(padding: const EdgeInsets.only(top: DS.s16), child: _Preview(s))),
            _Group('App grid', [
              _Block(
                Icons.grid_view_rounded,
                'Home grid',
                'Columns × rows on each home page',
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final g in pixelGrids.keys)
                    ChoiceChip(label: Text(g), selected: s.grid == g, onSelected: (_) => set('grid', g)),
                ]),
              ),
              _Block(
                Icons.view_column_outlined,
                'All apps columns',
                'Apps per row in the app drawer',
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [for (final n in [4, 5, 6]) ButtonSegment(value: n, label: Text('$n'))],
                  selected: {s.drawerCols},
                  onSelectionChanged: (v) => set('drawerCols', v.first),
                ),
              ),
            ]),
            _Group('Icons', [
              _Block(
                Icons.photo_size_select_large_rounded,
                'Icon size',
                '${(s.iconScale * 100).round()}% of the grid\'s natural size',
                Slider(
                  min: 70,
                  max: 130,
                  divisions: 12,
                  value: (s.iconScale * 100).roundToDouble(),
                  label: '${(s.iconScale * 100).round()}%',
                  onChanged: (v) => set('iconScale', v.round() / 100),
                ),
              ),
              _Block(
                Icons.interests_outlined,
                'Icon shape',
                'The shape every app icon is cut to',
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final sh in pixelShapes) _ShapeChoice(sh, selected: s.iconShape == sh, onTap: () => set('iconShape', sh)),
                  ]),
                ),
              ),
              _Switch(Icons.palette_outlined, 'Themed icons', 'Tint icons with your wallpaper colours', prefs.themedIcons, prefs.setThemedIcons),
              _Switch(Icons.label_outline_rounded, 'Labels on home', 'Show app names under home icons', s.labels, (v) => set('labels', v)),
              _Switch(Icons.label_outline_rounded, 'Labels in all apps', 'Show app names in the app drawer', s.drawerLabels, (v) => set('drawerLabels', v)),
              _Switch(Icons.circle_notifications_outlined, 'Notification dots', 'A dot on apps with new notifications', s.notifDots, (v) => set('notifDots', v)),
            ]),
            _Group('Home screen', [
              _Switch(Icons.wb_sunny_outlined, 'At a Glance', 'Date, weather and next event at the top', s.glance, (v) => set('glance', v)),
              _Switch(Icons.search_rounded, 'Search bar', 'The Google search pill at the bottom', s.searchBar, (v) => set('searchBar', v)),
              _Row(
                Icons.dock_rounded,
                'Dock icons',
                'How many apps fit in the dock',
                trailing: _Stepper(s.dockCount, 3, 7, (v) => set('dockCount', v)),
              ),
              _Switch(Icons.swipe_rounded, 'Scrolling dock', 'Swipe the dock sideways when it holds more', s.dockScroll, (v) => set('dockScroll', v)),
              _Switch(Icons.add_to_home_screen_rounded, 'Add new apps to home', 'Put newly installed apps on the home screen', s.addNewApps, (v) => set('addNewApps', v)),
              _Switch(Icons.lock_outline_rounded, 'Lock home layout', 'Stop icons being moved or removed by accident', s.lockLayout, (v) => set('lockLayout', v)),
              _Switch(Icons.folder_open_rounded, 'Big folders', 'Open folders full screen with a bigger grid', s.bigFolders, (v) => set('bigFolders', v)),
              _Switch(Icons.view_carousel_outlined, 'Left panel (Today)', 'Swipe right from the first page for Today', s.leftPanel, (v) => set('leftPanel', v)),
            ]),
            _Group('Gestures', [
              _Switch(Icons.touch_app_outlined, 'Double-tap to sleep', 'Double-tap empty space to turn the screen off', s.doubleTapSleep, (v) => set('doubleTapSleep', v)),
              _Switch(Icons.notifications_none_rounded, 'Swipe down for notifications', 'Pull the shade down from the home screen', s.swipeDownShade, (v) => set('swipeDownShade', v)),
              _Block(
                Icons.swipe_up_alt_rounded,
                'Swipe up opens',
                'What a swipe up from the home screen does',
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'drawer', label: Text('All apps')),
                    ButtonSegment(value: 'search', label: Text('Search')),
                  ],
                  selected: {s.swipeUp},
                  onSelectionChanged: (v) => set('swipeUp', v.first),
                ),
              ),
            ]),
            _Group('All apps', [
              _Switch(Icons.auto_awesome_outlined, 'Suggestions row', 'Apps you may want next, above the list', s.suggestions, (v) => set('suggestions', v)),
              _Block(
                Icons.sort_rounded,
                'Sort apps',
                'How the app list is ordered',
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'az', label: Text('A–Z')),
                    ButtonSegment(value: 'recent', label: Text('Recent')),
                    ButtonSegment(value: 'most', label: Text('Most used')),
                  ],
                  selected: {s.drawerSort},
                  onSelectionChanged: (v) => set('drawerSort', v.first),
                ),
              ),
              _Switch(Icons.keyboard_outlined, 'Keyboard on open', 'Start typing as soon as all apps opens', s.keyboardOnOpen, (v) => set('keyboardOnOpen', v)),
              _Switch(Icons.sort_by_alpha_rounded, 'Letter scroller', 'A–Z strip on the edge to jump around', s.letterScroller, (v) => set('letterScroller', v)),
            ]),
            _Group('More', [
              _Row(Icons.visibility_off_outlined, 'Hidden apps', 'Apps kept out of home and all apps', chevron: true, onTap: () async {
                final apps = await Apps.instance.list();
                if (context.mounted) await showHiddenApps(context, prefs: prefs, apps: apps);
              }),
              _Row(Icons.lock_person_outlined, 'App lock', 'Ask for a PIN to open chosen apps', chevron: true, onTap: () async {
                final apps = await Apps.instance.list();
                if (context.mounted) await showAppLockPage(context, prefs: prefs, apps: apps);
              }),
              _Row(Icons.wallpaper_rounded, 'Wallpaper & style', 'Change wallpaper, colours and themes', external: true, onTap: Apps.instance.openWallpaperPicker),
              _Row(Icons.restart_alt_rounded, 'Reset home layout', 'Clear pages, dock and folders; start fresh', onTap: () => _confirmReset(context)),
            ]),
            const SizedBox(height: DS.s24),
          ],
        );
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

// ---- Mini preview ----

class _Preview extends StatelessWidget {
  const _Preview(this.s);
  final PixelSettings s;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      height: 300,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: DS.cardMuted,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: DS.inkFaint.withValues(alpha: .5), width: 3),
      ),
      child: CustomPaint(painter: _PreviewPainter(s, DS.ink, DS.hero)),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.s, this.ink, this.accent);
  final PixelSettings s;
  final Color ink, accent;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Paint()..color = ink.withValues(alpha: .25);
    final icon = Paint()..color = accent;
    var top = 0.0;
    if (s.glance) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width * .5, 9), const Radius.circular(4)), bar);
      top = 20;
    }
    final dockH = 34.0 + (s.searchBar ? 22 : 0);
    final gridH = size.height - top - dockH - 16;
    final cols = s.cols, rows = s.rows;
    final cellW = size.width / cols, cellH = gridH / rows;
    final labelH = s.labels ? 5.0 : 0.0;
    final side = ((cellW < cellH - labelH - 2 ? cellW : cellH - labelH - 2) * .78 * s.iconScale).clamp(4.0, cellW);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        _icon(canvas, icon, bar, Offset(c * cellW + (cellW - side) / 2, top + r * cellH + (cellH - side - labelH) / 2), side, s.labels);
      }
    }
    // dock
    final n = s.dockCount;
    final dside = ((size.width / n) * .72).clamp(4.0, 24.0);
    final dy = size.height - (s.searchBar ? 22 : 0) - dockH + 34 - dside - 2;
    for (var i = 0; i < n; i++) {
      _icon(canvas, icon, bar, Offset(i * size.width / n + (size.width / n - dside) / 2, dy), dside, false);
    }
    if (s.searchBar) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, size.height - 16, size.width, 16), const Radius.circular(8)), bar);
    }
  }

  void _icon(Canvas canvas, Paint fill, Paint bar, Offset at, double side, bool label) {
    final path = PixelShape.pathFor(s.iconShape, Size.square(side)).shift(at);
    canvas.drawPath(path, fill);
    if (label) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(at.dx + side * .15, at.dy + side + 2, side * .7, 3), const Radius.circular(2)),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter o) => o.s.toJson().toString() != s.toJson().toString() || o.ink != ink || o.accent != accent;
}

// ---- Rows (look copied from sheets.dart's private rows) ----

class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.s16, DS.s24, DS.s16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(DS.s8, 0, DS.s8, DS.s8),
            child: Text(title, style: DS.rowTitle.copyWith(color: DS.hero, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(DS.rMedia),
            child: Material(
              color: DS.cardMuted,
              child: Column(children: [
                for (final (i, r) in rows.indexed) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, indent: 72, endIndent: DS.s16, color: DS.hairline),
                  r,
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(color: DS.hero, borderRadius: BorderRadius.circular(12)),
    child: Icon(icon, size: 21, color: DS.heroInk),
  );
}

Widget _texts(String title, String sub) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(title, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
    const SizedBox(height: 2),
    Text(sub, style: DS.rowSub.copyWith(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
  ],
);

/// Title + subtitle with something on the right (switch, stepper, chevron).
class _Row extends StatelessWidget {
  const _Row(this.icon, this.title, this.sub, {this.trailing, this.onTap, this.chevron = false, this.external = false});
  final IconData icon;
  final String title, sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron, external;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(DS.s16, DS.s12, DS.s12, DS.s12),
        child: Row(children: [
          _Disc(icon),
          const SizedBox(width: DS.s16),
          Expanded(child: _texts(title, sub)),
          if (trailing != null) ...[const SizedBox(width: DS.s8), trailing!],
          if (chevron || external) ...[
            const SizedBox(width: DS.s8),
            Icon(external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded, size: external ? 18 : 22, color: DS.inkFaint),
          ],
        ]),
      ),
    ),
  );
}

class _Switch extends StatelessWidget {
  const _Switch(this.icon, this.title, this.sub, this.value, this.onChanged);
  final IconData icon;
  final String title, sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _Row(
    icon,
    title,
    sub,
    onTap: () => onChanged(!value),
    trailing: Switch(value: value, onChanged: onChanged),
  );
}

/// A row whose control sits under the text (slider, chips, segmented buttons).
class _Block extends StatelessWidget {
  const _Block(this.icon, this.title, this.sub, this.control);
  final IconData icon;
  final String title, sub;
  final Widget control;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(DS.s16, DS.s12, DS.s16, DS.s12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [_Disc(icon), const SizedBox(width: DS.s16), Expanded(child: _texts(title, sub))]),
      const SizedBox(height: DS.s8),
      Padding(padding: const EdgeInsets.only(left: 56), child: Align(alignment: Alignment.centerLeft, child: control)),
    ]),
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper(this.value, this.min, this.max, this.onChanged);
  final int value, min, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    IconButton(
      tooltip: 'Fewer',
      icon: const Icon(Icons.remove_circle_outline_rounded),
      onPressed: value > min ? () => onChanged(value - 1) : null,
    ),
    SizedBox(width: 20, child: Text('$value', textAlign: TextAlign.center, style: DS.rowTitle)),
    IconButton(
      tooltip: 'More',
      icon: const Icon(Icons.add_circle_outline_rounded),
      onPressed: value < max ? () => onChanged(value + 1) : null,
    ),
  ]);
}

class _ShapeChoice extends StatelessWidget {
  const _ShapeChoice(this.shape, {required this.selected, required this.onTap});
  final String shape;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: shape,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? DS.hero.withValues(alpha: .18) : Colors.transparent,
          border: Border.all(color: selected ? DS.hero : DS.hairline, width: selected ? 2 : 1),
        ),
        child: Center(
          child: SizedBox.square(
            dimension: 30,
            child: ClipPath(clipper: PixelShape(shape), child: ColoredBox(color: selected ? DS.hero : DS.inkFaint)),
          ),
        ),
      ),
    ),
  );
}
