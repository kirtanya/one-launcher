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

  Future<void> launch(String package) => _call('launch', {'package': package});
  Future<void> appInfo(String package) => _call('appInfo', {'package': package});
  Future<void> uninstall(String package) => _call('uninstall', {'package': package});
  Future<void> openSettings() => _call('openSettings');
  Future<void> openInputs() => _call('openInputs');
  Future<void> openHomeSettings() => _call('openHomeSettings');

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    if (demo) return;
    await _ch.invokeMethod(method, args);
  }

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
