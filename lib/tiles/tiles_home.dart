import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../ui/components.dart';
import '../search_dock.dart' show SearchDock;
import '../search.dart';
import '../app_drawer.dart' show searchResults;
import '../quick_actions.dart';
import '../quick_chips.dart' show ShortcutIcon;
import '../photo_wallpaper.dart';
import '../prefs.dart';
import '../remote_sheet.dart';
import '../sheets.dart';
import '../top/header_fonts.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import '../ui/perf.dart';
import '../ui/theme.dart';
import '../widgets.dart';
import 'landing.dart';

/// The "Tiles" home view (Settings → Look → Home view): a Start screen of live tiles, and — one
/// swipe to the left — every app A–Z. The layout and navigation follow the Lumia launcher; the
/// colours are the theme's (Material).
class TilesHome extends StatefulWidget {
  const TilesHome({super.key, required this.prefs, required this.theme, this.preview = false});
  final Prefs prefs;
  final OneTheme theme;

  /// A live miniature for the Home screen editor (doesn't take the home button, Back or app
  /// changes from the real home screen).
  final bool preview;

  @override
  State<TilesHome> createState() => _TilesHomeState();
}

/// One tile on Start: an app or a live tile ('clock'), small 1×1 / medium 2×2 / wide 4×2.
class TileSpec {
  const TileSpec(this.id, this.size, [this.colour, this.name, this.items = const []]);
  final String id, size;

  /// Folders: their name and apps (packages); the open folder's panel carries the same apps.
  final String? name;
  final List<String> items;
  bool get isFolder => id.startsWith('folder:');
  bool get isPanel => id.startsWith('panel:');

  /// Its own colour: null = the Start default, 'accent', 'app' (the icon's colour) or an ARGB hex.
  final String? colour;

  bool get isApp => id.startsWith('app:');
  String get package => id.substring(4);

  /// A quick action ('qa:' + a built-in "b:…" or app shortcut `s:<package>|<id>|<profile>`).
  bool get isAction => id.startsWith('qa:');
  String get action => id.substring(3);

  /// Whose icon colour "app colour" uses: the app, or the app behind a shortcut.
  String? get colourPackage => isApp ? package : (isAction && action.startsWith('s:') ? action.substring(2).split('|').first : null);
  (int, int) get span => switch (size) {
    's' => (1, 1),
    'w' => (4, 2),
    'l' => (4, 4),
    _ => (2, 2),
  };

  /// The quick-actions row: one group across the whole width.
  bool get isChips => id == 'chips';

  /// Its cells on a [cols]-column grid (the chips row is always full width, one row high).
  (int, int) spanIn(int cols) => isChips ? (cols, 1) : (isPanel ? (cols, math.max(1, (items.length / cols).ceil())) : span);

  Map<String, dynamic> toJson() => {'id': id, 'size': size, 'colour': ?colour, 'name': ?name, if (items.isNotEmpty) 'items': items};
  static TileSpec fromJson(Map<String, dynamic> m) => TileSpec(m['id'] as String, m['size'] as String? ?? 'm', m['colour'] as String?, m['name'] as String?, [
    for (final x in m['items'] as List? ?? const []) x as String,
  ]);
  TileSpec resized(String s) => TileSpec(id, s, colour, name, items);
  TileSpec recoloured(String? c) => TileSpec(id, size, c, name, items);
  TileSpec withItems(List<String> list) => TileSpec(id, size, colour, name, list);
  TileSpec renamed(String n) => TileSpec(id, size, colour, n, items);
}

/// Colours a tile can take (edit mode → palette), besides the accent and the app's own.
const tileSwatches = <Color>[
  Color(0xFF1565C0), Color(0xFF0097A7), Color(0xFF2E7D32), Color(0xFF689F38), Color(0xFFF9A825), Color(0xFFEF6C00), //
  Color(0xFFD84315), Color(0xFFC62828), Color(0xFFAD1457), Color(0xFF6A1B9A), Color(0xFF4527A0), Color(0xFF37474F),
];

/// A tile's colour (with the Start screen's transparency): its own, else the Start default.
Future<Color> tileColour(TileSpec t, Prefs prefs) async {
  final mode = t.colour ?? (prefs.tileColours == 'colourful' ? 'app' : 'accent');
  final Color c = switch (mode) {
    'accent' => tileAccent(),
    'app' => t.colourPackage != null ? await iconColour(t.colourPackage!) : tileAccent(),
    _ => Color(int.tryParse(mode, radix: 16) ?? tileAccent().toARGB32()),
  };
  // Wallpaper through tiles: the colour is only a light tint over the wallpaper.
  return c.withValues(alpha: prefs.fx('window') ? math.min(prefs.tileOpacity, .22) : prefs.tileOpacity);
}

/// Places tiles on a 4-column grid in order, each at the first free spot it fits — small tiles
/// fill the gaps next to bigger ones, like the Lumia Start screen. → (tile, column, row).
List<(TileSpec, int, int)> packTiles(List<TileSpec> tiles, {int cols = 4}) {
  final used = <(int, int)>{};
  final out = <(TileSpec, int, int)>[];
  for (final t in tiles) {
    final (w, h) = t.spanIn(cols);
    var placed = false;
    for (var row = 0; !placed; row++) {
      for (var col = 0; col + w <= cols && !placed; col++) {
        var free = true;
        for (var x = col; x < col + w && free; x++) {
          for (var y = row; y < row + h && free; y++) {
            if (used.contains((x, y))) free = false;
          }
        }
        if (!free) continue;
        for (var x = col; x < col + w; x++) {
          for (var y = row; y < row + h; y++) {
            used.add((x, y));
          }
        }
        out.add((t, col, row));
        placed = true;
      }
    }
  }
  return out;
}

/// The tiles' accent: the theme's accent made deep and saturated enough to carry white glyphs.
Color tileAccent() {
  final h = HSLColor.fromColor(DS.hero);
  return h.withSaturation(math.max(h.saturation, .5)).withLightness(.38).toColor();
}

/// Ping to bring Start into view (top, not editing) — Settings → Home view previews on it.
final showTilesStart = _Signal();

class _Signal extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _TilesHomeState extends State<TilesHome> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Prefs get prefs => widget.prefs;
  final _pages = PageController();
  final _start = ScrollController();
  List<AppEntry> _apps = const [];
  bool _editing = false;
  final _searchFocus = FocusNode();
  final _searchText = TextEditingController();

  /// Search: 0 = closed … 1 = the bar is down from the top (results show once you type).
  late final _search = AnimationController(vsync: this, duration: Motion.snapDuration);
  bool get _searching => _search.status == AnimationStatus.forward || _search.status == AnimationStatus.completed;
  double _pull = 0; // pull-down on Start past the top, in px
  String? _selected; // the tile showing its edit controls

  @override
  void initState() {
    super.initState();
    prefs.addListener(_rebuild);
    if (!widget.preview) {
      WidgetsBinding.instance.addObserver(this);
      showTilesStart.addListener(_showStart);
      Apps.instance.onAppsChanged = _load;
      Apps.instance.onHomePressed = _home;
      startLanding.play();
    }
    _load();
  }

  /// Plays the landing animation of whichever page shows.
  void _land() => ((_pages.hasClients && (_pages.page ?? 0) > .5) ? listLanding : startLanding).play();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    prefs.removeListener(_rebuild);
    showTilesStart.removeListener(_showStart);
    _pages.dispose();
    _searchFocus.dispose();
    _searchText.dispose();
    _search.dispose();
    _start.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _land(); // back on home: the tiles / rows come in again
      _load();
      widget.theme.refreshSystem();
    }
  }

  void _rebuild() {
    // "Reset Start" in Settings clears the tiles: lay the starting ones out again right away.
    if (prefs.tiles == null && _apps.isNotEmpty) {
      prefs.setTiles([for (final t in _defaults()) t.toJson()]);
      return;
    }
    setState(() {});
  }

  Future<void> _load() async {
    final apps = await Apps.instance.list();
    if (!mounted) return;
    setState(() => _apps = apps);
    Apps.instance.refreshNotifCounts();
    if (prefs.tiles == null && apps.isNotEmpty) await prefs.setTiles([for (final t in _defaults()) t.toJson()]);
  }

  /// First time on Tiles: a clock, then pinned + most-used apps in a mix of sizes.
  List<TileSpec> _defaults() {
    final byPkg = {for (final a in _apps) a.package: a};
    final picks = <String>[
      for (final p in prefs.favourites)
        if (byPkg.containsKey(p)) p,
    ];
    final used = prefs.launchCounts.entries.where((e) => byPkg.containsKey(e.key)).toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in used) {
      if (!picks.contains(e.key)) picks.add(e.key);
    }
    for (final a in _apps) {
      if (picks.length >= 10) break;
      if (!picks.contains(a.package)) picks.add(a.package);
    }
    const sizes = ['m', 's', 's', 's', 's', 'm', 's', 's', 's', 's'];
    return [const TileSpec('clock', 'w'), const TileSpec('chips', 'm'), for (final (i, p) in picks.take(10).indexed) TileSpec('app:$p', sizes[i])];
  }

  List<TileSpec> get _tiles {
    final known = {for (final a in _apps) a.package};
    return [
      for (final m in prefs.tiles ?? const <Map<String, dynamic>>[])
        if (TileSpec.fromJson(m) case final t when !t.isApp || known.contains(t.package)) t,
    ];
  }

  Future<void> _save(List<TileSpec> tiles) => prefs.setTiles([for (final t in tiles) t.toJson()]);

  bool isPinned(String package) => _tiles.any((t) => (t.isApp && t.package == package) || (t.isFolder && t.items.contains(package)));

  String? _openFolder; // the folder open inline on Start
  final _gridKey = GlobalKey();

  /// Dropped onto the middle of a tile (Folders on Start): onto an app → a new folder of the
  /// two, onto a folder → into it.
  Future<void> _toFolder(String dragged, String target) async {
    final list = [..._tiles];
    final di = list.indexWhere((t) => t.id == dragged), ti = list.indexWhere((t) => t.id == target);
    if (di < 0 || ti < 0 || !list[di].isApp) return;
    final d = list[di], t = list[ti];
    if (t.isFolder) {
      list[ti] = t.withItems([...t.items, d.package]);
    } else if (t.isApp) {
      list[ti] = TileSpec('folder:${DateTime.now().millisecondsSinceEpoch}', t.size == 's' ? 'm' : t.size, t.colour, 'Folder', [t.package, d.package]);
    } else {
      return;
    }
    list.removeAt(di);
    HapticFeedback.heavyImpact();
    setState(() => _selected = list.firstWhere((x) => x.isFolder && x.items.contains(d.package)).id);
    await _save(list);
  }

  /// Out of a folder: the app goes back on Start right after it; a folder left with one app
  /// turns back into that app's tile.
  Future<void> _outOfFolder(String folderId, String package) async {
    final list = [..._tiles];
    final fi = list.indexWhere((t) => t.id == folderId);
    if (fi < 0) return;
    final f = list[fi];
    final rest = f.items.where((x) => x != package).toList();
    if (rest.length <= 1) {
      list[fi] = TileSpec('app:${rest.isEmpty ? package : rest.first}', f.size, f.colour);
      if (rest.isNotEmpty) list.insert(fi + 1, TileSpec('app:$package', 's'));
      if (_openFolder == folderId) _openFolder = null;
    } else {
      list[fi] = f.withItems(rest);
      list.insert(fi + 1, TileSpec('app:$package', 's'));
    }
    HapticFeedback.selectionClick();
    await _save(list);
  }

  Future<void> _renameFolder(TileSpec f) async {
    final text = TextEditingController(text: f.name ?? 'Folder');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Folder name'),
        content: TextField(controller: text, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, text.text), child: const Text('Save')),
        ],
      ),
    );
    text.dispose();
    if (name == null || name.trim().isEmpty) return;
    await _save([for (final t in _tiles) t.id == f.id ? t.renamed(name.trim()) : t]);
  }

  /// Ungroup: the folder's apps become small tiles where it was.
  Future<void> _ungroup(TileSpec f) async {
    final list = <TileSpec>[];
    for (final t in _tiles) {
      if (t.id == f.id) {
        list.addAll([for (final p in f.items) TileSpec('app:$p', 's')]);
      } else {
        list.add(t);
      }
    }
    if (_openFolder == f.id) _openFolder = null;
    if (_selected == f.id) _selected = null;
    await _save(list);
  }

  void _folderMenu(TileSpec f) => showOneSheet(
    context,
    header: SheetHeader(title: f.name ?? 'Folder', subtitle: '${f.items.length} apps'),
    actions: [
      SheetAction(Icons.edit_outlined, 'Rename', () {
        Navigator.pop(context);
        _renameFolder(f);
      }),
      SheetAction(Icons.folder_off_outlined, 'Ungroup', () {
        Navigator.pop(context);
        _ungroup(f);
      }),
    ],
  );

  Future<void> _pin(AppEntry a) async {
    HapticFeedback.mediumImpact();
    await _save([..._tiles, TileSpec('app:${a.package}', 'm')]);
  }

  Future<void> _unpin(String id) async {
    HapticFeedback.selectionClick();
    await _save([
      for (final t in _tiles)
        if (t.id != id) t,
    ]);
    if (_selected == id) _selected = null;
  }

  Future<void> _resize(TileSpec t) async {
    HapticFeedback.selectionClick();
    // small → medium → wide → large → small (the clock has no small).
    final next = switch (t.size) {
      's' => 'm',
      'm' => 'w',
      'w' => 'l',
      _ => t.id == 'clock' ? 'm' : 's',
    };
    await _save([for (final x in _tiles) x.id == t.id ? x.resized(next) : x]);
  }

  Future<void> _recolour(TileSpec t) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DS.card,
      showDragHandle: true,
      builder: (ctx) => _Palette(current: t.colour, app: t.colourPackage),
    );
    if (picked == null) return;
    await _save([for (final x in _tiles) x.id == t.id ? x.recoloured(picked == 'default' ? null : picked) : x]);
  }

  /// Puts [dragged] where [target] is (moving forward lands after it, back before it); '' = the end.
  Future<void> _move(String dragged, String target) async {
    final list = [..._tiles];
    final from = list.indexWhere((t) => t.id == dragged);
    final to = target.isEmpty ? list.length - 1 : list.indexWhere((t) => t.id == target);
    if (from < 0 || to < 0 || from == to) return;
    list.insert(to, list.removeAt(from));
    HapticFeedback.selectionClick();
    await _save(list);
  }

  void _launch(AppEntry a) {
    prefs.recordLaunch(a.package);
    Apps.instance.launch(a.package);
  }

  /// From a Start tile: with Interactions → Turnstile, Start swings away first (the tapped
  /// tile last), then the app opens; coming back plays the landing.
  Future<void> _launchFromStart(AppEntry a) async {
    if (!prefs.fx('turnstile') || Perf.lite.value) return _launch(a);
    startLanding.exit(last: 'app:${a.package}');
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    _launch(a);
    // If nothing opened (we're still in front), bring Start back.
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed && startLanding.exiting) startLanding.play();
    });
  }

  void _home() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() {
      _editing = false;
      _selected = null;
    });
    if (_pages.hasClients) _pages.animateToPage(0, duration: Motion.snapDuration, curve: Motion.settle);
    if (_start.hasClients) _start.animateTo(0, duration: Motion.snapDuration, curve: Motion.settle);
  }

  /// Pull down on Start (Settings → pull to search): all apps with the search box focused.
  bool _onStartScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || _editing || !prefs.pullToSearch) return false;
    if (n is OverscrollNotification && n.overscroll < 0 && n.dragDetails != null) {
      final was = _pull;
      _pull -= n.overscroll;
      if (was < _pullAt && _pull >= _pullAt) HapticFeedback.selectionClick(); // far enough
    } else if (n is ScrollEndNotification || (n is ScrollUpdateNotification && n.metrics.pixels > 0)) {
      if (_pull >= _pullAt) _openSearch();
      _pull = 0;
    }
    return false;
  }

  static const _pullAt = 72.0;

  /// The search bar slides down from the top over whichever page shows.
  void _openSearch() {
    if (_searching) return;
    HapticFeedback.selectionClick();
    _searchText.clear();
    _search.forward();
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    if (!_searching) return;
    _searchFocus.unfocus();
    _search.reverse().whenComplete(_searchText.clear);
  }

  void _showStart() {
    setState(() {
      _editing = false;
      _selected = null;
    });
    if (_pages.hasClients) _pages.animateToPage(0, duration: Motion.snapDuration, curve: Motion.settle);
    if (_start.hasClients) _start.animateTo(0, duration: Motion.snapDuration, curve: Motion.settle);
  }

  /// Double-tap empty space (Interactions → Double-tap to lock): screen off. The first time,
  /// explain and open Accessibility settings, where Android lets the user allow it.
  Future<void> _lock() async {
    if (await Apps.instance.lockScreen() || !mounted) return;
    HapticFeedback.mediumImpact();
    showOneSheet(
      context,
      header: const SheetHeader(
        title: 'Double-tap to lock',
        subtitle: 'Android needs you to allow “One Launcher · double-tap to lock” in Accessibility settings. It only turns the screen off — it reads nothing on screen.',
      ),
      actions: [
        SheetAction(Icons.accessibility_new_rounded, 'Open Accessibility settings', () {
          Navigator.pop(context);
          Apps.instance.openAccessibility();
        }),
        SheetAction(Icons.toggle_off_outlined, 'Turn double-tap to lock off', () {
          Navigator.pop(context);
          prefs.setFx('lock', false);
        }),
      ],
    );
  }

  void _settings() {
    HapticFeedback.mediumImpact();
    showSettingsSheet(context, prefs: prefs, apps: _apps, theme: widget.theme);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.preview,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_searching) return _closeSearch();
        if (_editing) {
          return setState(() {
            _editing = false;
            _selected = null;
          });
        }
        if (_pages.hasClients && (_pages.page ?? 0) > .5) _pages.animateToPage(0, duration: Motion.snapDuration, curve: Motion.settle);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        // Glass tiles blur the wallpaper behind them; grouped, they share one backdrop pass.
        body: BackdropGroup(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Start shows the whole screen. Wallpaper through tiles: it drifts slower than the tiles
              // as Start scrolls (parallax) — zoomed a little so it has room to move.
              IgnorePointer(
                child: prefs.fx('window')
                    ? AnimatedBuilder(
                        animation: _start,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(0, (-(_start.hasClients ? _start.offset : 0) * .15).clamp(-MediaQuery.sizeOf(context).height * .2, 0)),
                          child: child,
                        ),
                        child: Transform.scale(
                          scale: 1.25,
                          alignment: Alignment.topCenter,
                          child: PhotoWallpaper(prefs: prefs, fullScreen: true),
                        ),
                      )
                    : PhotoWallpaper(prefs: prefs, fullScreen: true),
              ),
              // Tiles want calm behind them: the wallpaper dims more than on the classic view (less
              // when it only shows through the tiles).
              IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: (prefs.wallpaperDim + (prefs.fx('window') ? 0 : .35)).clamp(0.0, .85))),
              ),
              // Search doesn't cover the page: the page itself steps back (fades, sinks a
              // little) as the search pill comes down and the results take its place.
              AnimatedBuilder(
                animation: _search,
                builder: (context, page) {
                  final t = Curves.easeOutCubic.transform(_search.value);
                  return IgnorePointer(
                    ignoring: t > 0,
                    child: Opacity(
                      opacity: (1 - t * 1.4).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 40 * t),
                        child: Transform.scale(scale: 1 - .06 * t, child: page),
                      ),
                    ),
                  );
                },
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) {
                    _closeSearch(); // going between Start and all apps ends a search
                    (i == 0 ? startLanding : listLanding).play();
                  },
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: _onStartScroll,
                      child: _StartPage(
                        tiles: _tiles,
                        apps: {for (final a in _apps) a.package: a},
                        scroll: _start,
                        editing: _editing,
                        selected: _selected,
                        prefs: prefs,
                        onLaunch: _launchFromStart,
                        onOpenClock: () {
                          final clock = _apps.where((a) => a.label.toLowerCase() == 'clock').firstOrNull;
                          if (clock != null) _launch(clock);
                        },
                        openFolder: _openFolder,
                        gridKey: _gridKey,
                        onFolder: _toFolder,
                        onOutOfFolder: _outOfFolder,
                        onFolderMenu: _folderMenu,
                        onToggleFolder: (id) => setState(() => _openFolder = _openFolder == id ? null : id),
                        onEdit: (id) => setState(() {
                          if (!_editing) HapticFeedback.mediumImpact();
                          _openFolder = null; // editing works on closed folders
                          _editing = true;
                          _selected = id;
                        }),
                        onDone: () => setState(() {
                          _editing = false;
                          _selected = null;
                        }),
                        onUnpin: _unpin,
                        onResize: _resize,
                        onRecolour: _recolour,
                        onMove: _move,
                        onAllApps: () => _pages.animateToPage(1, duration: Motion.snapDuration, curve: Motion.settle),
                        onSettings: _settings,
                        onDoubleTap: _lock,
                      ),
                    ),
                    NotificationListener<ScrollNotification>(
                      onNotification: _onStartScroll, // pull down on the list: search too
                      // Wallpaper through tiles: the app list sits on black, like Start around the tiles.
                      child: ColoredBox(
                        color: prefs.fx('window') ? Colors.black : Colors.transparent,
                        child: _AppListPage(
                          onSearch: _openSearch,
                          apps: _apps,
                          prefs: prefs,
                          isPinned: isPinned,
                          onLaunch: _launch,
                          onPin: _pin,
                          onUnpin: (a) => _unpin('app:${a.package}'),
                          onSettings: _settings,
                          onRemote: prefs.remoteButton ? () => showTvRemote(context, prefs: prefs) : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _TileSearch(
                anim: _search,
                text: _searchText,
                focus: _searchFocus,
                apps: _apps,
                prefs: prefs,
                onClose: _closeSearch,
                onLaunch: (a) {
                  _closeSearch();
                  _launch(a);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Start ----------------------------------------------------------------------------------

/// Start's rows: tiles' rows are a tile unit tall; the quick-actions row is shorter (its chips
/// are smaller than app tiles). Tops and heights in grid pixels.
class _Rows {
  _Rows(List<(TileSpec, int, int)> placed, this.unit)
    : short = {
        for (final (t, _, r) in placed)
          if (t.isChips) r,
      },
      chip = math.max(44, unit * .55);
  final double unit, chip;
  final Set<int> short;
  static const gap = _StartPage.gap;

  double h(int r) => short.contains(r) ? chip : unit;
  double top(int r) {
    var y = 0.0;
    for (var i = 0; i < r; i++) {
      y += h(i) + gap;
    }
    return y;
  }

  double span(int r, int n) => top(r + n) - top(r) - gap;

  /// The row at [dy] (past the last row keeps counting in tile units).
  int at(double dy) {
    var y = 0.0;
    for (var r = 0; r < 4000; r++) {
      y += h(r) + gap;
      if (dy < y) return r;
    }
    return 4000;
  }
}

class _StartPage extends StatelessWidget {
  const _StartPage({
    required this.tiles,
    required this.apps,
    required this.scroll,
    required this.editing,
    required this.selected,
    required this.prefs,
    required this.onLaunch,
    required this.onOpenClock,
    required this.onEdit,
    required this.onDone,
    required this.onUnpin,
    required this.onResize,
    required this.onRecolour,
    required this.onMove,
    required this.onAllApps,
    required this.onSettings,
    required this.onDoubleTap,
    required this.openFolder,
    required this.gridKey,
    required this.onFolder,
    required this.onOutOfFolder,
    required this.onFolderMenu,
    required this.onToggleFolder,
  });

  final String? openFolder;
  final Future<void> Function(String dragged, String target) onFolder;
  final Future<void> Function(String folder, String package) onOutOfFolder;
  final ValueChanged<TileSpec> onFolderMenu;
  final ValueChanged<String> onToggleFolder;
  final List<TileSpec> tiles;
  final Map<String, AppEntry> apps;
  final ScrollController scroll;
  final bool editing;
  final Prefs prefs;
  final String? selected;
  final ValueChanged<AppEntry> onLaunch;
  final VoidCallback onOpenClock, onDone, onAllApps, onSettings, onDoubleTap;
  final ValueChanged<String> onEdit, onUnpin;
  final ValueChanged<TileSpec> onResize, onRecolour;
  final Future<void> Function(String dragged, String target) onMove;

  static const gap = 6.0, side = 12.0;
  final GlobalKey gridKey; // the grid's box (each Start has its own: the editor shows a second)
  static String? _mergePending;
  static Timer? _mergeTimer;

  /// While a tile is dragged: the cell under its centre decides where it goes — onto a tile
  /// takes that tile's place (the rest reflow), empty space after the last tile = the end.
  void _hover(DragTargetDetails<String> d, List<(TileSpec, int, int)> placed, double unit, int cols, _Rows rows) {
    final box = gridKey.currentContext?.findRenderObject() as RenderBox?;
    final dragged = placed.where((p) => p.$1.id == d.data).firstOrNull;
    if (box == null || dragged == null) return;
    final (w, h) = (dragged.$1.spanIn(cols).$1 * (unit + gap), rows.span(dragged.$3, dragged.$1.spanIn(cols).$2) + gap);
    final p = box.globalToLocal(d.offset + Offset(w / 2, h / 2));
    if (p.dy < 0 || p.dx < 0) return;
    final col = (p.dx / (unit + gap)).floor().clamp(0, cols - 1), row = rows.at(p.dy);
    String? target;
    for (final (t, c, r) in placed) {
      final (sw, sh) = t.spanIn(cols);
      if (col >= c && col < c + sw && row >= r && row < r + sh) target = t.id;
    }
    if (target == null) {
      final (last, lc, lr) = placed.last;
      final pastEnd = row >= lr + last.spanIn(cols).$2 || (row >= lr && col >= lc + last.spanIn(cols).$1);
      if (!pastEnd || last.id == d.data) return;
      target = '';
    }
    if (target == d.data) return;
    // Folders: the dragged app's centre over the middle of an app or folder → make / join a
    // folder (no reflow while it's there).
    final over = placed.where((x) => x.$1.id == target).firstOrNull;
    if (prefs.fx('folders') && dragged.$1.isApp && over != null && (over.$1.isApp || over.$1.isFolder)) {
      final (sw, sh) = over.$1.spanIn(cols);
      final r = Rect.fromLTWH(over.$2 * (unit + gap), rows.top(over.$3), sw * unit + (sw - 1) * gap, rows.span(over.$3, sh));
      if (r.deflate(math.min(r.width, r.height) * .25).contains(p)) {
        _pending = null;
        _pendingTimer?.cancel();
        // Held there a moment → it will become a folder (the outline shows it).
        if (_mergePending != target) {
          _mergePending = target;
          _mergeTimer?.cancel();
          final t0 = target;
          _mergeTimer = Timer(const Duration(milliseconds: 300), () {
            if (_mergePending == t0) mergeTarget.value = t0;
          });
        }
        return;
      }
    }
    _mergePending = null;
    _mergeTimer?.cancel();
    mergeTarget.value = null;
    // Make room only once the finger rests on the tile's edge a moment (as on Lumia) — passing
    // over it on the way to its middle (a folder) or elsewhere moves nothing.
    if (_pending == target) return;
    _pending = target;
    _pendingTimer?.cancel();
    final dragged0 = d.data, target0 = target;
    _pendingTimer = Timer(const Duration(milliseconds: 260), () {
      if (_pending != target0 || mergeTarget.value != null) return;
      _pending = null;
      onMove(dragged0, target0);
    });
  }

  static String? _pending;
  static Timer? _pendingTimer;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final cols = prefs.tileColumns;
        final unit = (c.maxWidth - 2 * side - (cols - 1) * gap) / cols;
        final shown = [
          for (final t in tiles) ...[
            t,
            if (t.isFolder && t.id == openFolder)
              TileSpec('panel:${t.id}', 'm', t.colour, t.name, [
                for (final p in t.items)
                  if (apps.containsKey(p)) p,
              ]),
          ],
        ];
        final placed = packTiles(shown, cols: cols);
        final rows = placed.fold<int>(0, (m, p) => math.max(m, p.$3 + p.$1.spanIn(cols).$2));
        final grid = _Rows(placed, unit);
        final height = rows == 0 ? 0.0 : grid.span(0, rows);
        final start = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: editing ? onDone : null,
          onLongPress: editing ? null : onSettings, // long-press empty space: settings, like the classic view
          child: SingleChildScrollView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(), // pull down to search even when Start fits
            padding: EdgeInsets.fromLTRB(side, pad.top + DS.s24, side, pad.bottom + DS.s24),
            child: _EmptySpace(
              minHeight: c.maxHeight - pad.top - pad.bottom - 2 * DS.s24,
              onDoubleTap: prefs.fx('lock') ? onDoubleTap : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DragTarget<String>(
                    onWillAcceptWithDetails: (_) => true,
                    onMove: (d) => _hover(d, placed, unit, cols, grid),
                    onLeave: (_) {
                      _mergePending = null;
                      _mergeTimer?.cancel();
                      mergeTarget.value = null;
                      _pending = null;
                      _pendingTimer?.cancel();
                    },
                    onAcceptWithDetails: (d) {
                      _pending = null;
                      _pendingTimer?.cancel();
                      _mergePending = null;
                      _mergeTimer?.cancel();
                      final m = mergeTarget.value;
                      mergeTarget.value = null;
                      if (m != null) onFolder(d.data, m);
                    },
                    builder: (context, _, _) => SizedBox(
                      key: gridKey,
                      height: height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final (t, col, row) in placed)
                            AnimatedPositioned(
                              key: ValueKey(t.id),
                              duration: Motion.snapDuration,
                              curve: Motion.settle,
                              left: col * (unit + gap),
                              top: grid.top(row),
                              width: t.spanIn(cols).$1 * unit + (t.spanIn(cols).$1 - 1) * gap,
                              height: grid.span(row, t.spanIn(cols).$2),
                              child: t.isPanel
                                  ? Landed(
                                      landing: startLanding,
                                      style: 'cascade',
                                      reveal: true, // opens with a little drop-in
                                      delay: Duration.zero,
                                      child: _FolderPanel(
                                        panel: t,
                                        apps: apps,
                                        unit: unit,
                                        prefs: prefs,
                                        onLaunch: onLaunch,
                                        onOut: (p) => onOutOfFolder(t.id.substring(6), p),
                                      ),
                                    )
                                  : Landed(
                                      landing: startLanding,
                                      style: prefs.tileAnim,
                                      // Lumia's sweep: column by column, a little later each row.
                                      delay: Duration(milliseconds: 40 * col + 22 * row),
                                      id: t.id,
                                      // Long Start: tiles below the fold come in as you scroll to them.
                                      scroll: scroll,
                                      top: pad.top + DS.s24 + grid.top(row),
                                      bottom: pad.top + DS.s24 + grid.top(row + t.spanIn(cols).$2),
                                      child: _EditableTile(
                                        prefs: prefs,
                                        tile: t,
                                        editing: editing,
                                        selected: selected == t.id,
                                        onEdit: () => onEdit(t.id),
                                        onUnpin: () => onUnpin(t.id),
                                        onResize: () => onResize(t),
                                        onRecolour: () => onRecolour(t),
                                        onMore: t.isApp ? () => showTileMenu(context, prefs, apps[t.package]!) : (t.isFolder ? () => onFolderMenu(t) : null),
                                        child: t.isFolder
                                            ? _FolderTile(
                                                tile: t,
                                                apps: apps,
                                                prefs: prefs,
                                                open: openFolder == t.id,
                                                onTap: editing ? () => onEdit(t.id) : () => onToggleFolder(t.id),
                                              )
                                            : t.isApp
                                            ? _AppTile(
                                                app: apps[t.package]!,
                                                tile: t,
                                                prefs: prefs,
                                                onTap: editing ? () => onEdit(t.id) : () => onLaunch(apps[t.package]!),
                                              )
                                            : t.isChips
                                            // No box around the group: each chip is a tile of its own. In edit
                                            // mode a tap selects the group (long-press anywhere on it moves it).
                                            ? GestureDetector(
                                                behavior: HitTestBehavior.opaque,
                                                onTap: editing ? () => onEdit(t.id) : null,
                                                child: IgnorePointer(
                                                  ignoring: editing,
                                                  child: _ChipsRowTile(tile: t, prefs: prefs),
                                                ),
                                              )
                                            : t.isAction
                                            ? _ActionTile(tile: t, prefs: prefs, onTap: editing ? () => onEdit(t.id) : null)
                                            : _ClockTile(tile: t, prefs: prefs, onTap: editing ? () => onEdit(t.id) : onOpenClock),
                                      ),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: DS.s16),
                  Row(
                    children: [
                      if (editing) ...[
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: tileAccent(), foregroundColor: Colors.white, shape: const StadiumBorder()),
                          onPressed: onDone,
                          child: const Text('Done'),
                        ),
                        const SizedBox(width: DS.s8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: DS.onWallpaper,
                            side: const BorderSide(color: DS.onWallpaper, width: 1.5),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => addActionTile(context, prefs),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add tile'),
                        ),
                      ],
                      const Spacer(),
                      // The Lumia arrow: all apps (or swipe left).
                      Tooltip(
                        message: 'All apps',
                        child: Pressable(
                          scale: .9,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onAllApps,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: DS.onWallpaper, width: 2),
                              ),
                              child: const Icon(Icons.arrow_forward_rounded, color: DS.onWallpaper),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        if (!prefs.fx('window')) return start;
        // Wallpaper through tiles: black everywhere except the tiles, which become windows onto
        // the wallpaper (holes follow the scroll).
        final holes = [
          for (final (t, col, row) in placed)
            Rect.fromLTWH(
              side + col * (unit + gap),
              pad.top + DS.s24 + grid.top(row),
              t.spanIn(cols).$1 * unit + (t.spanIn(cols).$1 - 1) * gap,
              grid.span(row, t.spanIn(cols).$2),
            ),
        ];
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: AnimatedBuilder(
                animation: scroll,
                builder: (context, _) => CustomPaint(painter: _Holes(holes, scroll.hasClients ? scroll.offset : 0, prefs.tileRadius)),
              ),
            ),
            start,
          ],
        );
      },
    );
  }
}

/// Edit mode around a tile: others shrink a little; the selected one shows unpin (top-right)
/// and resize (bottom-right); drag a tile onto another to put it there.
class _EditableTile extends StatelessWidget {
  const _EditableTile({
    required this.tile,
    required this.editing,
    required this.selected,
    required this.onEdit,
    required this.onUnpin,
    required this.onResize,
    required this.onRecolour,
    required this.prefs,
    required this.child,
    this.onMore,
  });

  final VoidCallback? onMore; // app tiles: ⋯ (shortcuts, info, uninstall)

  final Prefs prefs;
  final TileSpec tile;
  final bool editing, selected;
  final VoidCallback onEdit, onUnpin, onResize, onRecolour;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final body = ValueListenableBuilder<String?>(
      valueListenable: mergeTarget,
      child: AnimatedOpacity(duration: Motion.snapDuration, opacity: editing && !selected ? .75 : 1, child: child),
      // A tile about to take the dragged one into a folder grows and gets a white outline.
      builder: (context, merge, inner) => AnimatedScale(
        duration: Motion.snapDuration,
        curve: Motion.settle,
        scale: merge == tile.id ? 1.06 : (editing && !selected ? .9 : 1),
        child: Container(
          foregroundDecoration: merge == tile.id
              ? BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(prefs.tileRadius),
                )
              : null,
          child: inner,
        ),
      ),
    );
    // One tree in both modes: entering edit mode mid long-press must not rebuild the tile away
    // under the finger.
    // Long-press picks the tile up straight away (and enters edit mode); in edit mode a short
    // hold is enough. The grid reflows live under the finger (see _StartPage).
    return LayoutBuilder(
      builder: (context, box) => Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          LongPressDraggable<String>(
            data: tile.id,
            delay: editing ? const Duration(milliseconds: 150) : kLongPressTimeout,
            feedback: SizedBox(
              width: box.maxWidth,
              height: box.maxHeight,
              child: Opacity(opacity: .85, child: child),
            ),
            childWhenDragging: Opacity(opacity: .3, child: body),
            onDragStarted: () {
              HapticFeedback.mediumImpact();
              if (!editing) onEdit();
            },
            onDragEnd: (_) => mergeTarget.value = null,
            child: body,
          ),
          if (editing && selected) ...[
            Positioned(
              right: -8,
              top: -8,
              child: _EditButton(icon: Icons.push_pin_outlined, tooltip: 'Unpin', onTap: onUnpin),
            ),
            if (onMore != null)
              Positioned(
                left: -8,
                top: -8,
                child: _EditButton(icon: Icons.more_horiz_rounded, tooltip: 'More', onTap: onMore!),
              ),
            if (tile.isChips) ...[
              Positioned(
                right: 36,
                top: -8,
                child: _EditButton(
                  icon: Icons.tune_rounded,
                  tooltip: 'Customise quick actions',
                  onTap: () => showCustomiseChips(context, prefs: prefs),
                ),
              ),
              Positioned(
                left: -8,
                bottom: -8,
                child: _EditButton(icon: Icons.palette_outlined, tooltip: 'Tile colour', onTap: onRecolour),
              ),
            ] else ...[
              Positioned(
                right: -8,
                bottom: -8,
                child: _EditButton(icon: Icons.open_in_full_rounded, tooltip: 'Resize', onTap: onResize),
              ),
              Positioned(
                left: -8,
                bottom: -8,
                child: _EditButton(icon: Icons.palette_outlined, tooltip: 'Tile colour', onTap: onRecolour),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: DS.onWallpaper,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(dimension: 32, child: Icon(icon, size: 18, color: Colors.black)),
      ),
    ),
  );
}

/// An app tile: its themed glyph (white) — or its full icon (setting, or no glyph) — on the
/// tile colour; bigger tiles carry the name (setting).
class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.tile, required this.prefs, required this.onTap});
  final AppEntry app;
  final TileSpec tile;
  final Prefs prefs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final glyph = switch (tile.size) {
      's' => 30.0,
      'w' => 44.0,
      'l' => 72.0,
      _ => 48.0,
    };
    return Builder(
      builder: (tileContext) {
        void tap() {
          Apps.instance.markLaunchFrom(tileContext);
          onTap();
        }

        final front = _TileFace(
          tile: tile,
          prefs: prefs,
          onTap: tap,
          child: Stack(
            children: [
              Center(
                child: prefs.tileIcons == 'icon' ? AppIcon(app, size: glyph) : TileGlyph(app: app, size: glyph),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: _Badge(id: app.package, prefs: prefs),
              ),
              if (tile.size != 's' && prefs.tileLabels)
                Positioned(
                  left: 8,
                  bottom: 6,
                  right: 8,
                  child: Text(
                    app.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
            ],
          ),
        );
        // Live tiles: medium and bigger tiles flip now and then to what's live for the app.
        if (tile.size == 's' || !prefs.fx('live')) return front;
        return _LiveFlip(
          app: app,
          front: front,
          back: (content) => _TileFace(tile: tile, prefs: prefs, onTap: tap, child: content),
        );
      },
    );
  }
}

/// A live tile: every few seconds it flips (Lumia's vertical flip) to the back — music playing
/// in this app (art + song), its unread notifications, or the next alarm on the Clock tile —
/// and back again. With nothing live it just stays the icon.
class _LiveFlip extends StatefulWidget {
  const _LiveFlip({required this.app, required this.front, required this.back});
  final AppEntry app;
  final Widget front;
  final Widget Function(Widget content) back;

  @override
  State<_LiveFlip> createState() => _LiveFlipState();
}

class _LiveFlipState extends State<_LiveFlip> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  Timer? _timer;
  (DateTime, String?)? _alarm;

  bool get _isClock => widget.app.label.toLowerCase() == 'clock' || widget.app.package.contains('deskclock');

  @override
  void initState() {
    super.initState();
    Apps.instance.media.addListener(_changed);
    Apps.instance.notifCounts.addListener(_changed);
    if (_isClock) Apps.instance.nextAlarm().then((a) => mounted ? setState(() => _alarm = a) : null);
    // Each tile on its own beat, so they don't all flip at once.
    final beat = Duration(milliseconds: 5200 + (widget.app.package.hashCode.abs() % 9) * 450);
    _timer = Timer.periodic(beat, (_) => _flip());
  }

  @override
  void dispose() {
    _timer?.cancel();
    Apps.instance.media.removeListener(_changed);
    Apps.instance.notifCounts.removeListener(_changed);
    _c.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_content() == null && _c.value > 0) _c.reverse();
    setState(() {});
  }

  void _flip() {
    if (!mounted || Perf.lite.value || TickerMode.valuesOf(context).enabled == false) return;
    if (_c.value == 0) {
      if (_content() != null) _c.forward();
    } else {
      _c.reverse();
    }
  }

  /// What the back shows now, or null when nothing's live for this app.
  Widget? _content() {
    const white = Colors.white;
    final m = Apps.instance.media.value;
    if (m != null && m['package'] == widget.app.package && (m['title'] as String? ?? '').isNotEmpty) {
      final art = m['art'] as Uint8List?;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (art != null) Image.memory(art, fit: BoxFit.cover, gaplessPlayback: true),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB3000000)]),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m['title'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: DS.font, color: white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if ((m['artist'] as String? ?? '').isNotEmpty)
                  Text(
                    m['artist'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: DS.font, color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    final n = Apps.instance.notifCounts.value[widget.app.package] ?? 0;
    if (n > 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FittedBox(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$n',
                  style: const TextStyle(fontFamily: DS.font, color: white, fontWeight: FontWeight.w300),
                ),
              ),
            ),
            Text(
              n == 1 ? 'new notification' : 'new notifications',
              style: const TextStyle(fontFamily: DS.font, color: white, fontSize: 12),
            ),
            Text(
              widget.app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: DS.font, color: white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }
    final a = _alarm;
    if (a != null) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final t = a.$1;
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.alarm_rounded, color: white, size: 22),
            const Spacer(),
            Text(
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontFamily: DS.font, color: white, fontSize: 26, fontWeight: FontWeight.w400),
            ),
            Text(
              'Next alarm · ${days[t.weekday - 1]}',
              style: const TextStyle(fontFamily: DS.font, color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final content = _content();
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final a = Curves.easeInOutCubic.transform(_c.value) * math.pi;
        final showBack = a > math.pi / 2 && content != null;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0012)
            ..rotateX(showBack ? a - math.pi : a),
          child: showBack ? widget.back(content) : widget.front,
        );
      },
    );
  }
}

/// The tile's square in its colour (resolved async for "the app's own colour").
class _TileFace extends StatelessWidget {
  const _TileFace({required this.tile, required this.prefs, required this.onTap, required this.child});
  final TileSpec tile;
  final Prefs prefs;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => TilePress(
    prefs: prefs,
    child: FutureBuilder<Color>(
      future: tileColour(tile, prefs),
      builder: (context, snap) => TileSurface(
        colour: snap.data ?? tileAccent().withValues(alpha: prefs.tileOpacity),
        prefs: prefs,
        onTap: onTap,
        child: child,
      ),
    ),
  );
}

/// A tile's surface in the chosen look. Solid: its colour. Glass: the wallpaper behind it
/// frosted (blurred), tinted with the tile's colour, with an optional bright edge and a soft
/// diagonal sheen. Lighter effects keep the tint and drop the blur.
class TileSurface extends StatelessWidget {
  const TileSurface({super.key, required this.colour, required this.prefs, required this.onTap, required this.child});
  final Color colour;
  final Prefs prefs;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(prefs.tileRadius);
    if (prefs.tileStyle != 'glass') {
      return Material(
        color: colour,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, splashColor: Colors.white24, child: child),
      );
    }
    final face = Material(
      color: colour.withValues(alpha: prefs.glassTint),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: prefs.glassEdge ? BorderSide(color: Colors.white.withValues(alpha: .35), width: 1) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white24,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (prefs.glassSheen)
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x38FFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x14FFFFFF)],
                        stops: [0, .45, .75, 1],
                      ),
                    ),
                  ),
                ),
              ),
            child,
          ],
        ),
      ),
    );
    final blur = prefs.glassBlur;
    if (blur <= 0 || Perf.lite.value) return face;
    // Grouped: all tiles share one backdrop pass (see BackdropGroup in TilesHome).
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: face,
      ),
    );
  }
}

/// How a tile reacts to a press: Lumia's tilt (it leans toward the finger and sinks a little)
/// when Interactions → Tilt is on, else the usual gentle squish.
class TilePress extends StatefulWidget {
  const TilePress({super.key, required this.prefs, required this.child});
  final Prefs prefs;
  final Widget child;

  @override
  State<TilePress> createState() => _TilePressState();
}

class _TilePressState extends State<TilePress> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 90), reverseDuration: const Duration(milliseconds: 260));
  Offset _at = Offset.zero; // press point, −1…1 from the centre

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.prefs.fx('tilt')) return Pressable(scale: .95, child: widget.child);
    return LayoutBuilder(
      builder: (context, box) => Listener(
        onPointerDown: (e) {
          _at = Offset((e.localPosition.dx / box.maxWidth * 2 - 1).clamp(-1, 1), (e.localPosition.dy / box.maxHeight * 2 - 1).clamp(-1, 1));
          _c.forward();
        },
        // The tile may have rebuilt away under the finger (long-press → edit): only if still here.
        onPointerUp: (_) => mounted ? _c.reverse() : null,
        onPointerCancel: (_) => mounted ? _c.reverse() : null,
        child: AnimatedBuilder(
          animation: _c,
          child: widget.child,
          builder: (context, child) {
            final t = Curves.easeOut.transform(_c.value);
            // Bigger tiles tilt less (as on Lumia); the press point sinks most.
            final k = .32 * t * (90 / math.max(90, math.min(box.maxWidth, box.maxHeight))).clamp(.45, 1.0);
            final m = Matrix4.identity()
              ..setEntry(3, 2, .0015)
              ..rotateX(_at.dy * k)
              ..rotateY(-_at.dx * k);
            return Transform(transform: m..scaleByDouble(1 - .04 * t, 1 - .04 * t, 1, 1), alignment: Alignment.center, child: child);
          },
        ),
      ),
    );
  }
}

/// The Start page's content, at least a screen tall: its empty space (between and below tiles)
/// takes the double-tap to lock — tiles themselves never wait on it.
class _EmptySpace extends StatelessWidget {
  const _EmptySpace({required this.minHeight, required this.onDoubleTap, required this.child});
  final double minHeight;
  final VoidCallback? onDoubleTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: math.max(0, minHeight)),
    child: Stack(
      children: [
        if (onDoubleTap != null)
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onDoubleTap: onDoubleTap),
          ),
        child,
      ],
    ),
  );
}

/// The tile a dragged app is held over to make (or join) a folder — it shows an outline.
final mergeTarget = ValueNotifier<String?>(null);

/// A folder on Start: up to four of its apps in a little grid, its name, and the count of
/// unread notifications inside. Tap opens it inline (Lumia / Windows 10 Mobile).
class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.tile, required this.apps, required this.prefs, required this.open, required this.onTap});
  final TileSpec tile;
  final Map<String, AppEntry> apps;
  final Prefs prefs;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inside = [
      for (final p in tile.items)
        if (apps[p] != null) apps[p]!,
    ];
    final small = tile.size == 's';
    final glyph = switch (tile.size) {
      's' => 14.0,
      'l' => 52.0,
      'w' => 30.0,
      _ => 26.0,
    };
    return _TileFace(
      tile: tile,
      prefs: prefs,
      onTap: onTap,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(small ? 8 : 12),
            child: Wrap(
              spacing: small ? 4 : 8,
              runSpacing: small ? 4 : 8,
              children: [for (final a in inside.take(4)) TileGlyph(app: a, size: glyph)],
            ),
          ),
          if (!small && prefs.tileLabels)
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tile.name ?? 'Folder',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.white, size: 18),
                ],
              ),
            ),
          if (prefs.fx('badges'))
            Positioned(
              right: 6,
              top: 6,
              child: ValueListenableBuilder<Map<String, int>>(
                valueListenable: Apps.instance.notifCounts,
                builder: (context, counts, _) {
                  final n = inside.fold<int>(0, (sum, a) => sum + (counts[a.package] ?? 0));
                  return n == 0 ? const SizedBox.shrink() : _Badge(id: '', prefs: prefs, count: n);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// An open folder: its apps as small tiles across the full width, right under the folder
/// (the tiles below move down). Long-press an app to take it out.
class _FolderPanel extends StatelessWidget {
  const _FolderPanel({required this.panel, required this.apps, required this.unit, required this.prefs, required this.onLaunch, required this.onOut});
  final TileSpec panel;
  final Map<String, AppEntry> apps;
  final double unit;
  final Prefs prefs;
  final ValueChanged<AppEntry> onLaunch;
  final ValueChanged<String> onOut;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(prefs.tileRadius)),
      child: Wrap(
        spacing: _StartPage.gap,
        runSpacing: _StartPage.gap,
        children: [
          for (final p in panel.items)
            SizedBox.square(
              dimension: unit,
              child: GestureDetector(
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  showOneSheet(
                    context,
                    header: SheetHeader(title: apps[p]!.label, leading: AppIcon(apps[p]!, size: 40)),
                    actions: [
                      SheetAction(Icons.drive_file_move_outline, 'Move out of folder', () {
                        Navigator.pop(context);
                        onOut(p);
                      }),
                      SheetAction(Icons.info_outline_rounded, 'App info', () {
                        Navigator.pop(context);
                        Apps.instance.appInfo(p);
                      }),
                    ],
                  );
                },
                child: _AppTile(app: apps[p]!, tile: TileSpec('app:$p', 's', panel.colour), prefs: prefs, onTap: () => onLaunch(apps[p]!)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Black with tile-shaped holes (Wallpaper through tiles).
class _Holes extends CustomPainter {
  _Holes(this.rects, this.offset, this.radius);
  final List<Rect> rects;
  final double offset, radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    for (final r in rects) {
      final at = r.shift(Offset(0, -offset));
      if (at.bottom < 0 || at.top > size.height) continue;
      path.addRRect(RRect.fromRectAndRadius(at, Radius.circular(radius)));
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(_Holes o) => o.offset != offset || o.radius != radius || !listEquals(o.rects, rects);
}

/// Unread-notification count on a tile's corner (Interactions → Notification badges).
class _Badge extends StatelessWidget {
  const _Badge({required this.id, required this.prefs, this.count});
  final String id; // the app id ("pkg" / "pkg@profile")
  final Prefs prefs;
  final int? count; // given (a folder's total) instead of looked up

  @override
  Widget build(BuildContext context) {
    if (!prefs.fx('badges')) return const SizedBox.shrink();
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: Apps.instance.notifCounts,
      builder: (context, counts, _) {
        final n = count ?? counts[id] ?? 0;
        if (n == 0) return const SizedBox.shrink();
        return Container(
          constraints: const BoxConstraints(minWidth: 22),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
          child: Text(
            n > 99 ? '99+' : '$n',
            style: TextStyle(fontFamily: DS.font, color: tileAccent(), fontSize: 12, fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}

/// Edit mode → palette: the Start default, accent, the app's own colour, or a Material colour.
class _Palette extends StatelessWidget {
  const _Palette({required this.current, required this.app});
  final String? current;
  final String? app; // null for live tiles (no "app colour")

  @override
  Widget build(BuildContext context) {
    Widget swatch(String value, Color colour, {String? label, IconData? icon}) {
      final on = (current ?? 'default') == value;
      return Tooltip(
        message: label ?? 'Colour',
        child: InkWell(
          onTap: () => Navigator.pop(context, value),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colour,
              border: on ? Border.all(color: DS.ink, width: 3) : null,
            ),
            child: icon == null ? null : Icon(icon, color: Colors.white),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeader(title: 'Tile colour'),
            const SizedBox(height: DS.s16),
            Wrap(
              spacing: DS.s8,
              runSpacing: DS.s8,
              children: [
                swatch('default', DS.cardMuted, label: 'Start default', icon: Icons.auto_awesome_rounded),
                swatch('accent', tileAccent(), label: 'Accent'),
                if (app != null) swatch('app', DS.inkMuted, label: 'App colour', icon: Icons.colorize_rounded),
                for (final c in tileSwatches) swatch(c.toARGB32().toRadixString(16), c),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick-action tile: the action's icon and name; tap runs it. Flashlight shows when it's on.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.tile, required this.prefs, required this.onTap});
  final TileSpec tile;
  final Prefs prefs;
  final VoidCallback? onTap; // null: run the action

  @override
  Widget build(BuildContext context) {
    final id = tile.action;
    final builtIn = builtInActions[id];
    final label = builtIn?.$1 ?? (prefs.quickLabels[id]?.split('|').first ?? 'Shortcut');
    final size = switch (tile.size) {
      's' => 30.0,
      'w' => 44.0,
      'l' => 72.0,
      _ => 48.0,
    };
    Widget face(bool on) => _TileFace(
      tile: tile,
      prefs: prefs,
      onTap: onTap ?? () => runQuickAction(context, prefs, id, label),
      child: Stack(
        children: [
          Center(
            child: builtIn != null
                ? Icon(on ? Icons.flashlight_on_rounded : builtIn.$2, size: size, color: Colors.white)
                : ShortcutIcon(id: id, size: size, color: Colors.white),
          ),
          if (on) // lit: a white ring inside the tile
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(prefs.tileRadius),
                ),
              ),
            ),
          if (tile.size != 's' && prefs.tileLabels)
            Positioned(
              left: 8,
              bottom: 6,
              right: 8,
              child: Text(
                on ? '$label · on' : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
    if (id != 'b:torch') return face(false);
    return ValueListenableBuilder<bool>(valueListenable: Apps.instance.torchOn, builder: (context, on, _) => face(on));
  }
}

/// The app's own shortcuts (New message, Scan QR…) as sheet rows (Interactions → Shortcuts).
Future<List<SheetAction>> appShortcutActions(BuildContext context, AppEntry a) async {
  final all = await Apps.instance.shortcuts() ?? const <AppShortcut>[];
  final pkg = a.package.split('@').first;
  return [
    for (final sc in all)
      if (sc.package == pkg && sc.work == a.work)
        SheetAction(Icons.bolt_rounded, sc.label, () {
          Navigator.pop(context);
          Apps.instance.quickAction(sc.id);
        }),
  ];
}

/// Edit mode → ⋯ on an app tile: its shortcuts, App info, Uninstall.
Future<void> showTileMenu(BuildContext context, Prefs prefs, AppEntry a) async {
  final shortcuts = prefs.fx('shortcuts') ? await appShortcutActions(context, a) : const <SheetAction>[];
  if (!context.mounted) return;
  showOneSheet(
    context,
    header: SheetHeader(title: a.label, leading: AppIcon(a, size: 40)),
    actions: [
      ...shortcuts,
      SheetAction(Icons.info_outline_rounded, 'App info', () {
        Navigator.pop(context);
        Apps.instance.appInfo(a.package);
      }),
      SheetAction(Icons.delete_outline_rounded, 'Uninstall', () {
        Navigator.pop(context);
        Apps.instance.uninstall(a.package);
      }, danger: true),
    ],
  );
}

/// A filled square in the app list (icon backs, jump letters) in the tile look: glass tiles →
/// a tinted pane with the bright edge and sheen.
BoxDecoration listSquare(Prefs prefs, Color colour, double radius) {
  if (prefs.tileStyle != 'glass') return BoxDecoration(color: colour, borderRadius: BorderRadius.circular(radius));
  final tint = colour.withValues(alpha: (.3 + prefs.glassTint).clamp(.25, .92));
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: prefs.glassEdge ? Border.all(color: Colors.white.withValues(alpha: .35)) : null,
    // A gradient replaces the fill: the tint, lit at the corners when Sheen is on.
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: prefs.glassSheen ? [Color.alphaBlend(const Color(0x38FFFFFF), tint), tint, tint, Color.alphaBlend(const Color(0x14FFFFFF), tint)] : [tint, tint],
      stops: prefs.glassSheen ? const [0, .45, .75, 1] : null,
    ),
  );
}

/// Runs a quick action from Start (our own TV remote opens here; the rest go to the phone).
Future<void> runQuickAction(BuildContext context, Prefs prefs, String id, String label) async {
  HapticFeedback.selectionClick();
  if (id == 'b:remote') return showTvRemote(context, prefs: prefs);
  final ok = await Apps.instance.quickAction(id);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn’t open “$label” on this phone'), behavior: SnackBarBehavior.floating));
  }
}

/// The quick-actions row on Start: the classic chips, drawn as tiles — the row's colour and
/// transparency, the Start corner radius, white icon + name — filling the row's height, with
/// the tile gap between them. Scrolls sideways when they don't fit; ＋ at the end to customise.
class _ChipsRowTile extends StatelessWidget {
  const _ChipsRowTile({required this.tile, required this.prefs});
  final TileSpec tile;
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    final labels = prefs.quickLabels;
    final ids = prefs.quickChips.where((id) => builtInActions.containsKey(id) || labels.containsKey(id)).toList();
    final radius = BorderRadius.circular(prefs.tileRadius);
    Widget chip(String id, bool on) {
      final builtIn = builtInActions[id];
      final label = builtIn?.$1 ?? labels[id]!.split('|').first;
      return TilePress(
        prefs: prefs,
        child: FutureBuilder<Color>(
          future: tileColour(tile, prefs),
          builder: (context, snap) => TileSurface(
            colour: snap.data ?? tileAccent().withValues(alpha: prefs.tileOpacity),
            prefs: prefs,
            onTap: () => runQuickAction(context, prefs, id, label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: DS.s12),
              foregroundDecoration: on
                  ? BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: radius,
                    )
                  : null,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  builtIn != null
                      ? Icon(on ? Icons.flashlight_on_rounded : builtIn.$2, size: 18, color: Colors.white)
                      : ShortcutIcon(id: id, size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final id in ids) ...[
          id == 'b:torch' ? ValueListenableBuilder<bool>(valueListenable: Apps.instance.torchOn, builder: (context, on, _) => chip(id, on)) : chip(id, false),
          const SizedBox(width: _StartPage.gap),
        ],
        // ＋ : arrange the chips and add more (the same sheet as the classic view).
        Tooltip(
          message: 'Customise quick actions',
          child: InkWell(
            borderRadius: radius,
            onTap: () {
              HapticFeedback.mediumImpact();
              showCustomiseChips(context, prefs: prefs);
            },
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 1.5),
                  borderRadius: radius,
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tiles search, styled like the classic home's: the search pill slides down from the top over
/// a dimmed screen. Empty → your most-used apps; typing → the same results as the classic home
/// (best match with Open, other apps in a row, shortcuts, phone settings, the web, Play Store —
/// from Settings → Search → Search in). Enter opens the best match. ✕ clears, or closes when
/// empty; tapping the dim area, Back, or swiping between pages closes it too.
class _TileSearch extends StatefulWidget {
  const _TileSearch({
    required this.anim,
    required this.text,
    required this.focus,
    required this.apps,
    required this.prefs,
    required this.onClose,
    required this.onLaunch,
  });
  final Animation<double> anim;
  final TextEditingController text;
  final FocusNode focus;
  final List<AppEntry> apps;
  final Prefs prefs;
  final VoidCallback onClose;
  final ValueChanged<AppEntry> onLaunch;

  @override
  State<_TileSearch> createState() => _TileSearchState();
}

class _TileSearchState extends State<_TileSearch> {
  List<AppShortcut>? _shortcuts; // loaded once per search
  String _last = '';

  @override
  void initState() {
    super.initState();
    widget.text.addListener(_typed);
  }

  @override
  void dispose() {
    widget.text.removeListener(_typed);
    super.dispose();
  }

  void _typed() {
    final q = widget.text.text.trim();
    if (q == _last) return;
    _last = q;
    if (q.isNotEmpty && _shortcuts == null && widget.prefs.searchIn.contains('shortcuts')) {
      Apps.instance.shortcuts().then((list) {
        if (mounted) setState(() => _shortcuts = list ?? const []);
      });
    }
    // Settings → Search → open the only match.
    if (q.isNotEmpty && widget.prefs.autoOpenSingleMatch && widget.prefs.searchIn.contains('apps')) {
      final r = searchApps(widget.apps, q);
      if (r.length == 1) return widget.onLaunch(r.first);
    }
    setState(() {});
  }

  void _run(Future<void> Function() action) async {
    widget.onClose();
    await action();
  }

  void _submit(String q) {
    final best = searchApps(widget.apps, q);
    if (best.isNotEmpty && widget.prefs.searchIn.contains('apps')) return widget.onLaunch(best.first);
    if (q.trim().isNotEmpty && widget.prefs.searchIn.contains('google')) _run(() => Apps.instance.webSearch(q.trim()));
  }

  /// Most-used apps (empty search): one row of icons.
  Widget _recent() {
    final byPkg = {for (final a in widget.apps) a.package: a};
    final used = widget.prefs.launchCounts.entries.where((e) => byPkg.containsKey(e.key)).toList()..sort((a, b) => b.value.compareTo(a.value));
    final apps = [for (final e in used.take(8)) byPkg[e.key]!];
    if (apps.isEmpty) return const SizedBox.shrink();
    return OneCard(
      padding: const EdgeInsets.fromLTRB(DS.s8, DS.s12, DS.s8, DS.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DS.s8),
            child: Text('Your apps', style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 13)),
          ),
          const SizedBox(height: DS.s8),
          SizedBox(
            height: 84,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final a in apps)
                  SizedBox(
                    width: 76,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(DS.rMedia),
                      onTap: () => widget.onLaunch(a),
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          AppIcon(a, size: 48),
                          const SizedBox(height: 6),
                          Text(
                            a.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DS.iconLabel.copyWith(color: DS.ink),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final q = widget.text.text.trim();
    final results = q.isEmpty
        ? _recent()
        : searchResults(
            prefs: widget.prefs,
            query: q,
            apps: widget.apps,
            shortcuts: _shortcuts,
            onLaunch: widget.onLaunch,
            onLongPress: (a) => showTileMenu(context, widget.prefs, a),
            onWebSearch: (query, {play = false}) => _run(() => play ? Apps.instance.playSearch(query) : Apps.instance.webSearch(query)),
            onRun: _run,
          );

    return AnimatedBuilder(
      animation: widget.anim,
      builder: (context, bar) {
        final t = Curves.easeOutCubic.transform(widget.anim.value);
        if (t == 0) return const SizedBox.shrink();
        return Stack(
          fit: StackFit.expand,
          children: [
            // No dark cover: the page behind has stepped back; tap the empty space to close.
            GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onClose),
            // The pill comes down from above the screen.
            Positioned(
              left: DS.gutter,
              right: DS.gutter,
              top: pad.top + DS.s12 - (1 - t) * (pad.top + 90),
              child: Opacity(opacity: t, child: bar),
            ),
            Positioned(
              left: DS.gutter,
              right: DS.gutter,
              top: pad.top + DS.s12 + 56 + DS.s12,
              bottom: math.max(keyboard, pad.bottom) + DS.s8,
              child: Opacity(
                opacity: t,
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual, // keep typing while scrolling
                  child: AnimatedSwitcher(
                    duration: Motion.snapDuration,
                    child: KeyedSubtree(key: ValueKey(q.isEmpty), child: results),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      // The classic home's search pill.
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), boxShadow: Perf.lite.value ? null : SearchDock.shadow),
        child: Material(
          color: DS.card,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: DS.s16),
                Icon(Icons.search_rounded, color: DS.ink),
                const SizedBox(width: DS.s12),
                Expanded(
                  child: TextField(
                    controller: widget.text,
                    focusNode: widget.focus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _submit,
                    cursorColor: DS.ink,
                    style: DS.rowTitle.copyWith(fontWeight: FontWeight.w400),
                    decoration: InputDecoration(
                      hintText: 'Search ${widget.apps.length} apps & more',
                      hintStyle: DS.rowTitle.copyWith(fontWeight: FontWeight.w400, color: DS.inkMuted),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                  ),
                ),
                // ✕: clears what's typed, or closes search when there's nothing.
                IconButton(
                  tooltip: q.isEmpty ? 'Close search' : 'Clear',
                  icon: Icon(Icons.close_rounded, color: DS.ink),
                  onPressed: () => q.isEmpty ? widget.onClose() : widget.text.clear(),
                ),
                const SizedBox(width: DS.s4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pick a quick action (built-in or an app's shortcut) and put it on Start as a small tile.
Future<void> addActionTile(BuildContext context, Prefs prefs) async {
  final onStart = {for (final m in prefs.tiles ?? const <Map<String, dynamic>>[]) m['id'] as String};
  final picked = await showOneSheetWith(context, builder: (ctx) => _ActionPicker(onStart: onStart));
  if (picked is! (String, String, String)) return;
  final (id, label, app) = picked;
  HapticFeedback.mediumImpact();
  final tiles = [...?prefs.tiles];
  if (id == 'chips') {
    // The whole quick-actions row, right under the first tile (usually the clock) so it's seen.
    tiles.insert(math.min(1, tiles.length), const TileSpec('chips', 'm').toJson());
    return prefs.setTiles(tiles);
  }
  if (id.startsWith('s:')) await prefs.nameQuickAction(id, label, app);
  await prefs.setTiles([...tiles, TileSpec('qa:$id', 's').toJson()]);
}

class _ActionPicker extends StatefulWidget {
  const _ActionPicker({required this.onStart});
  final Set<String> onStart;

  @override
  State<_ActionPicker> createState() => _ActionPickerState();
}

class _ActionPickerState extends State<_ActionPicker> {
  final _shortcuts = Apps.instance.shortcuts();
  var _query = '';

  @override
  Widget build(BuildContext context) {
    Widget row(String id, Widget icon, String title, String sub, String app) {
      final added = widget.onStart.contains(id == 'chips' ? 'chips' : 'qa:$id');
      return InkWell(
        onTap: added ? null : () => Navigator.pop(context, (id, title, app)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: DS.s12),
          child: Row(
            children: [
              SizedBox.square(dimension: 28, child: Center(child: icon)),
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
                    Text(added ? 'On Start' : sub, style: DS.rowSub.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              Icon(added ? Icons.check_rounded : Icons.add_rounded, color: added ? DS.inkMuted : DS.ink),
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
          padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s12),
          child: SheetHeader(title: 'Add a tile', subtitle: 'Quick actions and app shortcuts'),
        ),
        SheetSearchField(hint: 'Search actions & app shortcuts', onChanged: (q) => setState(() => _query = q)),
        if (matchesQuery(_query, ['Quick actions row', 'chips']))
          row('chips', Icon(Icons.view_week_outlined, color: DS.ink), 'Quick actions row', 'All your quick actions in one line · move it as a group', ''),
        for (final MapEntry(key: id, value: (name, icon)) in builtInActions.entries)
          if (matchesQuery(_query, [name])) row(id, Icon(icon, color: DS.ink), name, 'Quick action', ''),
        FutureBuilder<List<AppShortcut>?>(
          future: _shortcuts,
          builder: (context, snap) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final sc in snap.data ?? const <AppShortcut>[])
                if (matchesQuery(_query, [sc.label, sc.app]))
                  row(sc.id, ShortcutIcon(id: sc.id, size: 26, color: DS.ink), sc.label, sc.work ? '${sc.app} · Work' : sc.app, sc.app),
            ],
          ),
        ),
        const SizedBox(height: DS.s16),
      ],
    );
  }
}

/// The app's white themed glyph, else its normal icon.
class TileGlyph extends StatelessWidget {
  const TileGlyph({super.key, required this.app, required this.size});
  final AppEntry app;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: FutureBuilder<Uint8List?>(
      future: Apps.instance.monoIcon(app.package),
      builder: (context, snap) => snap.connectionState != ConnectionState.done
          ? const SizedBox.shrink()
          : snap.data != null
          ? withWorkBadge(app, size, Image.memory(snap.data!, gaplessPlayback: true, filterQuality: FilterQuality.medium))
          : AppIcon(app, size: size),
    ),
  );
}

/// An app icon's main colour, deepened for white text — for colourful tiles. Cached.
final _colours = <String, Future<Color>>{};
Future<Color> iconColour(String package) => _colours.putIfAbsent(package, () async {
  final bytes = await Apps.instance.icon(package);
  if (bytes == null) return tileAccent();
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24, targetHeight: 24);
  final img = (await codec.getNextFrame()).image;
  final data = await img.toByteData();
  img.dispose();
  if (data == null) return tileAccent();
  // Average the colourful, opaque pixels (ignore white/black/grey backgrounds).
  var r = 0.0, g = 0.0, b = 0.0, n = 0;
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    final a = data.getUint8(i + 3);
    if (a < 200) continue;
    final c = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    final hsl = HSLColor.fromColor(c);
    if (hsl.saturation < .25 || hsl.lightness < .12 || hsl.lightness > .92) continue;
    r += c.r;
    g += c.g;
    b += c.b;
    n++;
  }
  if (n < 8) return tileAccent();
  final avg = HSLColor.fromColor(Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n));
  return avg.withSaturation(math.max(avg.saturation, .45)).withLightness(.4).toColor();
});

/// Live clock tile: big time, the day and date; updates every minute. Tap opens Clock.
class _ClockTile extends StatefulWidget {
  const _ClockTile({required this.tile, required this.prefs, required this.onTap});
  final TileSpec tile;
  final Prefs prefs;
  final VoidCallback onTap;

  @override
  State<_ClockTile> createState() => _ClockTileState();
}

class _ClockTileState extends State<_ClockTile> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    _timer = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0'), m = now.minute.toString().padLeft(2, '0');
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final p = widget.prefs;
    final style = clockStyle(
      weight: p.tileClockWeight,
      width: p.tileClockWidth,
      slant: p.tileClockSlant,
      round: p.tileClockRound,
    ).copyWith(color: Colors.white, shadows: const []);
    return _TileFace(
      tile: widget.tile,
      prefs: widget.prefs,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text('$h:$m', style: style),
              ),
            ),
            if (widget.tile.size != 'm') ...[
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    days[now.weekday - 1],
                    style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '${now.day} ${months[now.month - 1]}',
                    style: const TextStyle(fontFamily: DS.font, color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- All apps -------------------------------------------------------------------------------

class _AppListPage extends StatefulWidget {
  const _AppListPage({
    required this.apps,
    required this.prefs,
    required this.isPinned,
    required this.onLaunch,
    required this.onPin,
    required this.onUnpin,
    required this.onSettings,
    required this.onRemote,
    required this.onSearch,
  });

  final List<AppEntry> apps;
  final VoidCallback onSearch;
  final Prefs prefs;
  final bool Function(String package) isPinned;
  final ValueChanged<AppEntry> onLaunch, onPin, onUnpin;
  final VoidCallback onSettings;
  final VoidCallback? onRemote;

  @override
  State<_AppListPage> createState() => _AppListPageState();
}

class _AppListPageState extends State<_AppListPage> {
  static const rowH = 60.0;
  final _list = ScrollController();
  bool _jump = false; // the A–Z jump grid is up

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  static String _letter(AppEntry a) {
    final c = a.label.isEmpty ? '#' : a.label[0].toUpperCase();
    return RegExp('[A-Z]').hasMatch(c) ? c : '#';
  }

  /// Rows: letter headers ('#', 'A'…) and apps, in order.
  List<Object> _rows() {
    final sorted = [...widget.apps]
      ..sort((a, b) {
        final la = _letter(a), lb = _letter(b);
        if (la != lb) return la == '#' ? -1 : (lb == '#' ? 1 : la.compareTo(lb));
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    final out = <Object>[];
    String? last;
    for (final a in sorted) {
      final l = _letter(a);
      if (l != last) out.add(l);
      out.add(a);
      last = l;
    }
    return out;
  }

  Future<void> _menu(AppEntry a) async {
    HapticFeedback.mediumImpact();
    final pinned = widget.isPinned(a.package);
    final shortcuts = widget.prefs.fx('shortcuts') ? await appShortcutActions(context, a) : const <SheetAction>[];
    if (!mounted) return;
    showOneSheet(
      context,
      header: SheetHeader(title: a.label, leading: AppIcon(a, size: 40)),
      actions: [
        ...shortcuts,
        SheetAction(pinned ? Icons.push_pin : Icons.push_pin_outlined, pinned ? 'Unpin from Start' : 'Pin to Start', () {
          Navigator.pop(context);
          pinned ? widget.onUnpin(a) : widget.onPin(a);
        }),
        SheetAction(Icons.info_outline_rounded, 'App info', () {
          Navigator.pop(context);
          Apps.instance.appInfo(a.package);
        }),
        SheetAction(Icons.delete_outline_rounded, 'Uninstall', () {
          Navigator.pop(context);
          Apps.instance.uninstall(a.package);
        }, danger: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final rows = _rows();
    final accent = tileAccent();
    final small = widget.prefs.tileRadius * .5; // list squares are smaller than tiles
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(DS.s16, pad.top + DS.s12, DS.s8, DS.s8),
              child: Row(
                children: [
                  // Just the icon: the full bar comes down from the top while searching
                  // (or pull down on the list).
                  IconButton(
                    tooltip: 'Search apps',
                    onPressed: widget.onSearch,
                    icon: const Icon(Icons.search_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  if (widget.onRemote != null)
                    GestureDetector(
                      onLongPress: () => offerHideRemote(context, prefs: widget.prefs),
                      child: IconButton(
                        tooltip: 'TV remote',
                        onPressed: widget.onRemote,
                        icon: const Icon(Icons.settings_remote_rounded, color: Colors.white),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Launcher settings',
                    onPressed: widget.onSettings,
                    icon: const Icon(Icons.tune_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _list,
                padding: EdgeInsets.fromLTRB(DS.s16, 0, DS.s16, pad.bottom + DS.s24),
                itemExtent: rowH,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0), // build rows as they scroll in, so they animate in view
                itemCount: rows.length,
                // Landing: rows on screen come in one after another; rows scrolled to later don't.
                itemBuilder: (context, i) => Landed(
                  landing: listLanding,
                  style: widget.prefs.listAnim,
                  reveal: true, // rows scrolled to come in as they appear
                  delay: Duration(milliseconds: 24 * (i - (_list.hasClients ? _list.offset ~/ rowH : 0)).clamp(0, 16)),
                  child: Builder(
                    builder: (context) {
                      final r = rows[i];
                      if (r is String) {
                        // Letter tile: tap for the A–Z jump grid.
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Tooltip(
                            message: 'Jump to a letter',
                            child: InkWell(
                              onTap: () => setState(() => _jump = true),
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.bottomLeft,
                                padding: const EdgeInsets.fromLTRB(6, 0, 0, 2),
                                decoration: BoxDecoration(
                                  border: Border.all(color: accent, width: 2),
                                  borderRadius: BorderRadius.circular(small),
                                ),
                                child: Text(
                                  r.toLowerCase(),
                                  style: TextStyle(fontFamily: DS.font, color: accent, fontSize: 24, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      final a = r as AppEntry;
                      return Builder(
                        builder: (rowContext) => InkWell(
                          onTap: () {
                            Apps.instance.markLaunchFrom(rowContext);
                            widget.onLaunch(a);
                          },
                          onLongPress: () => _menu(a),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: listSquare(widget.prefs, accent, small),
                                alignment: Alignment.center,
                                child: TileGlyph(app: a, size: 28),
                              ),
                              const SizedBox(width: DS.s16),
                              Expanded(
                                child: Text(
                                  a.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontFamily: DS.font, color: Colors.white, fontSize: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_jump) _JumpGrid(rows: rows, accent: accent, onPick: _jumpTo, onClose: () => setState(() => _jump = false)),
      ],
    );
  }

  void _jumpTo(String letter) {
    final rows = _rows();
    final i = rows.indexOf(letter);
    setState(() => _jump = false);
    if (i >= 0 && _list.hasClients) {
      HapticFeedback.selectionClick();
      _list.jumpTo((i * rowH).clamp(0, _list.position.maxScrollExtent));
    }
  }
}

/// The A–Z grid over the list (Lumia's letter jump): letters with apps are lit.
class _JumpGrid extends StatelessWidget {
  const _JumpGrid({required this.rows, required this.accent, required this.onPick, required this.onClose});
  final List<Object> rows;
  final Color accent;
  final ValueChanged<String> onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final have = rows.whereType<String>().toSet();
    final letters = ['#', for (var c = 65; c <= 90; c++) String.fromCharCode(c)];
    final pad = MediaQuery.paddingOf(context);
    return GestureDetector(
      onTap: onClose,
      child: ColoredBox(
        color: const Color(0xE6000000),
        child: Padding(
          padding: EdgeInsets.fromLTRB(DS.s16, pad.top + DS.s24, DS.s16, pad.bottom + DS.s24),
          child: Center(
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final l in letters)
                  Material(
                    color: have.contains(l) ? accent : Colors.white10,
                    child: InkWell(
                      onTap: have.contains(l) ? () => onPick(l) : null,
                      child: Container(
                        alignment: Alignment.bottomLeft,
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          l.toLowerCase(),
                          style: TextStyle(
                            fontFamily: DS.font,
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            color: have.contains(l) ? Colors.white : Colors.white30,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
