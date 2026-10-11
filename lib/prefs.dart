import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything the user customises, saved on the phone.
class Prefs extends ChangeNotifier {
  Prefs._(this._sp);
  final SharedPreferences _sp;

  static Future<Prefs> load() async => Prefs._(await SharedPreferences.getInstance());

  static const maxFavourites = 7;

  List<String> get favourites => _sp.getStringList('favourites') ?? const [];
  List<String> get hidden => _sp.getStringList('hidden') ?? const [];
  bool get showHomeIcons => _sp.getBool('showHomeIcons') ?? false;
  bool get autoOpenSingleMatch => _sp.getBool('autoOpenSingleMatch') ?? true;

  /// How often each app was opened from One Launcher.
  Map<String, int> get launchCounts => Map<String, int>.from(jsonDecode(_sp.getString('launchCounts') ?? '{}') as Map);

  /// Folders the user picked by hand (package → folder id).
  Map<String, String> get folderOverrides => Map<String, String>.from(jsonDecode(_sp.getString('folderOverrides') ?? '{}') as Map);

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

  Future<void> moveFavourite(String pkg, int by) {
    final list = [...favourites];
    final i = list.indexOf(pkg);
    final j = (i + by).clamp(0, list.length - 1);
    if (i < 0 || i == j) return Future.value();
    list
      ..removeAt(i)
      ..insert(j, pkg);
    return _setList('favourites', list);
  }

  Future<void> toggleHidden(String pkg) {
    final list = [...hidden];
    list.contains(pkg) ? list.remove(pkg) : list.add(pkg);
    return _setList('hidden', list);
  }

  Future<void> setShowHomeIcons(bool v) async {
    await _sp.setBool('showHomeIcons', v);
    notifyListeners();
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
