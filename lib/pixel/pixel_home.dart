import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_lock.dart';
import '../apps.dart';
import '../photo_wallpaper.dart';
import '../prefs.dart';
import '../sheets.dart';
import '../tiles/today_panel.dart';
import '../ui/photo_file.dart';
import '../ui/theme.dart';
import 'pixel_drawer.dart';
import 'pixel_folder.dart';
import 'pixel_icon.dart';
import 'pixel_model.dart';
import 'pixel_popup.dart';
import 'pixel_settings.dart';

/// Pixel view: Pixel Launcher's home, end to end (see docs/PIXEL_VIEW.md).
///
/// One pager: the Today panel (left of page 1, when on) then the home pages; At a Glance, the
/// page dots, the dock and the search pill float over it. The all-apps drawer stays mounted and
/// is translated off screen, because a drag that starts on one of its icons carries on over the
/// home's drop targets.
class PixelHome extends StatefulWidget {
  const PixelHome({
    super.key,
    required this.prefs,
    required this.theme,
    this.preview = false,
  });
  final Prefs prefs;
  final OneTheme theme;

  /// Drawn small inside Settings (Home view): no gestures, no native calls.
  final bool preview;

  @override
  State<PixelHome> createState() => _PixelHomeState();
}

class _Hit {
  const _Hit.grid(this.page, this.r, this.c, this.centre) : dock = false, i = 0;
  const _Hit.dock(this.i, this.centre) : dock = true, page = 0, r = 0, c = 0;
  final bool dock, centre;
  final int page, r, c, i;
  @override
  bool operator ==(Object o) =>
      o is _Hit &&
      o.dock == dock &&
      o.centre == centre &&
      o.page == page &&
      o.r == r &&
      o.c == c &&
      o.i == i;
  @override
  int get hashCode => Object.hash(dock, centre, page, r, c, i);
}

class _MenuItem {
  const _MenuItem(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _Geo {
  double w = 0,
      h = 0,
      top = 0,
      left = 12,
      gridH = 0,
      cw = 0,
      ch = 0,
      icon = 56,
      dockTop = 0,
      dockH = 0,
      dockCell = 0;
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _shadow = [Shadow(blurRadius: 6, color: Color(0x66000000))];

class _PixelHomeState extends State<PixelHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  Prefs get prefs => widget.prefs;
  PixelSettings get _s => PixelSettings.of(prefs);

  List<AppEntry> _apps = const [];
  Map<String, AppEntry> _byPkg = const {};
  PixelLayout? _layout;
  int _seenAt = 0;
  final _geo = _Geo();
  final _areaKey = GlobalKey();

  // Pager.
  late bool _hasPanel = _s.leftPanel && !widget.preview;
  late PageController _pager = PageController(initialPage: _hasPanel ? 1 : 0);
  int _page = 0; // home page shown (-1 = the Today panel)

  // Drawer: 0 closed … 1 open.
  late final AnimationController _drawer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  final _searchFocus = FocusNode();
  double _pullDy = 0;

  // Folders.
  String? _openFolder;
  Rect _folderFrom = Rect.zero;
  final _folderKey = GlobalKey<PixelFolderOpenState>();

  // Menu.
  Offset? _menuAt;
  bool _bigMenu = false;

  // Long-press on empty space, from raw pointers (the gesture arena with the pager and the
  // pull-down drag could swallow it).
  Timer? _lpTimer;
  Offset? _lpAt;
  int? _lpPointer;
  List<_MenuItem> _menuItems = const [];

  // Dragging.
  bool _dragging = false, _fromDrawer = false;
  String? _dragId, _fromFolderId;
  Offset? _dragFirst;
  PixelPopupHandle? _popup;
  final _hover = ValueNotifier<_Hit?>(null);
  Timer? _edgeTimer;
  int _edgeDir = 0;
  final _dockScroll = ScrollController();

  // At a Glance.
  Map _event = const {};
  (DateTime, String?)? _alarm;
  Map<String, int> _counts = const {};

  @override
  void initState() {
    super.initState();
    prefs.addListener(_onPrefs);
    if (!widget.preview) {
      WidgetsBinding.instance.addObserver(this);
      Apps.instance.onAppsChanged = _load;
      Apps.instance.onHomePressed = _home;
    }
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    prefs.removeListener(_onPrefs);
    _edgeTimer?.cancel();
    _lpTimer?.cancel();
    _popup?.close();
    _pager.dispose();
    _drawer.dispose();
    _searchFocus.dispose();
    _dockScroll.dispose();
    _hover.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      widget.theme.refreshSystem();
    }
  }

  // ---- data ---------------------------------------------------------------------------------

  Future<void> _load() async {
    final apps = await Apps.instance.list();
    if (!mounted) return;
    _apps = apps;
    _byPkg = {for (final a in apps) a.package: a};
    if (apps.isNotEmpty) _settle();
    setState(() {});
    if (widget.preview) return;
    Apps.instance.refreshNotifCounts();
    final ev = await Apps.instance.nextEvent();
    final al = await Apps.instance.nextAlarm();
    if (!mounted) return;
    setState(() {
      _event = ev;
      _alarm = al;
    });
  }

  void _onPrefs() {
    if (!mounted) return;
    final panel = _s.leftPanel && !widget.preview;
    if (panel != _hasPanel) {
      final old = _pager;
      _hasPanel = panel;
      _pager = PageController(
        initialPage: math.max(0, _page) + (panel ? 1 : 0),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (_layout != null) _settle();
    setState(() {});
  }

  /// First open → seed; later: drop what was uninstalled, fit to the grid, add new installs.
  void _settle() {
    final s = _s;
    var changed = false, fresh = false;
    final now = DateTime.now().millisecondsSinceEpoch;
    var l = _layout;
    if (l == null) {
      final stored = PixelLayout.of(prefs);
      if (stored != null) {
        l = stored;
        _seenAt = (prefs.pixelLayout['seenAt'] as num?)?.toInt() ?? now;
      } else {
        final usable = [
          for (final a in _apps)
            if (!a.isShortcut && !a.work && !prefs.hidden.contains(a.package))
              a.package,
        ];
        l = PixelLayout.seed(
          favourites: [
            for (final f in prefs.favourites)
              if (_byPkg.containsKey(f)) f,
          ],
          apps: usable,
          s: s,
        );
        _seenAt = now;
        fresh = true;
        changed = true;
      }
      _layout = l;
    }
    changed |= _prune(l);
    changed |= _fit(l, s);
    if (!fresh && s.addNewApps) {
      final placed = l.placedApps;
      for (final a in _apps) {
        if (a.isShortcut ||
            a.work ||
            a.installed <= _seenAt ||
            placed.contains(a.package) ||
            prefs.hidden.contains(a.package)) {
          continue;
        }
        final (p, r, c) = l.firstFree(s.rows, s.cols);
        l.place('app:${a.package}', p, r, c);
        changed = true;
      }
      if (changed || _apps.any((a) => a.installed > _seenAt)) {
        _seenAt = now;
        changed = true;
      }
    }
    if (changed && !widget.preview) {
      l.tidy();
      prefs.setPixelLayout({...l.toJson(), 'seenAt': _seenAt});
    }
  }

  bool _prune(PixelLayout l) {
    var changed = false;
    for (final f in l.folders.values.toList()) {
      for (final p in f.apps.toList()) {
        if (!_byPkg.containsKey(p)) {
          l.takeFromFolder(f.id, p);
          changed = true;
        }
      }
    }
    bool gone(String id) => id.startsWith('app:')
        ? !_byPkg.containsKey(id.substring(4))
        : id.startsWith('folder:') && !l.folders.containsKey(id.substring(7));
    for (final p in l.pages) {
      final n = p.length;
      p.removeWhere((s) => gone(s.id));
      changed |= p.length != n;
    }
    for (var i = 0; i < l.dock.length; i++) {
      final d = l.dock[i];
      if (d != null && gone(d)) {
        l.dock[i] = null;
        changed = true;
      }
    }
    return changed;
  }

  bool _fit(PixelLayout l, PixelSettings s) {
    var changed = false;
    final lost = <PixelSlot>[];
    for (final p in l.pages) {
      for (final sl in p.toList()) {
        if (sl.id == 'glance') continue;
        if (sl.r + sl.h > s.rows || sl.c + sl.w > s.cols) {
          p.remove(sl);
          lost.add(sl);
        }
      }
    }
    // PixelLayout.seed stores dock entries as bare packages; the dock holds `app:<pkg>` ids.
    for (var i = 0; i < l.dock.length; i++) {
      final d = l.dock[i];
      if (d != null && !d.contains(':')) {
        l.dock[i] = 'app:$d';
        changed = true;
      }
    }
    final want = s.dockCount;
    while (l.dock.length < want) {
      l.dock.add(null);
      changed = true;
    }
    if (!s.dockScroll && l.dock.length > want) {
      for (final d in l.dock.skip(want)) {
        if (d != null) lost.add(PixelSlot(id: d, r: 0, c: 0));
      }
      l.dock.removeRange(want, l.dock.length);
      changed = true;
    }
    for (final sl in lost) {
      final (p, r, c) = l.firstFree(
        s.rows,
        s.cols,
        w: math.min(sl.w, s.cols),
        h: math.min(sl.h, s.rows),
      );
      l.pages[p].add(
        PixelSlot(
          id: sl.id,
          r: r,
          c: c,
          w: math.min(sl.w, s.cols),
          h: math.min(sl.h, s.rows),
        ),
      );
      changed = true;
    }
    return changed;
  }

  Future<void> _save() async {
    final l = _layout;
    if (l == null) return;
    l.tidy();
    if (_page >= l.pages.length) _page = l.pages.length - 1;
    if (mounted) setState(() {});
    if (!widget.preview) {
      await prefs.setPixelLayout({...l.toJson(), 'seenAt': _seenAt});
    }
  }

  // ---- launching ----------------------------------------------------------------------------

  Future<void> _launch(String pkg) async {
    if (!await AppLock.of(prefs).gate(pkg)) return;
    prefs.recordLaunch(pkg);
    Apps.instance.launch(pkg);
  }

  void _launchByLabel(String word) {
    final a = _apps
        .where((a) => a.label.toLowerCase().contains(word))
        .firstOrNull;
    if (a != null) _launch(a.package);
  }

  // ---- drawer / search ----------------------------------------------------------------------

  void _drawerGo(double to, {bool focus = false}) {
    _drawer
        .animateTo(
          to,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (!mounted) return;
          if (to == 0) {
            _searchFocus.unfocus();
          } else if (focus) {
            _searchFocus.requestFocus();
          }
        });
  }

  void _openSearch() {
    HapticFeedback.selectionClick();
    _drawerGo(1, focus: true);
  }

  void _drawerDragStart() {
    setState(() {
      _fromDrawer = true;
      _dragging = true;
    });
    _drawerGo(0);
  }

  void _home() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _closeMenu();
    _folderKey.currentState?.close();
    if (_drawer.value > 0) _drawerGo(0);
    if (_pager.hasClients) {
      _pager.animateToPage(
        _hasPanel ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onBack() {
    if (_menuAt != null) return _closeMenu();
    if (_openFolder != null) {
      return _folderKey.currentState?.close() ??
          setState(() => _openFolder = null);
    }
    if (_drawer.value > 0) return _drawerGo(0);
    final first = _hasPanel ? 1 : 0;
    if (_pager.hasClients &&
        (_pager.page ?? first.toDouble()).round() != first) {
      _pager.animateToPage(
        first,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ---- menus --------------------------------------------------------------------------------

  void _showMenu(Offset at, List<_MenuItem> items) {
    HapticFeedback.mediumImpact();
    setState(() {
      _menuAt = at;
      _menuItems = items;
      _bigMenu = false;
    });
  }

  void _closeMenu() {
    if (_menuAt != null) setState(() => _menuAt = null);
  }

  void _homeMenu(Offset at) {
    HapticFeedback.mediumImpact();
    setState(() {
      _menuAt = at;
      _menuItems = const [];
      _bigMenu = true;
    });
  }

  void _lpDown(PointerDownEvent e) {
    _lpTimer?.cancel();
    if (widget.preview || _lpPointer != null) {
      // A second finger: not a long press.
      if (_lpPointer != null) _lpCancel();
      return;
    }
    _lpPointer = e.pointer;
    _lpAt = e.position;
    _lpTimer = Timer(const Duration(milliseconds: 420), () {
      final at = _lpAt;
      _lpTimer = null;
      if (!mounted || at == null || _menuAt != null || _dragging || _dragId != null || _openFolder != null || _drawer.value > .01 || _page < 0) return;
      final p = _local(at), g = _geo, l = _layout;
      if (l == null || p.dy < g.top - 40 || p.dy >= g.dockTop) return;
      PixelSlot? sl;
      if (p.dy >= g.top && p.dy < g.dockTop - 22) {
        sl = l.slotAt(_page, ((p.dy - g.top) / g.ch).floor().clamp(0, _s.rows - 1), ((p.dx - g.left) / g.cw).floor().clamp(0, _s.cols - 1));
      }
      if (sl != null && sl.id != 'glance') return;
      _homeMenu(at);
    });
  }

  void _lpMove(PointerMoveEvent e) {
    if (e.pointer == _lpPointer && _lpAt != null && (e.position - _lpAt!).distance > 14) _lpCancel();
  }

  void _lpCancel() {
    _lpTimer?.cancel();
    _lpTimer = null;
    _lpAt = null;
    _lpPointer = null;
  }

  void _addWidget() {
    showWidgetPicker(
      context,
      prefs: prefs,
      onAdded: (id, label) {
        final l = _layout;
        if (l == null) return;
        final s = _s;
        final w = math.min(4, s.cols), h = math.min(2, s.rows);
        final (p, r, c) = l.firstFree(s.rows, s.cols, w: w, h: h);
        l.place('widget:$id', p, r, c, w: w, h: h);
        _save();
      },
    );
  }

  // ---- drag & drop --------------------------------------------------------------------------

  Rect _iconRect(BuildContext ctx, {bool label = true}) {
    final box = ctx.findRenderObject() as RenderBox;
    final o = box.localToGlobal(Offset.zero);
    final size = _geo.icon;
    final c =
        o +
        Offset(
          box.size.width / 2,
          box.size.height / 2 - (label && _s.labels ? 9 : 0),
        );
    return Rect.fromCenter(center: c, width: size, height: size);
  }

  void _dragStart(
    String id,
    BuildContext ctx,
    AppEntry? app, {
    bool inDock = false,
  }) {
    _dragId = id;
    _fromDrawer = false;
    _fromFolderId = null;
    _dragFirst = null;
    if (app != null) {
      _popup = showPixelAppPopup(
        ctx,
        prefs: prefs,
        app: app,
        anchor: _iconRect(ctx, label: !inDock),
        onHome: true,
        onRemove: _s.lockLayout ? null : () => _remove(id),
      );
    }
  }

  void _dragUpdate(Offset pos) {
    _dragFirst ??= pos;
    if ((pos - _dragFirst!).distance > 12) {
      _popup?.close();
      _popup = null;
      if (!_dragging) setState(() => _dragging = true);
    }
  }

  void _endDrag() {
    _edgeTimer?.cancel();
    _edgeDir = 0;
    _hover.value = null;
    _fromFolderId = null;
    if (!_dragging && _dragId == null && !_fromDrawer) return;
    _layout?.tidy();
    if (mounted) {
      setState(() {
        _dragging = false;
        _fromDrawer = false;
        _dragId = null;
        _dragFirst = null;
        final n = _layout?.pages.length ?? 1;
        if (_page >= n) _page = n - 1;
      });
    }
  }

  void _remove(String id) {
    final l = _layout;
    if (l == null || _s.lockLayout) return;
    if (_fromFolderId != null && id.startsWith('app:')) {
      l.takeFromFolder(_fromFolderId!, id.substring(4));
    } else {
      l.remove(id);
    }
    HapticFeedback.selectionClick();
    _save();
  }

  Offset _pointer(DragTargetDetails<String> d) =>
      d.offset + Offset(_geo.icon / 2, _geo.icon / 2);

  Offset _local(Offset global) {
    final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  _Hit? _hitAt(Offset p) {
    final g = _geo, l = _layout;
    if (l == null) return null;
    if (p.dy >= g.dockTop - 6 && p.dy < g.dockTop + g.dockH + 6) {
      final off = _dockScroll.hasClients ? _dockScroll.offset : 0.0;
      final max =
          (_s.dockScroll
              ? math.max(l.dock.length, _s.dockCount)
              : _s.dockCount) -
          1;
      final i = ((p.dx - 8 + off) / g.dockCell).floor().clamp(0, max);
      final cx = 8 + (i + .5) * g.dockCell - off;
      return _Hit.dock(i, (p.dx - cx).abs() < g.dockCell * .3);
    }
    if (_page < 0 || p.dy < g.top || p.dy >= g.top + g.gridH) return null;
    final s = _s;
    final r = ((p.dy - g.top) / g.ch).floor().clamp(0, s.rows - 1);
    final c = ((p.dx - g.left) / g.cw).floor().clamp(0, s.cols - 1);
    final cx = g.left + (c + .5) * g.cw, cy = g.top + (r + .5) * g.ch;
    final near = (Offset(cx, cy) - p).distance < math.min(g.cw, g.ch) * .34;
    return _Hit.grid(_page, r, c, near);
  }

  void _onMove(DragTargetDetails<String> d) {
    // Only the id: the drop targets wait for the drag to actually move (_dragUpdate), like Pixel.
    if (_dragId != d.data) _dragId = d.data;
    final p = _local(_pointer(d));
    _hover.value = _hitAt(p);
    final w = _geo.w;
    final dir = p.dx < 24 ? -1 : (p.dx > w - 24 ? 1 : 0);
    if (dir == 0) {
      _edgeTimer?.cancel();
      _edgeDir = 0;
    } else if (dir != _edgeDir) {
      _edgeDir = dir;
      _edgeTimer?.cancel();
      _edgeTimer = Timer(const Duration(milliseconds: 500), _edgeStep);
    }
  }

  void _edgeStep() {
    final l = _layout;
    if (!mounted || l == null || _edgeDir == 0) return;
    final to = _page + _edgeDir;
    if (to < 0) return;
    if (to >= l.pages.length) {
      if (l.pages.length >= 8 || l.pages.last.isEmpty) return;
      l.pages.add([]);
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pager.hasClients) {
        _pager.animateToPage(
          to + (_hasPanel ? 1 : 0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
    _edgeTimer = Timer(const Duration(milliseconds: 800), _edgeStep);
  }

  void _put(PixelLayout l, String id, void Function() fn) {
    final fid = id.startsWith('folder:') ? id.substring(7) : null;
    final f = fid == null ? null : l.folders[fid];
    fn();
    if (f != null) l.folders[fid!] = f;
  }

  void _drop(DragTargetDetails<String> d) {
    final l = _layout;
    if (l == null || _s.lockLayout) return;
    final id = d.data;
    final hit = _hitAt(_local(_pointer(d)));
    if (hit == null) return;
    final s = _s;
    final fromFolder = _fromFolderId;
    // Where it comes from (for swapping).
    PixelSlot? from;
    int? fromDock;
    for (final p in l.pages) {
      for (final sl in p) {
        if (sl.id == id) from = sl;
      }
    }
    if (from == null && l.dock.contains(id)) fromDock = l.dock.indexOf(id);
    final w = from?.w ?? 1, h = from?.h ?? 1;
    if (fromFolder != null && id.startsWith('app:')) {
      l.takeFromFolder(fromFolder, id.substring(4));
      from = null;
    }
    final occ = hit.dock
        ? (hit.i < l.dock.length ? l.dock[hit.i] : null)
        : l.slotAt(hit.page, hit.r, hit.c)?.id;
    if (occ == id) return;

    void placeAtTarget(String who) => _put(l, who, () {
      if (hit.dock) {
        l.toDock(who, hit.i);
      } else {
        l.place(who, hit.page, hit.r, hit.c, w: w, h: h);
      }
    });
    void firstFree() => _put(l, id, () {
      final (p, r, c) = l.firstFree(s.rows, s.cols);
      l.place(id, p, r, c);
    });

    if (occ == null) {
      if (hit.dock ||
          l.fits(hit.page, hit.r, hit.c, w, h, s.rows, s.cols, except: id)) {
        placeAtTarget(id);
      } else {
        firstFree();
      }
    } else if (occ == 'glance' || occ.startsWith('widget:')) {
      if (from == null && fromDock == null) firstFree();
    } else if (id.startsWith('app:') &&
        hit.centre &&
        occ.startsWith('folder:')) {
      l.addToFolder(occ.substring(7), id);
    } else if (id.startsWith('app:') && hit.centre && occ.startsWith('app:')) {
      l.makeFolder(occ, id);
    } else if (from != null || fromDock != null) {
      // Swap with the occupant.
      _put(l, occ, () {
        if (fromDock != null) {
          l.toDock(occ, fromDock);
        } else {
          l.place(occ, _pageOf(l, from!), from.r, from.c);
        }
      });
      placeAtTarget(id);
    } else {
      firstFree();
    }
    HapticFeedback.selectionClick();
    _save();
  }

  int _pageOf(PixelLayout l, PixelSlot s) {
    for (var i = 0; i < l.pages.length; i++) {
      if (l.pages[i].contains(s)) return i;
    }
    return 0;
  }

  // ---- build --------------------------------------------------------------------------------

  void _geometry(Size size, EdgeInsets pad) {
    final s = _s, g = _geo;
    g.w = size.width;
    g.h = size.height;
    g.left = 12;
    g.top = pad.top + 6;
    g.cw = (g.w - g.left * 2) / s.cols;
    final bottom =
        (s.searchBar
                ? 52 + math.max(pad.bottom, 24) + 24 + 12
                : math.max(pad.bottom, 10) + 8)
            .toDouble();
    final ch0 = (g.h - bottom - 76 - 22 - g.top) / s.rows;
    final base = math.min(
      56.0,
      math.min(g.cw * .74, (ch0 - (s.labels ? 24 : 6)) * .9),
    );
    g.icon = (base * s.iconScale).clamp(24.0, g.cw * .92);
    g.dockH = g.icon + 22;
    g.dockTop = g.h - bottom - g.dockH;
    g.gridH = g.dockTop - 22 - g.top;
    g.ch = g.gridH / s.rows;
    g.dockCell = (g.w - 16) / s.dockCount;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: widget.preview,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: LayoutBuilder(
          builder: (context, c) {
            _geometry(c.biggest, mq.padding);
            final inner = Listener(
              onPointerUp: (_) => scheduleMicrotask(_afterPointer),
              onPointerCancel: (_) => scheduleMicrotask(_afterPointer),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _Wallpaper(),
                  _homeLayer(context, cs),
                  if (_openFolder != null &&
                      _layout?.folders[_openFolder] != null)
                    IgnorePointer(
                      ignoring: _fromFolderId != null,
                      child: PixelFolderOpen(
                        key: _folderKey,
                        folder: _layout!.folders[_openFolder]!,
                        apps: _byPkg,
                        from: _folderFrom,
                        shape: _s.iconShape,
                        big: _s.bigFolders,
                        labels: _s.labels,
                        iconScale: _s.iconScale,
                        locked: _s.lockLayout,
                        preview: widget.preview,
                        onClosed: () => setState(() => _openFolder = null),
                        onLaunch: (pkg) {
                          _launch(pkg);
                          Future<void>.delayed(
                            const Duration(milliseconds: 400),
                            () {
                              if (mounted) _folderKey.currentState?.close();
                            },
                          );
                        },
                        onRename: (n) {
                          _layout?.folders[_openFolder]?.name = n;
                          _save();
                        },
                        onDragOut: _folderDragOut,
                      ),
                    ),
                  if (!widget.preview) _topTargets(mq, cs),
                  if (!widget.preview) _drawerLayer(c.maxHeight),
                  if (_menuAt != null) _menuOverlay(cs, c.biggest),
                ],
              ),
            );
            return widget.preview ? IgnorePointer(child: inner) : inner;
          },
        ),
      ),
    );
  }

  void _afterPointer() {
    if (_dragging || _dragId != null || _fromDrawer) _endDrag();
  }

  void _folderDragOut(String pkg) {
    _fromFolderId = _openFolder;
    _dragId = 'app:$pkg';
    _dragFirst = null;
    setState(() => _dragging = true);
    _folderKey.currentState?.close();
  }

  Widget _drawerLayer(double h) => AnimatedBuilder(
    animation: _drawer,
    builder: (context, child) {
      final v = _drawer.value;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (v > 0)
            IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: .4 * v)),
            ),
          IgnorePointer(
            ignoring: v < .01 || _fromDrawer,
            child: Transform.translate(
              offset: Offset(0, (1 - v) * h),
              child: child,
            ),
          ),
        ],
      );
    },
    child: PixelDrawer(
      prefs: prefs,
      apps: _apps,
      onClose: () => _drawerGo(0),
      onDragStart: _drawerDragStart,
      searchFocus: _searchFocus,
    ),
  );

  // ---- home layer ---------------------------------------------------------------------------

  Widget _homeLayer(BuildContext context, ColorScheme cs) {
    final s = _s;
    return AnimatedBuilder(
      animation: _drawer,
      builder: (context, child) =>
          Opacity(opacity: 1 - .6 * _drawer.value, child: child),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _lpDown,
        onPointerMove: _lpMove,
        onPointerCancel: (_) => _lpCancel(),
        onPointerUp: (_) => _lpCancel(),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (_) {
            _drawer.stop();
            _pullDy = 0;
          },
          onVerticalDragUpdate: (d) {
            _pullDy += d.delta.dy;
            if (_pullDy < 0 && s.swipeUp == 'drawer') {
              _drawer.value = (-_pullDy / (_geo.h * .55)).clamp(0.0, 1.0);
            }
          },
          onVerticalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (_pullDy < 0) {
              if (s.swipeUp == 'search') {
                if (-_pullDy > 60 || v < -500) _openSearch();
              } else {
                _drawerGo(
                  v < -600 || (v <= 300 && _drawer.value > .3) ? 1 : 0,
                  focus: s.keyboardOnOpen,
                );
              }
            } else if (_pullDy > 40 || v > 600) {
              if (s.swipeDownShade) Apps.instance.openNotifications();
            }
            _pullDy = 0;
          },
          child: DragTarget<String>(
            onWillAcceptWithDetails: (_) => !s.lockLayout,
            onMove: _onMove,
            onLeave: (_) {
              _hover.value = null;
              _edgeTimer?.cancel();
              _edgeDir = 0;
            },
            onAcceptWithDetails: _drop,
            builder: (context, cand, rej) =>
                ValueListenableBuilder<Map<String, int>>(
                  valueListenable: Apps.instance.notifCounts,
                  builder: (context, counts, _) {
                    _counts = counts;
                    return Stack(
                      key: _areaKey,
                      fit: StackFit.expand,
                      children: [_pager_(cs), _floating(cs)],
                    );
                  },
                ),
          ),
        ),
      ),
    );
  }

  Widget _pager_(ColorScheme cs) {
    final l = _layout;
    final off = _hasPanel ? 1 : 0;
    final n = (l?.pages.length ?? 1) + off;
    return PageView.builder(
      key: ValueKey(_hasPanel),
      controller: _pager,
      itemCount: n,
      onPageChanged: (i) {
        if (!widget.preview) HapticFeedback.selectionClick();
        setState(() => _page = i - off);
      },
      itemBuilder: (context, i) {
        if (_hasPanel && i == 0) {
          return ColoredBox(
            color: Colors.black.withValues(alpha: .45),
            child: TodayPanel(
              prefs: prefs,
              apps: _apps,
              onLaunch: (a) => _launch(a.package),
              backdrop: false,
            ),
          );
        }
        return _gridPage(context, i - off);
      },
    );
  }

  Widget _gridPage(BuildContext context, int page) {
    final l = _layout;
    final s = _s, g = _geo;
    if (l == null) return const SizedBox.shrink();
    final slots = page < l.pages.length ? l.pages[page] : const <PixelSlot>[];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ValueListenableBuilder<_Hit?>(
          valueListenable: _hover,
          builder: (context, h, _) {
            if (h == null || h.dock || h.page != page) {
              return const SizedBox.shrink();
            }
            return Positioned(
              left: g.left + h.c * g.cw + 3,
              top: g.top + h.r * g.ch + 3,
              width: g.cw - 6,
              height: g.ch - 6,
              child: _highlight(h.centre),
            );
          },
        ),
        for (final sl in slots)
          Positioned(
            left: g.left + sl.c * g.cw,
            top: g.top + sl.r * g.ch,
            width: (sl.id == 'glance' ? s.cols : sl.w) * g.cw,
            height: sl.h * g.ch,
            child: _slot(context, sl),
          ),
      ],
    );
  }

  Widget _highlight(bool folder) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: folder ? .3 : .16),
      borderRadius: BorderRadius.circular(22),
    ),
  );

  Widget _slot(BuildContext context, PixelSlot sl) {
    final s = _s;
    if (sl.id == 'glance') {
      return s.glance ? _glance(context) : const SizedBox.shrink();
    }
    if (sl.id.startsWith('widget:')) return _widgetCell(sl);
    return _iconCell(sl.id);
  }

  /// An app or a folder in a home cell or a dock cell.
  Widget _iconCell(String id, {bool dock = false}) {
    final s = _s, g = _geo, l = _layout!;
    final showLabel = s.labels && !dock;
    Widget icon, feedback;
    AppEntry? app;
    VoidCallback onTap;
    if (id.startsWith('folder:')) {
      final f = l.folders[id.substring(7)];
      if (f == null) return const SizedBox.shrink();
      final dot = s.notifDots && f.apps.any((p) => (_counts[p] ?? 0) > 0);
      icon = PixelFolderIcon(
        folder: f,
        apps: _byPkg,
        size: g.icon,
        shape: s.iconShape,
        label: showLabel,
        dot: dot,
      );
      feedback = PixelFolderIcon(
        folder: f,
        apps: _byPkg,
        size: g.icon,
        shape: s.iconShape,
        label: false,
      );
      onTap = () {};
    } else {
      app = _byPkg[id.substring(4)];
      if (app == null) return const SizedBox.shrink();
      icon = PixelIcon(
        app: app,
        size: g.icon,
        shape: s.iconShape,
        label: showLabel,
        dot: s.notifDots && (_counts[app.package] ?? 0) > 0,
      );
      feedback = PixelIcon(
        app: app,
        size: g.icon,
        shape: s.iconShape,
        label: false,
      );
      final pkg = app.package;
      onTap = () => _launch(pkg);
    }
    return Builder(
      builder: (ctx) {
        if (id.startsWith('folder:')) {
          onTap = () {
            _folderFrom = _iconRect(ctx, label: showLabel);
            setState(() => _openFolder = id.substring(7));
          };
        }
        final tap = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.preview ? null : onTap,
          child: icon,
        );
        if (widget.preview) return Center(child: icon);
        if (s.lockLayout) {
          return Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onLongPress: app == null
                  ? null
                  : () => showPixelAppPopup(
                      ctx,
                      prefs: prefs,
                      app: app!,
                      anchor: _iconRect(ctx, label: showLabel),
                      onHome: true,
                    ),
              child: icon,
            ),
          );
        }
        return Center(
          child: LongPressDraggable<String>(
            data: id,
            delay: const Duration(milliseconds: 350),
            hapticFeedbackOnStart: true,
            dragAnchorStrategy: (d, c, p) => Offset(g.icon / 2, g.icon / 2),
            feedback: Transform.scale(scale: 1.1, child: feedback),
            childWhenDragging: Opacity(opacity: 0, child: icon),
            onDragStarted: () => _dragStart(id, ctx, app, inDock: dock),
            onDragUpdate: (u) => _dragUpdate(u.globalPosition),
            onDragEnd: (_) => _endDrag(),
            child: tap,
          ),
        );
      },
    );
  }

  Widget _widgetCell(PixelSlot sl) {
    final id = int.tryParse(sl.id.substring(7));
    Widget body;
    if (id == null ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        widget.preview) {
      // TODO: preview / tests draw a placeholder card; Android hosts the real app widget.
      body = DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: Icon(Icons.widgets_outlined, color: Colors.white),
        ),
      );
    } else {
      body = AndroidView(
        key: ValueKey('pixelwidget-$id'),
        viewType: 'one_launcher/appwidget',
        creationParams: {'id': id},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    // TODO: drag / resize hosted widgets; for now long-press removes.
    return Padding(
      padding: const EdgeInsets.all(6),
      child: GestureDetector(
        onLongPressStart: _s.lockLayout
            ? null
            : (d) => _showMenu(d.globalPosition, [
                _MenuItem(Icons.delete_outline_rounded, 'Remove widget', () {
                  if (id != null) Apps.instance.removeWidget(id);
                  _layout?.remove(sl.id);
                  _save();
                }),
              ]),
        child: ClipRRect(borderRadius: BorderRadius.circular(24), child: body),
      ),
    );
  }

  Widget _glance(BuildContext context) {
    final now = DateTime.now();
    final title =
        '${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}';
    String? sub;
    final b = (_event['begin'] as num?)?.toInt();
    if (_event['title'] != null && b != null) {
      final at = DateTime.fromMillisecondsSinceEpoch(b);
      sub = _event['allDay'] == true
          ? '${_event['title']}'
          : '${_event['title']} · ${_hm(at)}';
    } else if (_alarm != null) {
      sub = 'Alarm · ${_hm(_alarm!.$1)}';
    }
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.preview ? null : () => _launchByLabel('calendar'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 34,
                  height: 1.1,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  shadows: _shadow,
                ),
              ),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      shadows: _shadow,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _hm(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  // ---- dots, dock, search -------------------------------------------------------------------

  Widget _floating(ColorScheme cs) {
    final s = _s, g = _geo;
    final l = _layout;
    return AnimatedBuilder(
      animation: _pager,
      builder: (context, _) {
        var p = _hasPanel ? 1.0 : 0.0;
        if (_pager.hasClients && _pager.position.haveDimensions) {
          p = _pager.page ?? p;
        }
        final fade = _hasPanel ? p.clamp(0.0, 1.0) : 1.0;
        final cur = (p - (_hasPanel ? 1 : 0)).round();
        final n = l?.pages.length ?? 1;
        return IgnorePointer(
          ignoring: fade < .5,
          child: Opacity(
            opacity: fade,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: g.dockTop - 22,
                  height: 22,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < n; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(
                              alpha: i == cur ? 1 : .45,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                blurRadius: 3,
                                color: Color(0x33000000),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  top: g.dockTop,
                  height: g.dockH,
                  child: _dock(),
                ),
                if (s.searchBar)
                  Positioned(
                    left: 22,
                    right: 22,
                    bottom:
                        math.max(MediaQuery.of(context).padding.bottom, 24) + 24,
                    height: 52,
                    child: _searchPill(cs),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dock() {
    final l = _layout;
    if (l == null) return const SizedBox.shrink();
    final s = _s, g = _geo;
    final count = s.dockScroll
        ? math.max(l.dock.length, s.dockCount)
        : s.dockCount;
    Widget cell(int i) => SizedBox(
      width: g.dockCell,
      height: g.dockH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<_Hit?>(
              valueListenable: _hover,
              builder: (context, h, _) => h != null && h.dock && h.i == i
                  ? Padding(
                      padding: const EdgeInsets.all(3),
                      child: _highlight(h.centre),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          if (i < l.dock.length && l.dock[i] != null)
            Positioned.fill(child: _iconCell(l.dock[i]!, dock: true)),
        ],
      ),
    );
    final row = Row(children: [for (var i = 0; i < count; i++) cell(i)]);
    if (s.dockScroll && count > s.dockCount) {
      return SingleChildScrollView(
        controller: _dockScroll,
        scrollDirection: Axis.horizontal,
        child: row,
      );
    }
    return row;
  }

  Widget _searchPill(ColorScheme cs) {
    final dark = cs.brightness == Brightness.dark;
    final fg = dark ? const Color(0xFFE3E3E3) : const Color(0xFF444746);
    return Material(
      key: const Key('pixel-search'),
      color: dark ? const Color(0x9E303030) : const Color(0xB3FFFFFF),
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: widget.preview ? null : _openSearch,
        child: Padding(
          padding: const EdgeInsets.only(left: 18, right: 16),
          child: Row(
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(
                  colors: [
                    Color(0xFF4285F4),
                    Color(0xFFEA4335),
                    Color(0xFFFBBC05),
                    Color(0xFF34A853),
                  ],
                  stops: [.1, .4, .65, .9],
                ).createShader(r),
                child: const Text(
                  'G',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              const Spacer(),
              // AI Mode: a search glass with a sparkle.
              SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.search_rounded, color: fg, size: 28),
                    Positioned(right: -3, top: -4, child: Icon(Icons.auto_awesome, color: fg, size: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Icon(Icons.mic_none_rounded, color: fg, size: 28),
              const SizedBox(width: 20),
              // TODO: Google Lens glyph; the focus frame stands in.
              Icon(Icons.center_focus_strong_outlined, color: fg, size: 28),
            ],
          ),
        ),
      ),
    );
  }

  // ---- drop targets on top & menu ------------------------------------------------------------

  Widget _topTargets(MediaQueryData mq, ColorScheme cs) {
    final id = _dragId;
    final isApp = id == null || id.startsWith('app:');
    final pkg = id != null && id.startsWith('app:') ? id.substring(4) : null;
    final system = pkg != null && (_byPkg[pkg]?.system ?? false);
    final s = _s;
    final items =
        <(IconData, String, bool Function(String), void Function(String))>[
          if (!_fromDrawer && !s.lockLayout)
            (Icons.close_rounded, 'Remove', (_) => true, _remove),
          if (isApp)
            (
              Icons.info_outline_rounded,
              'App info',
              (d) => d.startsWith('app:'),
              (d) => Apps.instance.appInfo(d.substring(4)),
            ),
          if (isApp && !system)
            (
              Icons.delete_outline_rounded,
              'Uninstall',
              (d) =>
                  d.startsWith('app:') &&
                  !(_byPkg[d.substring(4)]?.system ?? true),
              (d) => Apps.instance.uninstall(d.substring(4)),
            ),
        ];
    return Positioned(
      top: mq.padding.top + 10,
      left: 12,
      right: 12,
      child: IgnorePointer(
        ignoring: !_dragging,
        child: AnimatedOpacity(
          opacity: _dragging ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (final (icon, label, ok, act) in items)
                DragTarget<String>(
                  onWillAcceptWithDetails: (d) => ok(d.data),
                  onAcceptWithDetails: (d) {
                    act(d.data);
                    HapticFeedback.selectionClick();
                  },
                  builder: (context, cand, rej) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cand.isNotEmpty
                          ? cs.primaryContainer
                          : cs.surfaceContainerHigh.withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: cs.onSurface),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(fontSize: 13, color: cs.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigMenuOverlay(ColorScheme cs, Size size) {
    final dark = cs.brightness == Brightness.dark;
    final fg = dark ? Colors.white : cs.onSurface;
    final thumb = prefs.wallpaperPhoto == null ? null : photoFile(prefs.wallpaperPhoto!);
    Widget row(IconData icon, String label, VoidCallback onTap) => InkWell(
      onTap: () {
        _closeMenu();
        onTap();
      },
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 24, color: fg),
              const SizedBox(width: 18),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: fg))),
            ],
          ),
        ),
      ),
    );
    final bottom = (_geo.dockTop - 4).clamp(0.0, size.height).toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(behavior: HitTestBehavior.opaque, onTap: _closeMenu, onLongPress: _closeMenu),
        Positioned(
          left: 19,
          right: 19,
          bottom: size.height - bottom,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .9, end: 1),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            builder: (context, t, child) => Opacity(
              opacity: ((t - .9) / .1).clamp(0, 1),
              child: Transform.scale(scale: t, alignment: Alignment.bottomCenter, child: child),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: ColoredBox(
                  color: dark ? const Color(0xD9464646) : const Color(0xE6F3EDF7),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        row(Icons.palette_outlined, 'Wallpaper and style', () => Apps.instance.openWallpaperPicker()),
                        if (thumb != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                            child: SizedBox(
                              height: 84,
                              width: double.infinity,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(32),
                                      child: Image(image: thumb, fit: BoxFit.cover),
                                    ),
                                  ),
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xCCB0B0B0)),
                                    child: const Icon(Icons.check_rounded, color: Color(0xFF303030)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        row(Icons.widgets_outlined, 'Widgets', _addWidget),
                        row(Icons.apps_rounded, 'Apps list', () => _drawerGo(1, focus: _s.keyboardOnOpen)),
                        row(Icons.settings_outlined, 'Home settings', () => showPixelHomeSettings(context, prefs: prefs)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuOverlay(ColorScheme cs, Size size) {
    if (_bigMenu) return _bigMenuOverlay(cs, size);
    final at = _menuAt!;
    const w = 232.0;
    final h = _menuItems.length * 52.0 + 16;
    final left = (at.dx - w / 2)
        .clamp(12.0, math.max(12.0, size.width - w - 12))
        .toDouble();
    final top = (at.dy - h - 12 < 40 ? at.dy + 12 : at.dy - h - 12)
        .clamp(40.0, math.max(40.0, size.height - h - 24))
        .toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _closeMenu,
          onLongPress: _closeMenu,
        ),
        Positioned(
          left: left,
          top: top,
          width: w,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .85, end: 1),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            builder: (context, t, child) => Opacity(
              opacity: ((t - .85) / .15).clamp(0, 1),
              child: Transform.scale(scale: t, child: child),
            ),
            child: Material(
              color: cs.surfaceContainerHigh,
              elevation: 6,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final it in _menuItems)
                      InkWell(
                        onTap: () {
                          _closeMenu();
                          it.onTap();
                        },
                        child: SizedBox(
                          height: 52,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Icon(it.icon, size: 22, color: cs.onSurface),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    it.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The photo wallpaper (when the user set one; else the system wallpaper shows through), with
/// soft shades top and bottom so white text and the dock read on any picture.
class _Wallpaper extends StatelessWidget {
  const _Wallpaper();
  @override
  Widget build(BuildContext context) {
    final home = context.findAncestorStateOfType<_PixelHomeState>()!;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoWallpaper(prefs: home.prefs, fullScreen: true),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x40000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x40000000),
                ],
                stops: [0, .22, .7, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
