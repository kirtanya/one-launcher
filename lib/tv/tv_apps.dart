import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../apps.dart';

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

  /// Artwork from a program uri, downsized on the TV side; cached.
  MemoryImage? imageNow(String uri) => _imagesReady[uri];
  Future<MemoryImage?> image(String uri, {int width = 480}) {
    if (demo) return Future.value(null);
    return _images.putIfAbsent('$uri@$width', () async {
      final bytes = await _ch.invokeMethod<Uint8List>('getImage', {'uri': uri, 'width': width});
      if (bytes == null) return null;
      return _imagesReady[uri] = MemoryImage(bytes);
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
