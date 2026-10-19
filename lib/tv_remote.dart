import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Connection to the user's Google TV / Android TV (native side: TvRemote.kt). Pair once with
/// the code the TV shows, then send keys and app links. Local Wi-Fi only.
enum TvStatus { idle, connecting, connected, disconnected }

/// Android key codes the remote sends.
abstract final class TvKey {
  static const home = 3, back = 4, up = 19, down = 20, left = 21, right = 22, ok = 23;
  static const volumeUp = 24, volumeDown = 25, power = 26, menu = 82, playPause = 85;
  static const next = 87, previous = 88, mute = 164, input = 178, settings = 176;
  static const enter = 66, delete = 67;
}

/// Direction of a key press on the wire.
abstract final class TvPress {
  static const longStart = 1, longEnd = 2, short = 3;
}

class TvRemote {
  TvRemote._();
  static final instance = TvRemote._();
  static const _ch = MethodChannel('one_launcher/apps');

  final status = ValueNotifier<TvStatus>(TvStatus.idle);

  /// (level, max, muted) when the TV reports it.
  final volume = ValueNotifier<(int, int, bool)?>(null);

  /// A text field is focused on the TV: (its current text, its label). Null when not typing.
  final ime = ValueNotifier<(String, String)?>(null);

  /// The last problem, in words (connection lost, wrong code…).
  final error = ValueNotifier<String?>(null);

  void onEvent(Map m) {
    switch (m['state']) {
      case 'connecting':
        status.value = TvStatus.connecting;
      case 'connected':
        status.value = TvStatus.connected;
        error.value = null;
      case 'disconnected':
        status.value = TvStatus.disconnected;
        ime.value = null;
      case 'volume':
        volume.value = ((m['level'] as num).toInt(), (m['max'] as num).toInt(), m['muted'] == true);
      case 'ime':
        ime.value = ((m['text'] as String?) ?? '', (m['label'] as String?) ?? '');
      case 'error':
        error.value = m['message'] as String?;
    }
  }

  String _why(Object e) => e is PlatformException ? (e.message ?? 'Something went wrong') : '$e';

  /// TVs on this Wi-Fi that accept remotes: (name, host).
  Future<List<(String, String)>> discover() async {
    try {
      final list = await _ch.invokeListMethod<Map>('tvDiscover') ?? const [];
      return [for (final m in list) (m['name'] as String, m['host'] as String)];
    } catch (_) {
      return const [];
    }
  }

  /// Step 1: the TV shows a 6-character code. Returns an error message, or null when it worked.
  Future<String?> pairStart(String host) async {
    try {
      await _ch.invokeMethod('tvPairStart', {'host': host});
      return null;
    } catch (e) {
      return _why(e);
    }
  }

  /// Step 2: the code from the TV screen. Returns an error message, or null when paired.
  Future<String?> pairFinish(String code) async {
    try {
      await _ch.invokeMethod('tvPairFinish', {'code': code});
      return null;
    } catch (e) {
      return _why(e);
    }
  }

  /// Connects to a paired TV. Returns an error message, or null.
  Future<String?> connect(String host) async {
    status.value = TvStatus.connecting;
    try {
      await _ch.invokeMethod('tvConnect', {'host': host});
      return null;
    } catch (e) {
      status.value = TvStatus.disconnected;
      error.value = _why(e);
      return error.value;
    }
  }

  Future<void> key(int code, {int press = TvPress.short}) async {
    try {
      await _ch.invokeMethod('tvKey', {'code': code, 'direction': press});
    } catch (e) {
      status.value = TvStatus.disconnected;
      error.value = _why(e);
    }
  }

  /// What the typing panel last sent (to turn changes into key presses).
  String _typed = '';

  /// The typing panel opened on [start] (the TV field's current text).
  void startTyping(String start) => _typed = start;

  /// Types on the TV: sends only what changed since the last call. The TV adds whatever text it
  /// is sent to its field (it doesn't replace the field), so removed letters go as Delete key
  /// presses and new letters as text through the TV's keyboard protocol — or as one key press
  /// each when the TV didn't give us its field (some only name the app). Assumes the cursor is
  /// at the end, as it is while typing on the phone.
  Future<void> text(String text) async {
    final before = _typed;
    _typed = text;
    var same = 0;
    while (same < before.length && same < text.length && before[same] == text[same]) {
      same++;
    }
    final added = text.substring(same);
    try {
      for (var i = same; i < before.length; i++) {
        await key(TvKey.delete);
      }
      if (added.isEmpty) return;
      final viaIme = await _ch.invokeMethod<bool>('tvText', {'text': added}) ?? false;
      if (viaIme) return;
      for (final ch in added.split('')) {
        final code = keyFor(ch);
        if (code != null) await key(code);
      }
    } catch (e) {
      error.value = _why(e);
    }
  }

  /// Android key code for a typed character (letters, digits, common symbols), or null.
  static int? keyFor(String ch) {
    final c = ch.toLowerCase();
    final u = c.codeUnitAt(0);
    if (u >= 97 && u <= 122) return 29 + (u - 97); // a–z
    if (u >= 48 && u <= 57) return 7 + (u - 48); // 0–9
    return const {
      ' ': 62, '.': 56, ',': 55, '-': 69, '=': 70, '[': 71, ']': 72, '\\': 73, ';': 74, "'": 75, '/': 76, '@': 77, '+': 81, '*': 17, '#': 18, //
    }[c];
  }

  /// Volume to [target] (0…max): the protocol only has volume keys, so press up/down the
  /// right number of times; the TV reports the real level back as it changes.
  bool _settingVolume = false;
  Future<void> setVolume(int target) async {
    final v = volume.value;
    if (v == null || _settingVolume) return;
    _settingVolume = true;
    try {
      var steps = target - v.$1;
      final code = steps > 0 ? TvKey.volumeUp : TvKey.volumeDown;
      for (steps = steps.abs(); steps > 0; steps--) {
        await key(code);
        await Future<void>.delayed(const Duration(milliseconds: 45));
      }
    } finally {
      _settingVolume = false;
    }
  }

  /// TV brightness 0–100 % as Android brightness on the TV (via One Launcher TV). Only TVs whose
  /// backlight follows Android brightness respond; others keep it in their picture panel.
  Future<void> setBrightness(int percent) => appLink('onelauncher://brightness?level=${(1 + percent.clamp(0, 100) * 254 / 100).round()}');

  /// Opens the TV's own picture settings (backlight lives there), via One Launcher TV on the TV.
  Future<void> openPicture() => appLink('onelauncher://picture');

  Future<void> appLink(String link) async {
    try {
      await _ch.invokeMethod('tvAppLink', {'link': link});
    } catch (e) {
      error.value = _why(e);
    }
  }

  Future<void> disconnect() async {
    try {
      await _ch.invokeMethod('tvDisconnect');
    } catch (_) {}
    status.value = TvStatus.idle;
  }

  Future<void> forget(String host) async {
    try {
      await _ch.invokeMethod('tvForget', {'host': host});
    } catch (_) {}
    status.value = TvStatus.idle;
    volume.value = null;
  }
}

/// A quick app on the phone remote: its name, its Android TV package and (when it has one) a web
/// link the app opens on the TV — which works without One Launcher TV on the TV.
typedef RemoteApp = ({String id, String name, String package, String? web});

/// Common TV apps for the remote's quick row (Edit → Add).
const remoteAppCatalog = <RemoteApp>[
  (id: 'youtube', name: 'YouTube', package: 'com.google.android.youtube.tv', web: 'https://www.youtube.com'),
  (id: 'netflix', name: 'Netflix', package: 'com.netflix.ninja', web: 'https://www.netflix.com/title'),
  (id: 'prime', name: 'Prime Video', package: 'com.amazon.amazonvideo.livingroom', web: 'https://app.primevideo.com'),
  (id: 'hotstar', name: 'JioHotstar', package: 'in.startv.hotstar', web: 'https://www.hotstar.com'),
  (id: 'disney', name: 'Disney+', package: 'com.disney.disneyplus', web: 'https://www.disneyplus.com'),
  (id: 'ytmusic', name: 'YouTube Music', package: 'com.google.android.youtube.tvmusic', web: null),
  (id: 'spotify', name: 'Spotify', package: 'com.spotify.tv.android', web: 'https://open.spotify.com'),
  (id: 'sonyliv', name: 'SonyLIV', package: 'com.sonyliv', web: null),
  (id: 'zee5', name: 'ZEE5', package: 'com.graymatrix.did', web: null),
  (id: 'appletv', name: 'Apple TV', package: 'com.apple.atve.androidtv.appletv', web: null),
  (id: 'plex', name: 'Plex', package: 'com.plexapp.android', web: null),
  (id: 'nuvio', name: 'Nuvio', package: 'com.nuvio.app', web: null),
  (id: 'stremio', name: 'Stremio', package: 'com.stremio.one', web: null),
  (id: 'vlc', name: 'VLC', package: 'org.videolan.vlc', web: null),
  (id: 'kodi', name: 'Kodi', package: 'org.xbmc.kodi', web: null),
  (id: 'twitch', name: 'Twitch', package: 'tv.twitch.android.viewer', web: null),
  (id: 'playstore', name: 'Play Store', package: 'com.android.vending', web: null),
];

/// A quick-app id → the app ("c:Name|package" is one the user typed in), or null if unknown.
RemoteApp? remoteAppFor(String id) {
  if (id.startsWith('c:')) {
    final parts = id.substring(2).split('|');
    if (parts.length < 2 || parts[1].isEmpty) return null;
    return (id: id, name: parts[0].isEmpty ? parts[1] : parts[0], package: parts[1], web: null);
  }
  return remoteAppCatalog.where((a) => a.id == id).firstOrNull;
}

/// Opens [app] on the TV: its web link when it has one (the app takes it), else through One
/// Launcher TV (onelauncher://launch — needs it installed on the TV).
Future<void> openRemoteApp(RemoteApp app) =>
    TvRemote.instance.appLink(app.web ?? 'onelauncher://launch?package=${Uri.encodeQueryComponent(app.package)}');
