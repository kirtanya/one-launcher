import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'tv_remote.dart';

import 'quick_actions.dart';

/// An Android app widget that can be added to the top carousel.
class WidgetProvider {
  const WidgetProvider(this.map);
  final Map map;
  String get provider => map['provider'] as String;
  int get serial => (map['serial'] as num).toInt();
  String get label => map['label'] as String;
  String get app => map['app'] as String;
  String get package => map['package'] as String;
  bool get work => map['work'] == true;
  int get cols => (map['cols'] as num?)?.toInt() ?? 2;
  int get rows => (map['rows'] as num?)?.toInt() ?? 1;
}

class AppEntry {
  const AppEntry({
    required this.package,
    required this.label,
    this.system = false,
    this.category = -1,
    this.installed = 0,
    this.work = false,
    this.paused = false,
  });
  final String package;
  final String label;
  final bool system;
  final int category; // Android ApplicationInfo.category, -1 = none
  final int installed; // first install time, ms since epoch
  final bool work; // from the work profile (package is then "pkg@profile")
  final bool paused; // work apps are paused (tapping asks to turn them on)
}

/// Talks to Android (MainActivity.kt). On web it serves demo apps so the
/// layout can be previewed in a browser.
class Apps {
  Apps._();
  static final instance = Apps._();

  static const _ch = MethodChannel('one_launcher/apps');
  static bool get isDemo => kIsWeb;

  final _icons = <String, Future<Uint8List?>>{};

  /// Icons already loaded, as reusable images: draw instantly (no blank first frame) and are
  /// decoded once, then served from Flutter's image cache.
  final _ready = <String, MemoryImage>{};
  MemoryImage? iconNow(String package) => _ready[package];
  VoidCallback? onHomePressed;
  VoidCallback? onAppsChanged;
  VoidCallback? onPermissionsChanged;

  /// What's playing (pushed by Android whenever the track or play state changes).
  /// Keys: granted, active, app, title, artist, art (png), playing, position, duration (ms),
  /// speed, canPrev, canNext, plus 'at' = when we received it (to move the progress bar).
  final media = ValueNotifier<Map?>(null);

  /// Unread (clearable) notifications per app id — badges on Start tiles. Needs Notification access.
  final notifCounts = ValueNotifier<Map<String, int>>(const {});

  Future<void> refreshNotifCounts() async {
    if (isDemo) return;
    try {
      final m = await _ch.invokeMapMethod<String, int>('notifCounts');
      if (m != null) notifCounts.value = m;
    } catch (_) {}
  }

  /// The next alarm (live Clock tile): when, and which app set it.
  Future<(DateTime, String?)?> nextAlarm() async {
    if (isDemo) return null;
    try {
      final m = await _ch.invokeMapMethod<String, Object?>('nextAlarm');
      if (m == null) return null;
      return (DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()), m['package'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// Double-tap to lock: true when the screen went off; false = the lock service isn't on yet.
  Future<bool> lockScreen() async {
    if (isDemo) return false;
    try {
      return await _ch.invokeMethod<bool>('lockScreen') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAccessibility() => _call('openAccessibility');

  /// Flashlight on? (pushed by Android when it changes, from anywhere.)
  final torchOn = ValueNotifier<bool>(false);

  void init() {
    if (isDemo) return;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'homePressed':
          onHomePressed?.call();
        case 'appsChanged':
          // Keep the icons on screen; the reload that follows refreshes only the ones that
          // changed (wiping them all flashed every icon to a letter).
          _icons.removeWhere((pkg, _) => !_ready.containsKey(pkg)); // retry ones that failed
          onAppsChanged?.call();
        case 'permissionsChanged':
          onPermissionsChanged?.call();
        case 'torchChanged':
          torchOn.value = call.arguments == true;
        case 'tvState':
          TvRemote.instance.onEvent(call.arguments as Map);
        case 'notifCounts':
          notifCounts.value = Map<String, int>.from(call.arguments as Map);
        case 'mediaChanged':
          media.value = {...(call.arguments as Map), 'at': DateTime.now().millisecondsSinceEpoch};
      }
    });
  }

  Future<List<AppEntry>> list() async {
    if (isDemo) return _demo;
    final raw = await _ch.invokeListMethod<Map>('getApps') ?? [];
    final apps =
        raw
            .map(
              (m) => AppEntry(
                package: m['package'] as String,
                label: m['label'] as String,
                system: m['system'] as bool? ?? false,
                category: m['category'] as int? ?? -1,
                installed: m['installed'] as int? ?? 0,
                work: m['work'] as bool? ?? false,
                paused: m['paused'] as bool? ?? false,
              ),
            )
            .toList()
          ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    // Every icon in one batch (from Android's disk cache when unchanged), given a moment to
    // arrive so the list doesn't open on letter tiles; slower ones fill in as they come.
    await _prefetch(apps).timeout(const Duration(milliseconds: 600), onTimeout: () {});
    return apps;
  }

  Future<void>? _prefetching;

  /// Loads all [apps]' icons at once and decodes them ahead of their first draw. Icons that
  /// didn't change keep their image (no flicker); changed ones are swapped in.
  Future<void> _prefetch(List<AppEntry> apps) => _prefetching = () async {
    try {
      final m = await _ch.invokeMapMethod<String, Uint8List>('getIcons', {'packages': [for (final a in apps) a.package]});
      if (m == null) return;
      for (final MapEntry(key: pkg, value: bytes) in m.entries) {
        if (_ready[pkg] case final old? when listEquals(old.bytes, bytes)) continue;
        final img = MemoryImage(bytes);
        _ready[pkg] = img;
        _icons[pkg] = Future.value(bytes);
        img.resolve(ImageConfiguration.empty); // decode now, not on first draw
      }
    } catch (_) {
      // Older Android side: icons load one by one as drawn.
    }
  }();

  Future<Uint8List?> icon(String package) {
    if (isDemo) return Future.value(null);
    return _icons.putIfAbsent(package, () async {
      // A batch is on its way: wait for it rather than asking twice.
      await _prefetching;
      if (_ready[package] case final ready?) return ready.bytes;
      final bytes = await _ch.invokeMethod<Uint8List>('getIcon', {'package': package});
      if (bytes != null) _ready[package] = MemoryImage(bytes);
      return bytes;
    });
  }

  /// The app's white one-colour glyph (Android 13+ themed icon), or null if it has none.
  final _mono = <String, Future<Uint8List?>>{};
  Future<Uint8List?> monoIcon(String package) {
    if (isDemo) return Future.value(null);
    return _mono.putIfAbsent(package, () async {
      try {
        final bytes = await _ch.invokeMethod<Uint8List>('getMonoIcon', {'package': package});
        if (bytes != null) _monoReady[package] = MemoryImage(bytes);
        return bytes;
      } catch (_) {
        return null;
      }
    });
  }

  /// The glyph when already loaded (no flicker on rebuilds); [monoChecked] = asked before.
  final _monoReady = <String, MemoryImage>{};
  MemoryImage? monoNow(String package) => _monoReady[package];

  /// Where the tapped icon is (screen pixels: left, top, width, height), so the app opens
  /// growing out of it. Set by [markLaunchFrom] just before launching; used once.
  List<int>? _launchFrom;

  /// Remember the tapped widget's on-screen box for the next launch's open animation.
  void markLaunchFrom(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final r = box.localToGlobal(Offset.zero) & box.size;
    _launchFrom = [(r.left * dpr).round(), (r.top * dpr).round(), (r.width * dpr).round(), (r.height * dpr).round()];
  }

  Future<void> launch(String package) {
    final from = _launchFrom;
    _launchFrom = null;
    return _call('launch', {'package': package, 'from': ?from});
  }

  Future<void> appInfo(String package) => _call('appInfo', {'package': package});
  Future<void> uninstall(String package) => _call('uninstall', {'package': package});
  Future<void> openNotifications() => _call('openNotifications');
  Future<void> openWallpaperPicker() => _call('openWallpaperPicker');

  /// Search the web for [query] (Google app if installed, else the browser).
  Future<void> webSearch(String query) => _call('webSearch', {'query': query});

  /// Open a phone settings page by its Android action (Settings.ACTION_…).
  Future<void> openSetting(String action) => _call('openSetting', {'action': action});

  /// Search the Play Store's apps for [query].
  Future<void> playSearch(String query) => _call('playSearch', {'query': query});
  Future<void> openHomeSettings() => _call('openHomeSettings');

  // ---- Top carousel data ----

  /// {granted, total (ms), top: [{package, label, ms}]}
  Future<Map> screenTime() async {
    if (isDemo) {
      return {
        'granted': true,
        'total': 13_920_000,
        'top': [
          {'package': 'com.whatsapp', 'label': 'WhatsApp', 'ms': 4_200_000},
          {'package': 'com.google.android.youtube', 'label': 'YouTube', 'ms': 3_100_000},
          {'package': 'com.Slack', 'label': 'Slack', 'ms': 1_800_000},
        ],
      };
    }
    return await _ch.invokeMapMethod('getScreenTime') ?? const {};
  }

  /// {level (0-100), charging, full, chargeMsLeft (-1 = unknown)}
  Future<Map> battery() async {
    if (isDemo) return {'level': 64, 'charging': true, 'full': false, 'chargeMsLeft': 2_700_000};
    return await _ch.invokeMapMethod('getBattery') ?? const {};
  }

  /// The next few calendar events: {granted, events: [{id, title, begin, end, allDay, color}]}.
  Future<Map> events({int limit = 6}) async {
    if (isDemo) return const {'granted': true, 'events': []};
    try {
      return await _ch.invokeMapMethod('getEvents', {'limit': limit}) ?? const {};
    } catch (_) {
      return const {};
    }
  }

  /// {granted, id?, title?, begin?, end?, allDay?}
  Future<Map> nextEvent() async {
    if (isDemo) {
      final b = DateTime.now().add(const Duration(minutes: 40)).millisecondsSinceEpoch;
      return {'granted': true, 'id': 1, 'title': 'Design review', 'begin': b, 'end': b + 1_800_000, 'allDay': false};
    }
    return await _ch.invokeMapMethod('getNextEvent') ?? const {};
  }

  // ---- App widgets (top carousel) ----

  Future<List<WidgetProvider>> widgetProviders() async {
    if (isDemo) return const [];
    final raw = await _ch.invokeListMethod<Map>('listWidgetProviders') ?? [];
    return raw.map(WidgetProvider.new).toList();
  }

  final _previews = <String, Future<Uint8List?>>{};
  Future<Uint8List?> widgetPreview(WidgetProvider p) => _previews.putIfAbsent(
    '${p.provider}@${p.serial}',
    () => isDemo ? Future.value(null) : _ch.invokeMethod<Uint8List>('getWidgetPreview', {'provider': p.provider, 'serial': p.serial}),
  );

  /// Bind (asking the user once) and run the widget's setup; returns its id, or null if cancelled.
  Future<int?> addWidget(WidgetProvider p) async {
    if (isDemo) return null;
    return _ch.invokeMethod<int>('addWidget', {'provider': p.provider, 'serial': p.serial});
  }

  Future<void> removeWidget(int id) => _call('removeWidget', {'id': id});

  /// Android's "save file" picker; true if saved.
  Future<bool> saveBackup(String name, String text) async {
    if (isDemo) return false;
    return await _ch.invokeMethod<bool>('saveBackup', {'name': name, 'text': text}) ?? false;
  }

  /// Android's "open file" picker (optionally opened in Downloads); the file's text, or null.
  Future<String?> openBackup({bool inDownloads = false}) async {
    if (isDemo) return null;
    return _ch.invokeMethod<String>('openBackup', {'downloads': inDownloads});
  }

  /// Android's photo picker; the picked image copied into app storage (its path), or null.
  Future<String?> pickPhoto() async {
    if (isDemo) return null;
    return _ch.invokeMethod<String>('pickPhoto');
  }

  /// Phone capability: lowRam (Android's own flag), ramGb, cores. Empty in the web demo.
  Future<Map<String, dynamic>> deviceClass() async {
    if (isDemo) return const {};
    try {
      return await _ch.invokeMapMethod<String, dynamic>('deviceClass') ?? const {};
    } catch (_) {
      return const {};
    }
  }

  /// True on the very first launch of this install (also after a reinstall).
  Future<bool> isFirstRun() async {
    if (isDemo) return false;
    final m = await _ch.invokeMapMethod<String, dynamic>('installState');
    return m?['firstRun'] == true;
  }

  /// App widget ids that actually exist on this phone (null if unknown).
  Future<List<int>?> boundWidgetIds() async {
    if (isDemo) return null;
    final l = await _ch.invokeListMethod<int>('boundWidgetIds');
    return l;
  }

  // ---- Quick actions ----

  /// Runs a quick action; false if nothing on this phone can do it.
  Future<bool> quickAction(String id) async {
    if (isDemo) return true;
    return await _ch.invokeMethod<bool>('quickAction', {'id': id}) ?? false;
  }

  Future<void> refreshTorch() async {
    if (isDemo) return;
    final m = await _ch.invokeMapMethod('torchState');
    torchOn.value = m?['on'] == true;
  }

  /// App shortcuts (null = not allowed: One Launcher isn't the default home app).
  Future<List<AppShortcut>?> shortcuts() async {
    if (isDemo) return const [];
    final m = await _ch.invokeMapMethod('listShortcuts');
    if (m == null || m['allowed'] != true) return null;
    return [for (final s in m['shortcuts'] as List) AppShortcut(s as Map)];
  }

  final _shortcutIcons = <String, Future<Uint8List?>>{};
  Future<Uint8List?> shortcutIcon(String id) =>
      _shortcutIcons.putIfAbsent(id, () => isDemo ? Future.value(null) : _ch.invokeMethod<Uint8List>('shortcutIcon', {'id': id}));

  // ---- Now playing ----

  Future<void> refreshMedia() async {
    if (isDemo) {
      media.value = {
        'granted': true,
        'active': true,
        'app': 'Spotify',
        'title': 'Midnight City',
        'artist': 'M83',
        'playing': true,
        'position': 64000,
        'duration': 243000,
        'speed': 1.0,
        'canPrev': true,
        'canNext': true,
        'at': DateTime.now().millisecondsSinceEpoch,
      };
      return;
    }
    final m = await _ch.invokeMapMethod('mediaState');
    if (m != null) media.value = {...m, 'at': DateTime.now().millisecondsSinceEpoch};
  }

  Future<void> mediaPlayPause() => _call('mediaPlayPause');
  Future<void> mediaNext() => _call('mediaNext');
  Future<void> mediaPrev() => _call('mediaPrev');
  Future<void> mediaOpen() => _call('mediaOpen');
  Future<void> openNotificationAccess() => _call('openNotificationAccess');

  Future<void> openUsageAccess() => _call('openUsageAccess');
  Future<void> openScreenTime() => _call('openScreenTime');
  Future<void> openBatterySettings() => _call('openBatterySettings');
  Future<void> requestCalendar() => _call('requestCalendar');
  Future<void> openEvent(int id) => _call('openEvent', {'id': id});

  Future<void> _call(String method, [Map<String, dynamic>? args]) async {
    if (isDemo) return;
    await _ch.invokeMethod(method, args);
  }

  static const _demo = [
    AppEntry(package: 'com.google.android.calendar', label: 'Calendar'),
    AppEntry(package: 'com.google.android.GoogleCamera', label: 'Camera'),
    AppEntry(package: 'com.android.chrome', label: 'Chrome', system: true),
    AppEntry(package: 'com.google.android.deskclock', label: 'Clock', system: true),
    AppEntry(package: 'com.google.android.apps.docs', label: 'Drive'),
    AppEntry(package: 'com.figma.mirror', label: 'Figma'),
    AppEntry(package: 'com.google.android.gm', label: 'Gmail'),
    AppEntry(package: 'com.google.android.apps.maps', label: 'Maps'),
    AppEntry(package: 'com.google.android.apps.messaging', label: 'Messages'),
    AppEntry(package: 'com.google.android.apps.photos', label: 'Photos'),
    AppEntry(package: 'com.android.settings', label: 'Settings', system: true),
    AppEntry(package: 'com.Slack', label: 'Slack'),
    AppEntry(package: 'com.spotify.music', label: 'Spotify'),
    AppEntry(package: 'com.whatsapp', label: 'WhatsApp'),
    AppEntry(package: 'com.instagram.android', label: 'Instagram'),
    AppEntry(package: 'com.google.android.youtube', label: 'YouTube'),
    AppEntry(package: 'net.one97.paytm', label: 'Paytm'),
    AppEntry(package: 'com.phonepe.app', label: 'PhonePe'),
    AppEntry(package: 'in.swiggy.android', label: 'Swiggy'),
    AppEntry(package: 'com.application.zomato', label: 'Zomato'),
    AppEntry(package: 'com.ubercab', label: 'Uber'),
    AppEntry(package: 'com.splitwise.SplitwiseMobile', label: 'Splitwise'),
    AppEntry(package: 'com.netflix.mediaclient', label: 'Netflix'),
    AppEntry(package: 'com.amazon.mShop.android.shopping', label: 'Amazon'),
  ];
}
