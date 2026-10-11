import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'folders.dart';

/// Everything the user customises, saved on the phone.
class Prefs extends ChangeNotifier {
  Prefs._(this._sp);
  final SharedPreferences _sp;

  static Future<Prefs> load() async {
    final sp = await SharedPreferences.getInstance();
    // One-time: switch the new "Just wallpaper" page on for people who already chose pages.
    if (!sp.containsKey('blankAdded')) {
      final on = sp.getStringList('topEnabled');
      if (on != null && !on.contains('blank')) await sp.setStringList('topEnabled', [...on, 'blank']);
      await sp.setBool('blankAdded', true);
    }
    return Prefs._(sp);
  }

  static const maxFavourites = 16; // pinned apps lead the green card (2 pages × 8)

  // ---- Speed: JSON settings are parsed once and kept until something changes ----
  final _parsed = <String, Map>{};
  Map _json(String key) => _parsed.putIfAbsent(key, () => jsonDecode(_sp.getString(key) ?? '{}') as Map);

  /// Bumps on every change; lets callers cache work derived from settings.
  int get version => _version;
  int _version = 0;

  @override
  void notifyListeners() {
    _parsed.clear();
    _version++;
    super.notifyListeners();
  }

  List<String> get favourites => _sp.getStringList('favourites') ?? const [];
  List<String> get hidden => _sp.getStringList('hidden') ?? const [];
  bool get autoOpenSingleMatch => _sp.getBool('autoOpenSingleMatch') ?? true;

  /// How often each app was opened from One Launcher.
  Map<String, int> get launchCounts => Map<String, int>.from(_json('launchCounts'));

  /// Folders the user picked by hand (package → folder id).
  Map<String, String> get folderOverrides => Map<String, String>.from(_json('folderOverrides'));

  /// Folder names the user typed (folder id → name).
  Map<String, String> get folderNames => Map<String, String>.from(_json('folderNames'));

  /// Folder order the user set (ids, top to bottom). Empty = default order.
  List<String> get folderOrder => _sp.getStringList('folderOrder') ?? const [];

  String folderName(Folder f) => folderNames[f.id] ?? f.name;

  Future<void> renameFolder(String id, String? name) async {
    final m = folderNames;
    (name == null || name.trim().isEmpty) ? m.remove(id) : m[id] = name.trim();
    await _sp.setString('folderNames', jsonEncode(m));
    notifyListeners();
  }

  Future<void> setFolderOrder(List<String> ids) => _setList('folderOrder', ids);

  /// Back to automatic: default name, and apps the user moved in go back to their own folders.
  Future<void> resetFolder(String id) async {
    final names = folderNames..remove(id);
    final overrides = folderOverrides..removeWhere((_, f) => f == id);
    await _sp.setString('folderNames', jsonEncode(names));
    await _sp.setString('folderOverrides', jsonEncode(overrides));
    notifyListeners();
  }

  /// Top carousel pages, in order, and which are switched on.
  static const topDefaultOrder = ['clock', 'screen_time', 'battery', 'up_next', 'blank'];
  List<String> get topOrder {
    final saved = _sp.getStringList('topOrder') ?? const [];
    bool known(String id) => topDefaultOrder.contains(id) || (id.startsWith('widget:') && widgetLabels.containsKey(id));
    return [...saved.where(known), ...topDefaultOrder.where((id) => !saved.contains(id))];
  }

  Set<String> get topEnabled => (_sp.getStringList('topEnabled') ?? const ['clock', 'screen_time', 'blank']).toSet();
  List<String> get topPages => [
    for (final id in topOrder)
      if (topEnabled.contains(id)) id,
  ];

  Future<void> setTopOrder(List<String> ids) => _setList('topOrder', ids);

  /// App widget pages (`widget:<id>`) and their names.
  Map<String, String> get widgetLabels => Map<String, String>.from(_json('widgetLabels'));

  /// Adds an app widget as a page (before "Just wallpaper") and switches it on.
  Future<void> addWidgetPage(int id, String label) async {
    final key = 'widget:$id';
    await _sp.setString('widgetLabels', jsonEncode(widgetLabels..[key] = label));
    _parsed.remove('widgetLabels');
    // Keep "Just wallpaper" as the last page: new widgets go just before it.
    final order = topOrder.where((x) => x != key).toList();
    final blank = order.indexOf('blank');
    blank < 0 ? order.add(key) : order.insert(blank, key);
    await _sp.setStringList('topOrder', order);
    await _sp.setStringList('topEnabled', {...topEnabled, key}.toList());
    notifyListeners();
  }

  Future<void> removeWidgetPage(String key) async {
    await _sp.setString('widgetLabels', jsonEncode(widgetLabels..remove(key)));
    await _sp.setStringList('topOrder', topOrder.where((x) => x != key).toList());
    final on = topEnabled..remove(key);
    await _sp.setStringList('topEnabled', on.isEmpty ? ['clock'] : on.toList());
    notifyListeners();
  }

  Future<void> setTopEnabled(String id, bool on) {
    final set = topEnabled;
    on ? set.add(id) : set.remove(id);
    if (set.isEmpty) return Future.value(); // keep at least one page
    return _setList('topEnabled', set.toList());
  }

  /// Share of the screen for the top widgets; the app sheet rests on the rest.
  static const topShareMin = 0.20, topShareMax = 0.50;
  double get topShare => (_sp.getDouble('topShare') ?? 0.25).clamp(topShareMin, topShareMax);
  Future<void> setTopShare(double v) async {
    await _sp.setDouble('topShare', v.clamp(topShareMin, topShareMax));
    notifyListeners();
  }

  /// Typeface for the big figures in the top half (see top/header_fonts.dart).
  String get headerFont => _sp.getString('headerFont') ?? 'condensed';
  Future<void> setHeaderFont(String id) async {
    await _sp.setString('headerFont', id);
    notifyListeners();
  }

  /// Extra breathing room around the top widgets (pt).
  static const topPaddingMax = 40.0;
  double get topPadding => (_sp.getDouble('topPadding') ?? 16).clamp(0, topPaddingMax);
  Future<void> setTopPadding(double v) async {
    await _sp.setDouble('topPadding', v.clamp(0, topPaddingMax));
    notifyListeners();
  }

  /// Colours & style: 'system' (Material You), 'basic' (one of 8 colours) or 'original'.
  String get themeSource => _sp.getString('themeSource') ?? 'system';
  int get themeSeed => _sp.getInt('themeSeed') ?? 0xFF4285F4;
  String get themeStyle => _sp.getString('themeStyle') ?? 'tonal';
  Future<void> setTheme({String? source, int? seed, String? style}) async {
    if (source != null) await _sp.setString('themeSource', source);
    if (seed != null) await _sp.setInt('themeSeed', seed);
    if (style != null) await _sp.setString('themeStyle', style);
    notifyListeners();
  }

  Future<void> unpinAll() => _setList('favourites', []);

  Future<void> clearLaunches() async {
    await _sp.remove('launchCounts');
    notifyListeners();
  }

  Future<void> recordLaunch(String pkg) async {
    final m = launchCounts;
    m[pkg] = (m[pkg] ?? 0) + 1;
    await _sp.setString('launchCounts', jsonEncode(m));
    notifyListeners();
  }

  Future<void> setFolder(String pkg, String? folderId) async {
    final m = folderOverrides;
    folderId == null ? m.remove(pkg) : m[pkg] = folderId;
    await _sp.setString('folderOverrides', jsonEncode(m));
    notifyListeners();
  }

  bool isFavourite(String pkg) => favourites.contains(pkg);
  bool get favouritesFull => favourites.length >= maxFavourites;

  Future<void> toggleFavourite(String pkg) {
    final list = [...favourites];
    list.contains(pkg) ? list.remove(pkg) : list.add(pkg);
    return _setList('favourites', list);
  }

  Future<void> toggleHidden(String pkg) {
    final list = [...hidden];
    list.contains(pkg) ? list.remove(pkg) : list.add(pkg);
    return _setList('hidden', list);
  }

  Future<void> setAutoOpenSingleMatch(bool v) async {
    await _sp.setBool('autoOpenSingleMatch', v);
    notifyListeners();
  }

  Future<void> _setList(String key, List<String> v) async {
    await _sp.setStringList(key, v);
    notifyListeners();
  }
}
