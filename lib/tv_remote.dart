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

  /// Types on the TV: replaces its focused field with [text] through the TV's keyboard
  /// protocol. If the TV didn't give us its field (some only name the app), types the change
  /// as key presses instead — Delete for removed letters, a key per new character.
  Future<void> text(String text) async {
    final before = _typed;
    _typed = text;
    try {
      final viaIme = await _ch.invokeMethod<bool>('tvText', {'text': text}) ?? false;
      if (viaIme) return;
      var same = 0;
      while (same < before.length && same < text.length && before[same] == text[same]) {
        same++;
      }
      for (var i = same; i < before.length; i++) {
        await key(TvKey.delete);
      }
      for (final ch in text.substring(same).split('')) {
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
