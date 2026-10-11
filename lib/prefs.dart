import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'folders.dart';

/// Everything the user customises, saved on the phone.
class Prefs extends ChangeNotifier {
  Prefs._(this._sp);
  final SharedPreferences _sp;

  static Future<Prefs> load() async => Prefs._(await SharedPreferences.getInstance());

  static const maxFavourites = 8; // pinned apps lead the green card (it shows 8 apps)

  List<String> get favourites => _sp.getStringList('favourites') ?? const [];
  List<String> get hidden => _sp.getStringList('hidden') ?? const [];
  bool get autoOpenSingleMatch => _sp.getBool('autoOpenSingleMatch') ?? true;

  /// How often each app was opened from One Launcher.
  Map<String, int> get launchCounts => Map<String, int>.from(jsonDecode(_sp.getString('launchCounts') ?? '{}') as Map);

  /// Folders the user picked by hand (package → folder id).
  Map<String, String> get folderOverrides => Map<String, String>.from(jsonDecode(_sp.getString('folderOverrides') ?? '{}') as Map);

  /// Folder names the user typed (folder id → name).
  Map<String, String> get folderNames => Map<String, String>.from(jsonDecode(_sp.getString('folderNames') ?? '{}') as Map);

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
  static const topDefaultOrder = ['clock', 'screen_time', 'battery', 'up_next'];
  List<String> get topOrder {
    final saved = _sp.getStringList('topOrder') ?? const [];
    return [...saved.where(topDefaultOrder.contains), ...topDefaultOrder.where((id) => !saved.contains(id))];
  }

  Set<String> get topEnabled => (_sp.getStringList('topEnabled') ?? const ['clock', 'screen_time']).toSet();
  List<String> get topPages => [
    for (final id in topOrder)
      if (topEnabled.contains(id)) id,
  ];

  Future<void> setTopOrder(List<String> ids) => _setList('topOrder', ids);
  Future<void> setTopEnabled(String id, bool on) {
    final set = topEnabled;
    on ? set.add(id) : set.remove(id);
    if (set.isEmpty) return Future.value(); // keep at least one page
    return _setList('topEnabled', set.toList());
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
