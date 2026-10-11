import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../apps.dart';
import '../prefs.dart';

/// Lighter effects for slower phones, so the launcher stays smooth everywhere.
///
/// [lite] is on when the user chose it (Settings → Lighter effects), or in 'auto' mode when
/// the phone is a budget one (Android's low-RAM flag, < 4 GB RAM or ≤ 4 cores) or was seen
/// dropping frames during use. Lite turns off the purely decorative effects that cost the
/// most per frame: edge scaling, pop-ins, page fades, the landing animation, big shadows.
class Perf {
  Perf._();

  static final lite = ValueNotifier<bool>(false);

  /// Auto mode found this phone slow (from its specs or from dropped frames).
  static bool get autoSlow => _slowPhone || _slowFrames;

  static Prefs? _prefs;
  static bool _slowPhone = false, _slowFrames = false, _watching = false;

  static Future<void> init(Prefs prefs) async {
    _prefs = prefs;
    _slowFrames = prefs.slowFrames;
    final d = await Apps.instance.deviceClass();
    _slowPhone = d['lowRam'] == true || ((d['ramGb'] as num?) ?? 8) < 3.6 || ((d['cores'] as num?) ?? 8) <= 4;
    prefs.addListener(_apply);
    _apply();
    if (!_slowFrames && !_watching) {
      _watching = true;
      _since = Stopwatch()..start();
      SchedulerBinding.instance.addTimingsCallback(_watch);
    }
  }

  static void _apply() {
    final mode = _prefs?.effects ?? 'auto';
    lite.value = const bool.fromEnvironment('FORCE_LITE') || mode == 'lite' || (mode == 'auto' && autoSlow); // FORCE_LITE: measuring builds
  }

  // Dropped-frame watch: frames come in while the user scrolls / swipes. In each window of 90
  // frames, count those that took longer than a 60 Hz frame plus slack (20 ms from vsync to
  // pixels). Three windows in a row with over a fifth of them slow → this phone needs lite.
  static int _frames = 0, _slow = 0, _badWindows = 0;
  static Stopwatch? _since;

  static void _watch(List<FrameTiming> timings) {
    // Not during start-up (first build, icons loading): every phone is busy then.
    if ((_since?.elapsed ?? Duration.zero) < const Duration(seconds: 8)) return;
    for (final t in timings) {
      _frames++;
      if (t.totalSpan.inMicroseconds > 20000) _slow++;
      if (_frames < 90) continue;
      _badWindows = _slow > 18 ? _badWindows + 1 : 0;
      _frames = _slow = 0;
      if (_badWindows >= 3) {
        _slowFrames = true;
        _prefs?.setSlowFrames(true);
        SchedulerBinding.instance.removeTimingsCallback(_watch);
        _watching = false;
        _apply();
        return;
      }
    }
  }
}
