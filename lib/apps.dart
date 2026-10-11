import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppEntry {
  const AppEntry({required this.package, required this.label, this.system = false, this.category = -1, this.installed = 0});
  final String package;
  final String label;
  final bool system;
  final int category; // Android ApplicationInfo.category, -1 = none
  final int installed; // first install time, ms since epoch
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
    final apps =
        raw
            .map(
              (m) => AppEntry(
                package: m['package'] as String,
                label: m['label'] as String,
                system: m['system'] as bool? ?? false,
                category: m['category'] as int? ?? -1,
                installed: m['installed'] as int? ?? 0,
              ),
            )
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
