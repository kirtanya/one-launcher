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
    // One-time: switch "Now playing" on (just before "Just wallpaper") for existing setups.
    if (!sp.containsKey('nowPlayingAdded')) {
      final on = sp.getStringList('topEnabled');
      if (on != null && !on.contains('now_playing')) await sp.setStringList('topEnabled', [...on, 'now_playing']);
      final order = sp.getStringList('topOrder');
      if (order != null && !order.contains('now_playing')) {
        final b = order.indexOf('blank');
        await sp.setStringList('topOrder', [...order]..insert(b < 0 ? order.length : b, 'now_playing'));
      }
      await sp.setBool('nowPlayingAdded', true);
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
  static const topDefaultOrder = ['clock', 'screen_time', 'battery', 'up_next', 'now_playing', 'blank'];
  List<String> get topOrder {
    final saved = _sp.getStringList('topOrder') ?? const [];
    bool known(String id) => topDefaultOrder.contains(id) || (id.startsWith('widget:') && widgetLabels.containsKey(id));
    return [...saved.where(known), ...topDefaultOrder.where((id) => !saved.contains(id))];
  }

  Set<String> get topEnabled => (_sp.getStringList('topEnabled') ?? const ['clock', 'screen_time', 'now_playing', 'blank']).toSet();
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

  /// Clock style (variable font axes): weight 100–1000, width 25–151, slant −10…0.
  double get clockWeight => _sp.getDouble('clockWeight') ?? 300;
  double get clockWidth => _sp.getDouble('clockWidth') ?? 25;
  double get clockSlant => _sp.getDouble('clockSlant') ?? 0;
  double get clockRound => _sp.getDouble('clockRound') ?? 0; // 0 sharp … 100 fully rounded
  Future<void> setClockStyle({double? weight, double? width, double? slant, double? round}) async {
    if (round != null) await _sp.setDouble('clockRound', round.clamp(0, 100));
    if (weight != null) await _sp.setDouble('clockWeight', weight.clamp(100, 1000));
    if (width != null) await _sp.setDouble('clockWidth', width.clamp(25, 151));
    if (slant != null) await _sp.setDouble('clockSlant', slant.clamp(-10, 0));
    notifyListeners();
  }

  /// How the quick-action chips look (colour, opacity, shape, size, content, outline) — see ChipLook.
  Map get chipLook => _json('chipLook');
  Future<void> setChipLook(Map<String, Object> look) async {
    final saving = _sp.setString('chipLook', jsonEncode(look)); // memory updates at once
    _parsed.remove('chipLook'); // so a quick second change builds on this one
    await saving;
    notifyListeners();
  }

  /// Own photo as the launcher background (a file in app storage), or null = phone wallpaper.
  String? get wallpaperPhoto => _sp.getString('wallpaperPhoto');

  Future<void> setWallpaperPhoto(String? path) async {
    if (path == null) {
      await _sp.remove('wallpaperPhoto');
    } else {
      await _sp.setString('wallpaperPhoto', path);
      await setPhotoFrame(zoom: 1, x: 0, y: 0); // a new photo starts centred
    }
    notifyListeners();
  }

  /// How the photo sits on screen: zoom 1–3, position −1…1 on each axis (which part shows
  /// when zoomed / cropped), blur 0–24.
  double get photoZoom => (_sp.getDouble('photoZoom') ?? 1).clamp(1, 3);
  double get photoX => (_sp.getDouble('photoX') ?? 0).clamp(-1, 1);
  double get photoY => (_sp.getDouble('photoY') ?? 0).clamp(-1, 1);
  double get photoBlur => (_sp.getDouble('photoBlur') ?? 0).clamp(0, 24);
  Future<void> setPhotoFrame({double? zoom, double? x, double? y, double? blur}) async {
    if (zoom != null) await _sp.setDouble('photoZoom', zoom.clamp(1, 3));
    if (x != null) await _sp.setDouble('photoX', x.clamp(-1, 1));
    if (y != null) await _sp.setDouble('photoY', y.clamp(-1, 1));
    if (blur != null) await _sp.setDouble('photoBlur', blur.clamp(0, 24));
    notifyListeners();
  }

  /// Black over the wallpaper (0 = off … 0.6), for legibility of everything on it.
  double get wallpaperDim => (_sp.getDouble('wallpaperDim') ?? 0.2).clamp(0, .6);
  Future<void> setWallpaperDim(double v) async {
    await _sp.setDouble('wallpaperDim', v.clamp(0, .6));
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

  /// Cards: 'light', 'dark', or 'auto' (follow the phone's dark theme).
  String get cardStyle => _sp.getString('cardStyle') ?? 'light';
  Future<void> setCardStyle(String v) async {
    await _sp.setString('cardStyle', v);
    notifyListeners();
  }

  Future<void> setTheme({String? source, int? seed, String? style}) async {
    if (source != null) await _sp.setString('themeSource', source);
    if (seed != null) await _sp.setInt('themeSeed', seed);
    if (style != null) await _sp.setString('themeStyle', style);
    notifyListeners();
  }

  // ---- Backup & restore -----------------------------------------------------------

  static const _backupFormat = 1;

  /// Everything the user set, as a JSON file. App widgets are left out: Android ties them to
  /// the phone they were added on, so they can't be restored elsewhere.
  static const _phoneOnly = {'widgetLabels', 'installId', 'wallpaperPhoto', 'slowFrames', 'tvHost', 'tvName'};

  String exportBackup() {
    final out = <String, Object>{};
    for (final k in _sp.getKeys()) {
      if (_phoneOnly.contains(k)) continue; // phone-specific
      final v = _sp.get(k);
      out[k] = switch (v) {
        final String s => {'t': 's', 'v': s},
        final bool b => {'t': 'b', 'v': b},
        final int i => {'t': 'i', 'v': i},
        final double d => {'t': 'd', 'v': d},
        final List l => {
          't': 'l',
          'v': [
            for (final x in l)
              if (!(x as String).startsWith('widget:')) x,
          ],
        },
        _ => {'t': 's', 'v': '$v'},
      };
    }
    return const JsonEncoder.withIndent('  ')
        .convert({'app': 'One Launcher', 'format': _backupFormat, 'created': DateTime.now().toIso8601String(), 'settings': out});
  }

  /// Replaces all settings with the backup's. Widgets on this phone are kept as they are.
  /// Returns how many settings were restored; throws [FormatException] for a wrong file.
  Future<int> importBackup(String text) async {
    final data = jsonDecode(text);
    if (data is! Map || data['app'] != 'One Launcher' || data['settings'] is! Map) {
      throw const FormatException('Not a One Launcher backup');
    }
    if ((data['format'] as num? ?? 0) > _backupFormat) throw const FormatException('Backup is from a newer version');

    // Keep what belongs to this phone: its widget pages and its install id.
    final id = installId;
    final labels = widgetLabels;
    final widgetOrder = topOrder.where((x) => x.startsWith('widget:')).toList();
    final widgetOn = topEnabled.where((x) => x.startsWith('widget:')).toList();

    await _sp.clear();
    _parsed.clear(); // drop cached settings from before the restore
    if (id != null) await _sp.setString('installId', id);
    var n = 0;
    for (final MapEntry(:key, :value) in (data['settings'] as Map).entries) {
      final t = (value as Map)['t'], v = value['v'];
      switch (t) {
        case 's':
          await _sp.setString(key as String, v as String);
        case 'b':
          await _sp.setBool(key as String, v as bool);
        case 'i':
          await _sp.setInt(key as String, (v as num).toInt());
        case 'd':
          await _sp.setDouble(key as String, (v as num).toDouble());
        case 'l':
          await _sp.setStringList(key as String, [for (final x in v as List) '$x']);
        default:
          continue;
      }
      n++;
    }
    if (labels.isNotEmpty) {
      await _sp.setString('widgetLabels', jsonEncode(labels));
      _parsed.clear();
      final order = topOrder;
      final blank = order.indexOf('blank');
      blank < 0 ? order.addAll(widgetOrder) : order.insertAll(blank, widgetOrder);
      await _sp.setStringList('topOrder', order);
      await _sp.setStringList('topEnabled', {...topEnabled, ...widgetOn}.toList());
    }
    notifyListeners(); // everything (theme, pages, folders…) updates live
    return n;
  }

  // ---- First launch ---------------------------------------------------------------

  /// Nothing set yet (a brand-new install with no restored settings).
  bool get isFresh => _sp.getKeys().difference({'blankAdded', 'nowPlayingAdded'}).isEmpty;

  /// Random id saved with the settings. If settings carry one on a first launch, Android
  /// restored them from the phone's Google backup.
  String? get installId => _sp.getString('installId');
  Future<void> setInstallId() => _sp.setString('installId', '${DateTime.now().microsecondsSinceEpoch}');

  /// Drop widget pages whose widget doesn't exist on this phone (e.g. restored from another).
  Future<void> pruneWidgetPages(Set<int> bound) async {
    final stale = widgetLabels.keys.where((k) => !bound.contains(int.tryParse(k.substring(7)))).toList();
    if (stale.isEmpty) return;
    final labels = widgetLabels..removeWhere((k, _) => stale.contains(k));
    await _sp.setString('widgetLabels', jsonEncode(labels));
    _parsed.clear();
    await _sp.setStringList('topOrder', topOrder.where((x) => !stale.contains(x)).toList());
    final on = topEnabled..removeAll(stale);
    await _sp.setStringList('topEnabled', on.isEmpty ? ['clock'] : on.toList());
    notifyListeners();
  }

  // ---- Quick action chips ---------------------------------------------------------

  /// Chips above the green card, in order (built-in "b:…" or app shortcut "s:…").
  List<String> get quickChips => _sp.getStringList('quickChips') ?? const ['b:timer', 'b:torch', 'b:camera', 'b:calculator'];

  /// Names of app-shortcut chips (id → "label|app").
  Map<String, String> get quickLabels => Map<String, String>.from(_json('quickLabels'));

  Future<void> setQuickChips(List<String> ids) => _setList('quickChips', ids);

  Future<void> addQuickChip(String id, {String? label, String? app, bool first = false}) async {
    if (label != null) {
      await _sp.setString('quickLabels', jsonEncode(quickLabels..[id] = '$label|${app ?? ''}'));
      _parsed.remove('quickLabels');
    }
    final list = quickChips.where((x) => x != id).toList();
    first ? list.insert(0, id) : list.add(id);
    await _setList('quickChips', list);
  }

  Future<void> removeQuickChip(String id) => _setList('quickChips', quickChips.where((x) => x != id).toList());

  /// The Paytm-style "Scan QR" chip is offered once (needs app shortcuts to be available).
  bool get qrSeeded => _sp.getBool('qrSeeded') ?? false;
  Future<void> setQrSeeded() => _sp.setBool('qrSeeded', true);

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

  /// TV: the user's own order of apps inside a row (row id → packages; apps not listed keep
  /// their place after the listed ones).
  List<String> tvRowOrder(String row) => List<String>.from((_json('tvRowOrder')[row] as List?) ?? const []);
  Future<void> setTvRowOrder(String row, List<String> packages) async {
    final m = Map<String, dynamic>.from(_json('tvRowOrder'))..[row] = packages;
    await _sp.setString('tvRowOrder', jsonEncode(m));
    notifyListeners();
  }

  /// TV: look & behaviour settings (Customise), one JSON map; see lib/tv/tv_settings.dart.
  Map<String, dynamic> get tvSettings => Map<String, dynamic>.from(_json('tvSettings'));
  Future<void> setTvSetting(String key, Object? value) async {
    await _sp.setString('tvSettings', jsonEncode(tvSettings..[key] = value));
    notifyListeners();
  }

  Future<void> resetTvSettings() async {
    await _sp.remove('tvSettings');
    notifyListeners();
  }

  /// TV: the quick action chips above the rows, in order ("t:…" built-in, `a:<package>` apps).
  static const tvQuickDefault = ['t:inputs', 't:assistant', 't:wifi', 't:sound', 't:settings'];
  List<String> get tvQuickActions => _sp.getStringList('tvQuickActions') ?? tvQuickDefault;
  Future<void> setTvQuickActions(List<String> ids) => _setList('tvQuickActions', ids);

  /// TV: apps opened from the launcher, newest first ("Jump back in").
  List<String> get tvRecents => _sp.getStringList('tvRecents') ?? const [];
  Future<void> noteTvLaunch(String pkg) => _setList('tvRecents', [pkg, ...tvRecents.where((p) => p != pkg)].take(12).toList());

  /// Favourites in a new order (TV: Move left / right).
  Future<void> setFavourites(List<String> ids) => _setList('favourites', ids);

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

  /// Lighter effects: 'auto' (on for budget phones / when frames drop), 'lite' or 'full'.
  String get effects => _sp.getString('effects') ?? 'auto';
  Future<void> setEffects(String v) async {
    await _sp.setString('effects', v);
    notifyListeners();
  }

  /// This phone was seen dropping frames (remembered, so auto mode starts light next time).
  bool get slowFrames => _sp.getBool('slowFrames') ?? false;
  Future<void> setSlowFrames(bool v) => _sp.setBool('slowFrames', v);

  /// Where the search bar lives: 'bottom' (floating dock) or 'top' (in the app drawer, above
  /// the pinned / most-used card).
  String get searchPosition => _sp.getString('searchPosition') ?? 'bottom';
  Future<void> setSearchPosition(String v) async {
    await _sp.setString('searchPosition', v);
    notifyListeners();
  }

  /// What search looks through: apps, app shortcuts, phone settings, Google (web), Play Store.
  static const searchSourceIds = ['apps', 'shortcuts', 'settings', 'google', 'play'];
  Set<String> get searchIn => (_sp.getStringList('searchIn') ?? searchSourceIds).toSet();
  Future<void> setSearchIn(String id, bool on) async {
    final s = searchIn;
    on ? s.add(id) : s.remove(id);
    await _sp.setStringList('searchIn', [
      for (final x in searchSourceIds)
        if (s.contains(x)) x,
    ]);
    notifyListeners();
  }

  /// TV remote: the paired TV (address + name) and whether the dock shows the remote button.
  String? get tvHost => _sp.getString('tvHost');
  String get tvName => _sp.getString('tvName') ?? 'TV';
  Future<void> setTv(String? host, {String? name}) async {
    if (host == null) {
      await _sp.remove('tvHost');
      await _sp.remove('tvName');
    } else {
      await _sp.setString('tvHost', host);
      if (name != null) await _sp.setString('tvName', name);
    }
    notifyListeners();
  }

  bool get remoteButton => _sp.getBool('remoteButton') ?? true;
  Future<void> setRemoteButton(bool v) async {
    await _sp.setBool('remoteButton', v);
    notifyListeners();
  }

  /// Pull down on the app drawer (when it can't scroll further) to open search.
  bool get pullToSearch => _sp.getBool('pullToSearch') ?? true;
  Future<void> setPullToSearch(bool v) async {
    await _sp.setBool('pullToSearch', v);
    notifyListeners();
  }

  /// Scroll-to-open: the folder that settles in the middle of the app list opens by itself
  /// (and the one before closes). Off by default.
  bool get autoOpenFolders => _sp.getBool('autoOpenFolders') ?? false;
  Future<void> setAutoOpenFolders(bool v) async {
    await _sp.setBool('autoOpenFolders', v);
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
