import '../prefs.dart';

/// Pixel view's data: its settings and its home layout, kept in [Prefs.pixelSettings] /
/// [Prefs.pixelLayout] as JSON. Pure Dart: the screens (pixel_home, pixel_drawer, pixel_popup,
/// pixel_settings) read these and write back through [PixelSettings.save] / [PixelLayout.save].

/// Grid presets, like Pixel Launcher's "App grid" (plus the bigger ones people ask for).
const pixelGrids = <String, (int, int)>{
  '4x4': (4, 4),
  '4x5': (4, 5),
  '5x5': (5, 5),
  '5x6': (5, 6),
  '6x7': (6, 7),
};

/// Icon shapes (Pixel's "Wallpaper & style → Icon shape", Android 16 QPR2).
const pixelShapes = ['circle', 'squircle', 'square', 'arch', 'clover', 'scallop'];

class PixelSettings {
  PixelSettings(this._m);
  factory PixelSettings.of(Prefs p) => PixelSettings(p.pixelSettings);
  final Map<String, dynamic> _m;

  T _get<T>(String k, T fallback) => _m[k] is T ? _m[k] as T : fallback;
  PixelSettings copyWith(String key, Object? value) =>
      PixelSettings({..._m, key: value});
  Future<void> save(Prefs p) => p.setPixelSettings(_m);
  Map<String, dynamic> toJson() => Map.of(_m);

  // ---- grid & icons ----
  /// Home grid, a [pixelGrids] key (5x5, like Pixel Launcher on this size of phone).
  String get grid => _get('grid', '5x5');
  int get cols => (pixelGrids[grid] ?? (4, 5)).$1;
  int get rows => (pixelGrids[grid] ?? (4, 5)).$2;

  /// Icon size, 0.7..1.3 of the grid's natural size.
  double get iconScale => (_get<num>('iconScale', 1)).toDouble().clamp(.7, 1.3);
  String get iconShape => _get('iconShape', 'circle');
  bool get labels => _get('labels', true); // home icon labels
  bool get drawerLabels => _get('drawerLabels', true);
  bool get notifDots => _get('notifDots', true);

  // ---- home ----
  bool get glance => _get('glance', true); // At a Glance, top-left
  bool get searchBar => _get('searchBar', true); // bottom search pill (G · mic · Lens)
  /// Icons in the dock (Pixel: 5; 4–6), scrolls sideways when [dockScroll] and it holds more.
  int get dockCount => _get<num>('dockCount', 5).toInt().clamp(3, 7);
  bool get dockScroll => _get('dockScroll', false);
  bool get addNewApps => _get('addNewApps', true); // new installs land on home
  bool get lockLayout => _get('lockLayout', false); // no drags / removals on home
  /// Big folders: open a folder full screen with a bigger grid.
  bool get bigFolders => _get('bigFolders', false);

  // ---- gestures ----
  bool get doubleTapSleep => _get('doubleTapSleep', true);
  bool get swipeDownShade => _get('swipeDownShade', true); // swipe down on home → notifications
  /// What a swipe up does: 'drawer' (Pixel) or 'search'.
  String get swipeUp => _get('swipeUp', 'drawer');
  /// Today panel to the left of page 1 (Pixel's Discover spot).
  bool get leftPanel => _get('leftPanel', true);

  // ---- drawer ----
  bool get suggestions => _get('suggestions', true); // suggested row on top
  /// 'az' (Pixel) | 'recent' | 'most'.
  String get drawerSort => _get('drawerSort', 'az');
  int get drawerCols => _get<num>('drawerCols', cols).toInt().clamp(4, 6);
  bool get keyboardOnOpen => _get('keyboardOnOpen', false);
  bool get letterScroller => _get('letterScroller', true);
}

/// One thing on a home page: an app, a folder, At a Glance or a hosted widget, at a cell.
class PixelSlot {
  PixelSlot({required this.id, required this.r, required this.c, this.w = 1, this.h = 1});
  factory PixelSlot.fromJson(Map m) => PixelSlot(
    id: m['id'] as String,
    r: (m['r'] as num).toInt(),
    c: (m['c'] as num).toInt(),
    w: (m['w'] as num?)?.toInt() ?? 1,
    h: (m['h'] as num?)?.toInt() ?? 1,
  );

  /// `app:<package>`, `folder:<folderId>`, `glance`, `widget:<appWidgetId>`.
  final String id;
  final int r, c, w, h;

  PixelSlot at(int r, int c) => PixelSlot(id: id, r: r, c: c, w: w, h: h);
  PixelSlot sized(int w, int h) => PixelSlot(id: id, r: r, c: c, w: w, h: h);
  bool covers(int row, int col) => row >= r && row < r + h && col >= c && col < c + w;
  Map<String, dynamic> toJson() => {'id': id, 'r': r, 'c': c, if (w != 1) 'w': w, if (h != 1) 'h': h};
}

class PixelFolder {
  PixelFolder({required this.id, required this.name, required this.apps});
  factory PixelFolder.fromJson(String id, Map m) => PixelFolder(
    id: id,
    name: m['name'] as String? ?? '',
    apps: List<String>.from(m['apps'] as List? ?? const []),
  );
  final String id;
  String name;

  /// Packages, in order; the first 4 show in the closed folder's preview (2x2, like Pixel).
  final List<String> apps;
  Map<String, dynamic> toJson() => {'name': name, 'apps': apps};
}

/// Home pages, the dock and folders. Mutable: change, then [save].
class PixelLayout {
  PixelLayout({required this.pages, required this.dock, required this.folders});

  factory PixelLayout.fromJson(Map<String, dynamic> m) => PixelLayout(
    pages: [
      for (final p in (m['pages'] as List? ?? const []))
        [for (final s in p as List) PixelSlot.fromJson(s as Map)],
    ],
    dock: [for (final d in (m['dock'] as List? ?? const [])) d as String?],
    folders: {
      for (final e in (m['folders'] as Map? ?? const {}).entries)
        e.key as String: PixelFolder.fromJson(e.key as String, e.value as Map),
    },
  );

  /// The saved layout, or null on first open (then [seed]).
  static PixelLayout? of(Prefs p) {
    final m = p.pixelLayout;
    return m.isEmpty ? null : PixelLayout.fromJson(m);
  }

  /// First open: At a Glance on page 1, the dock from favourites (or the first apps), the
  /// rest of the favourites on page 1's bottom row — like a fresh Pixel.
  factory PixelLayout.seed({required List<String> favourites, required List<String> apps, required PixelSettings s}) {
    final pool = [...favourites, ...apps.where((a) => !favourites.contains(a))];
    final dock = pool.take(s.dockCount).toList();
    final rest = pool.skip(dock.length).take(s.cols).toList();
    return PixelLayout(
      pages: [
        [
          PixelSlot(id: 'glance', r: 0, c: 0, w: s.cols, h: 1),
          for (var i = 0; i < rest.length; i++) PixelSlot(id: 'app:${rest[i]}', r: s.rows - 1, c: i),
        ],
      ],
      dock: [for (final d in dock) 'app:$d', for (var i = dock.length; i < s.dockCount; i++) null],
      folders: {},
    );
  }

  final List<List<PixelSlot>> pages;
  final List<String?> dock; // `app:<pkg>` / `folder:<id>` / null (empty spot)
  final Map<String, PixelFolder> folders;

  Map<String, dynamic> toJson() => {
    'pages': [for (final p in pages) [for (final s in p) s.toJson()]],
    'dock': dock,
    'folders': {for (final e in folders.entries) e.key: e.value.toJson()},
  };
  Future<void> save(Prefs p) => p.setPixelLayout(toJson());

  PixelSlot? slotAt(int page, int r, int c) =>
      page < pages.length ? pages[page].where((s) => s.covers(r, c)).firstOrNull : null;

  /// Is [r],[c] (w×h) free on [page], ignoring [except]?
  bool fits(int page, int r, int c, int w, int h, int rows, int cols, {String? except}) {
    if (r < 0 || c < 0 || r + h > rows || c + w > cols) return false;
    if (page >= pages.length) return true;
    for (final s in pages[page]) {
      if (s.id == except) continue;
      final overlap = r < s.r + s.h && s.r < r + h && c < s.c + s.w && s.c < c + w;
      if (overlap) return false;
    }
    return true;
  }

  /// First free cell for a w×h item, page by page; adds a page when all are full.
  (int, int, int) firstFree(int rows, int cols, {int w = 1, int h = 1, int fromPage = 0}) {
    for (var p = fromPage; p < pages.length; p++) {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          if (fits(p, r, c, w, h, rows, cols)) return (p, r, c);
        }
      }
    }
    pages.add([]);
    return (pages.length - 1, 0, 0);
  }

  /// Is [id] on a home page or in the dock?
  bool contains(String id) =>
      pages.any((p) => p.any((s) => s.id == id)) || dock.contains(id);

  /// Every package on home, dock or in a folder.
  Set<String> get placedApps => {
    for (final p in pages)
      for (final s in p)
        if (s.id.startsWith('app:')) s.id.substring(4),
    for (final d in dock)
      if (d != null && d.startsWith('app:')) d.substring(4),
    for (final f in folders.values) ...f.apps,
  };

  /// Takes [id] off home and the dock (not out of folders).
  void remove(String id) {
    for (final p in pages) {
      p.removeWhere((s) => s.id == id);
    }
    for (var i = 0; i < dock.length; i++) {
      if (dock[i] == id) dock[i] = null;
    }
    if (id.startsWith('folder:')) folders.remove(id.substring(7));
  }

  /// Puts [id] on [page] at r,c (moves it if it's already somewhere).
  void place(String id, int page, int r, int c, {int w = 1, int h = 1}) {
    remove(id);
    while (pages.length <= page) {
      pages.add([]);
    }
    pages[page].add(PixelSlot(id: id, r: r, c: c, w: w, h: h));
  }

  void toDock(String id, int index) {
    remove(id);
    while (dock.length <= index) {
      dock.add(null);
    }
    dock[index] = id;
  }

  /// Drop app [dragged] on app [target]: a new folder where [target] was (Pixel's
  /// drag-onto-app). Returns the folder id.
  String makeFolder(String target, String dragged, {String name = ''}) {
    final id = 'f${DateTime.now().microsecondsSinceEpoch}';
    folders[id] = PixelFolder(id: id, name: name, apps: [_pkg(target), _pkg(dragged)]);
    remove(dragged);
    _swap(target, 'folder:$id');
    return id;
  }

  void addToFolder(String folderId, String app) {
    remove(app);
    final f = folders[folderId];
    if (f != null && !f.apps.contains(_pkg(app))) f.apps.add(_pkg(app));
  }

  /// Takes [pkg] out of a folder; a folder left with one app turns back into that app.
  void takeFromFolder(String folderId, String pkg) {
    final f = folders[folderId];
    if (f == null) return;
    f.apps.remove(pkg);
    if (f.apps.length == 1) _swap('folder:$folderId', 'app:${f.apps.first}');
    if (f.apps.length <= 1) folders.remove(folderId);
  }

  /// Drops empty trailing pages (never page 1).
  void tidy() {
    while (pages.length > 1 && pages.last.isEmpty) {
      pages.removeLast();
    }
  }

  void _swap(String from, String to) {
    for (final p in pages) {
      for (var i = 0; i < p.length; i++) {
        if (p[i].id == from) p[i] = PixelSlot(id: to, r: p[i].r, c: p[i].c, w: p[i].w, h: p[i].h);
      }
    }
    for (var i = 0; i < dock.length; i++) {
      if (dock[i] == from) dock[i] = to;
    }
  }

  static String _pkg(String id) => id.startsWith('app:') ? id.substring(4) : id;
}
