import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppEntry {
  const AppEntry({required this.package, required this.label, this.system = false});
  final String package;
  final String label;
  final bool system;
}

/// Talks to Android (MainActivity.kt). On web it serves demo apps so the
/// layout can be previewed in a browser.
class Apps {
  Apps._();
  static final instance = Apps._();

  static const _ch = MethodChannel('one_launcher/apps');
  static bool get isDemo => kIsWeb;

  final _icons = <String, Future<Uint8List?>>{};
  VoidCallback? onHomePressed;
  VoidCallback? onAppsChanged;

  void init() {
    if (isDemo) return;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'homePressed':
          onHomePressed?.call();
        case 'appsChanged':
          _icons.clear();
          onAppsChanged?.call();
      }
    });
  }

  Future<List<AppEntry>> list() async {
    if (isDemo) return _demo;
    final raw = await _ch.invokeListMethod<Map>('getApps') ?? [];
    final apps = raw
        .map((m) => AppEntry(package: m['package'] as String, label: m['label'] as String, system: m['system'] as bool? ?? false))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return apps;
  }

  Future<Uint8List?> icon(String package) {
    if (isDemo) return Future.value(null);
    return _icons.putIfAbsent(package, () => _ch.invokeMethod<Uint8List>('getIcon', {'package': package}));
  }

  Future<void> launch(String package) => _call('launch', {'package': package});
  Future<void> appInfo(String package) => _call('appInfo', {'package': package});
  Future<void> uninstall(String package) => _call('uninstall', {'package': package});
  Future<void> openNotifications() => _call('openNotifications');
  Future<void> openWallpaperPicker() => _call('openWallpaperPicker');
  Future<void> openHomeSettings() => _call('openHomeSettings');

  Future<void> _call(String method, [Map<String, dynamic>? args]) async {
    if (isDemo) return;
    await _ch.invokeMethod(method, args);
  }

  static const _demo = [
    AppEntry(package: 'calendar', label: 'Calendar'),
    AppEntry(package: 'camera', label: 'Camera'),
    AppEntry(package: 'chrome', label: 'Chrome'),
    AppEntry(package: 'clock', label: 'Clock'),
    AppEntry(package: 'contacts', label: 'Contacts'),
    AppEntry(package: 'drive', label: 'Drive'),
    AppEntry(package: 'figma', label: 'Figma'),
    AppEntry(package: 'gmail', label: 'Gmail'),
    AppEntry(package: 'maps', label: 'Maps'),
    AppEntry(package: 'messages', label: 'Messages'),
    AppEntry(package: 'phone', label: 'Phone'),
    AppEntry(package: 'photos', label: 'Photos'),
    AppEntry(package: 'settings', label: 'Settings', system: true),
    AppEntry(package: 'slack', label: 'Slack'),
    AppEntry(package: 'spotify', label: 'Spotify'),
    AppEntry(package: 'whatsapp', label: 'WhatsApp'),
    AppEntry(package: 'youtube', label: 'YouTube'),
  ];
}
