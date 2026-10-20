import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../one_stream.dart';

/// A TV app's artwork: its 16:9 banner when it has one, else its square icon.
class TvArt {
  const TvArt(this.image, {required this.banner});
  final MemoryImage image;
  final bool banner;
}

/// Talks to Android (TvActivity.kt, channel "one_launcher/tv"). On web/tests it serves
/// demo apps so the layout can be previewed.
class TvApps {
  TvApps._();
  static final instance = TvApps._();

  static const _ch = MethodChannel('one_launcher/tv');
  static bool demo = kIsWeb;

  VoidCallback? onHomePressed;
  VoidCallback? onAppsChanged;
  VoidCallback? onResumed; // back on the home screen (Continue watching may have changed)

  /// What's playing / paused now (MediaWatcher.kt). Keys: granted, active, package, app,
  /// title, artist, art (jpeg), playing, position, duration (ms), plus 'at' = when received.
  final media = ValueNotifier<Map?>(null);

  final _images = <String, Future<MemoryImage?>>{};
  final _imagesReady = <String, MemoryImage>{};

  final _art = <String, Future<TvArt?>>{};
  final _ready = <String, TvArt>{};
  final _banner = <String>{};

  /// Already loaded art (draws on the first frame, no flash).
  TvArt? artNow(String package) => _ready[package];

  /// Tests / previews: icons, banners and icon colours as if Android had sent them.
  @visibleForTesting
  void debugSeed({Map<String, MemoryImage> icons = const {}, Map<String, TvArt> art = const {}, Map<String, Color> colours = const {}}) {
    _iconsReady.addAll(icons);
    _ready.addAll(art);
    _demoColours.addAll(colours);
  }

  final _demoColours = <String, Color>{};

  void init() {
    if (demo) return;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'homePressed':
          onHomePressed?.call();
        case 'appsChanged':
          _art.clear();
          _ready.clear();
          onAppsChanged?.call();
          OneStream.instance.refresh(); // One Stream installed / removed
        case 'resumed':
          onResumed?.call();
        case 'mediaChanged':
          media.value = {...(call.arguments as Map), 'at': DateTime.now().millisecondsSinceEpoch};
      }
    });
  }

  Future<List<AppEntry>> list() async {
    if (demo) return _demo;
    final raw = await _ch.invokeListMethod<Map>('getApps') ?? [];
    _banner
      ..clear()
      ..addAll([
        for (final m in raw)
          if (m['banner'] == true) m['package'] as String,
      ]);
    return [
      for (final m in raw)
        AppEntry(
          package: m['package'] as String,
          label: m['label'] as String,
          system: m['system'] as bool? ?? false,
          category: m['category'] as int? ?? -1,
          installed: m['installed'] as int? ?? 0,
        ),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  Future<TvArt?> art(String package) {
    if (demo) return Future.value(null);
    return _art.putIfAbsent(package, () async {
      final bytes = await _ch.invokeMethod<Uint8List>('getArt', {'package': package});
      if (bytes == null) return null;
      return _ready[package] = TvArt(MemoryImage(bytes), banner: _banner.contains(package));
    });
  }

  // ---- Streaming content (best effort; see TvContent.kt) ----

  /// The streaming apps' "Continue watching" (empty where Android keeps it for the system launcher).
  Future<List<Map>> watchNext() async => demo ? _demoWatchNext : await _ch.invokeListMethod<Map>('getWatchNext') ?? const [];

  /// The streaming apps' own rows: each {name, package, programs: [...]}.
  Future<List<Map>> channels() async => demo ? const [] : await _ch.invokeListMethod<Map>('getChannels') ?? const [];

  Future<void> refreshMedia() async {
    if (demo) {
      media.value = _demoMedia;
      return;
    }
    final m = await _ch.invokeMapMethod<String, Object?>('mediaState');
    if (m != null) media.value = {...m, 'at': DateTime.now().millisecondsSinceEpoch};
  }

  Future<void> mediaOpen() => _call('mediaOpen');
  Future<void> mediaResume() => _call('mediaResume');
  Future<void> mediaPlayPause() => _call('mediaPlayPause');
  Future<void> mediaNext() => _call('mediaNext');
  Future<void> mediaPrev() => _call('mediaPrev');

  /// Watch history kept on the TV (MediaHistory.kt): newest first. Keys: key, package, app,
  /// title, subtitle, position, duration (ms), at (epoch ms), art (file path or null).
  Future<List<Map>> history() async => demo ? _demoHistory : await _ch.invokeListMethod<Map>('getHistory') ?? const [];
  Future<void> removeHistory(String key) => _call('removeHistory', {'key': key});
  Future<void> setHistoryEnabled(bool on) => _call('setHistoryEnabled', {'on': on});
  Future<void> clearHistory() => _call('clearHistory');
  Future<void> openNotificationAccess() => _call('openNotificationAccess');
  Future<void> openProgram(String? intent, String package) => _call('openProgram', {'intent': intent, 'package': package});

  /// Artwork from a program uri, downsized on the TV side; cached per size (a small grid poster
  /// never stands in for a big backdrop, and a big one never fills a small tile's memory).
  MemoryImage? imageNow(String uri, {int width = 480}) => _imagesReady['$uri@$width'];
  Future<MemoryImage?> image(String uri, {int width = 480}) {
    if (demo) return Future.value(null);
    return _images.putIfAbsent('$uri@$width', () async {
      final bytes = await _ch.invokeMethod<Uint8List>('getImage', {'uri': uri, 'width': width});
      if (bytes == null) return null;
      return _imagesReady['$uri@$width'] = MemoryImage(bytes);
    });
  }

  /// Tiles: the app's own icon (square), and its main colour for "each app's colour" tiles.
  final _icons = <String, Future<MemoryImage?>>{};
  final _iconsReady = <String, MemoryImage>{};
  MemoryImage? iconNow(String package) => _iconsReady[package];
  Future<MemoryImage?> icon(String package) {
    if (demo) return Future.value(null);
    return _icons.putIfAbsent(package, () async {
      final bytes = await _ch.invokeMethod<Uint8List>('getIcon', {'package': package});
      if (bytes == null) return null;
      return _iconsReady[package] = MemoryImage(bytes);
    });
  }

  final _colours = <String, Future<Color?>>{};
  Future<Color?> iconColour(String package) {
    if (demo) return Future.value(_demoColours[package]);
    return _colours.putIfAbsent(package, () async {
      final c = await _ch.invokeMethod<int>('getIconColour', {'package': package});
      return c == null ? null : Color(c);
    });
  }

  /// The app's banner pre-blurred on the TV side (soft backdrop wash); cached.
  final _backdrops = <String, Future<MemoryImage?>>{};
  final _backdropsReady = <String, MemoryImage>{};
  MemoryImage? backdropNow(String package) => _backdropsReady[package];
  Future<MemoryImage?> backdrop(String package) {
    if (demo) return Future.value(null);
    return _backdrops.putIfAbsent(package, () async {
      final bytes = await _ch.invokeMethod<Uint8List>('getBackdrop', {'package': package});
      if (bytes == null) return null;
      return _backdropsReady[package] = MemoryImage(bytes);
    });
  }

  /// Installed apps that accept a search request (JioHotstar, Play Store…).
  Future<List<String>> searchTargets() async =>
      demo ? const ['in.startv.hotstar', 'com.android.vending'] : await _ch.invokeListMethod<String>('searchTargets') ?? const [];
  Future<void> searchIn(String package, String query) => _call('searchIn', {'package': package, 'query': query});
  Future<void> openUri(String uri, {String? package}) => _call('openUri', {'uri': uri, 'package': package});
  Future<void> searchEverywhere(String query) => _call('searchEverywhere', {'query': query});

  /// GET through Android's network stack (TvActivity "httpGet") → (status, body). Status -1 =
  /// no connection (body says why).
  Future<(int, String)> httpGet(String url, {Map<String, String> headers = const {}}) async {
    final m = await _ch.invokeMapMethod<String, Object?>('httpGet', {'url': url, 'headers': headers});
    return ((m?['status'] as int?) ?? -1, (m?['body'] as String?) ?? '');
  }

  /// Opens a show's link in an app: WatchHub's "watch on" links (intent://… or https://…) or
  /// "Open in Nuvio" (stremio:///detail/…), in [package] when given; [fallback] (the web link)
  /// when the first doesn't open. → whether something opened.
  Future<bool> openLink(String uri, {String? package, String? fallback}) async {
    if (demo) return false;
    return await _ch.invokeMethod<bool>('openLink', {'uri': uri, 'package': package, 'fallback': fallback}) ?? false;
  }

  /// Installed apps that open [uri] (stremio:///detail/… → Nuvio, Stremio): (package, name).
  Future<List<(String, String)>> linkHandlers(String uri) async {
    if (demo) return uri.startsWith('stremio:') ? const [('com.nuvio.app', 'Nuvio')] : const [];
    final raw = await _ch.invokeListMethod<Map>('linkHandlers', {'uri': uri}) ?? const [];
    return [for (final m in raw) (m['package'] as String, m['label'] as String)];
  }

  /// The app's own storage folder (the shows & films catalog is saved there).
  Future<String?> filesDir() async => demo ? null : await _ch.invokeMethod<String>('filesDir');

  Future<void> launch(String package) => _call('launch', {'package': package});
  Future<void> appInfo(String package) => _call('appInfo', {'package': package});
  Future<void> uninstall(String package) => _call('uninstall', {'package': package});
  Future<void> openAction(String id) => _call('openAction', {'id': id});
  Future<void> openSettings() => _call('openSettings');
  Future<void> openInputs() => _call('openInputs');
  Future<void> openHomeSettings() => _call('openHomeSettings');

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    if (demo) return;
    await _ch.invokeMethod(method, args);
  }

  static final _demoMedia = {
    'granted': true,
    'active': true,
    'package': 'com.netflix.ninja',
    'app': 'Netflix',
    'title': 'The Long Night',
    'artist': 'Season 2 · Episode 5',
    'playing': false,
    'position': 1980000,
    'duration': 3120000,
    'canPrev': true,
    'canNext': true,
    'at': 0,
  };

  static final _demoHistory = <Map>[
    {
      'key': 'com.netflix.ninja|The Long Night',
      'package': 'com.netflix.ninja',
      'app': 'Netflix',
      'title': 'The Long Night',
      'subtitle': 'Season 2 · Episode 5',
      'position': 1980000,
      'duration': 3120000,
      'at': DateTime.now().millisecondsSinceEpoch,
    },
    {
      'key': 'com.spotify.tv.android|Midnight City',
      'package': 'com.spotify.tv.android',
      'app': 'Spotify',
      'title': 'Midnight City',
      'subtitle': 'M83',
      'position': 120000,
      'duration': 244000,
      'at': DateTime.now().subtract(const Duration(hours: 5)).millisecondsSinceEpoch,
    },
    {
      'key': 'com.google.android.youtube.tv|How lighthouses work',
      'package': 'com.google.android.youtube.tv',
      'app': 'YouTube',
      'title': 'How lighthouses work',
      'subtitle': 'Practical Engineering',
      'position': 300000,
      'duration': 900000,
      'at': DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch,
    },
  ];

  static const _demoWatchNext = <Map>[
    {
      'id': '1',
      'package': 'com.amazon.amazonvideo.livingroom',
      'title': 'Coastline',
      'season': '1',
      'episode': '3',
      'episodeTitle': 'Low Tide',
      'description': 'A storm strands the crew on the far side of the island.',
      'position': 900000,
      'duration': 2700000,
    },
    {
      'id': '2',
      'package': 'in.startv.hotstar',
      'title': 'Final Over',
      'description': 'Highlights from last night’s match.',
      'position': 0,
      'duration': 1500000,
    },
  ];

  static const _demo = [
    AppEntry(package: 'com.netflix.ninja', label: 'Netflix'),
    AppEntry(package: 'com.google.android.youtube.tv', label: 'YouTube'),
    AppEntry(package: 'com.amazon.amazonvideo.livingroom', label: 'Prime Video'),
    AppEntry(package: 'in.startv.hotstar', label: 'Hotstar'),
    AppEntry(package: 'com.spotify.tv.android', label: 'Spotify'),
    AppEntry(package: 'com.google.android.youtube.tvmusic', label: 'YouTube Music'),
    AppEntry(package: 'com.plexapp.android', label: 'Plex'),
    AppEntry(package: 'org.videolan.vlc', label: 'VLC'),
    AppEntry(package: 'com.google.android.play.games', label: 'Play Games'),
    AppEntry(package: 'com.gameloft.asphalt', label: 'Asphalt Xtreme'),
    AppEntry(package: 'com.android.vending', label: 'Play Store', system: true),
    AppEntry(package: 'com.android.tv.settings', label: 'Settings', system: true),
    AppEntry(package: 'com.google.android.apps.photos', label: 'Photos'),
    AppEntry(package: 'com.android.chrome', label: 'Chrome'),
    AppEntry(package: 'com.estrongs.android.pop', label: 'File Manager', system: true),
  ];
}
