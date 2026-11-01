import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apps.dart';
import 'ui/ds.dart';

/// Caffeine quick action (chip `b:caffeine`): keeps the screen on longer by changing Android's
/// screen timeout. Tapping switches Off ↔ the chosen level ([choice]: 5 min, 10 min or Keep awake,
/// picked by long-press, prefs `caffeineChoice`, default Keep awake); Off puts back the phone's own
/// timeout (saved in prefs `caffeineOriginal` when Caffeine first turns on). While on, the icon
/// becomes the minutes ("5", "10") or an eye for Keep awake ([glyph]).
/// Needs "Modify system settings" (WRITE_SETTINGS); native side in `QuickActions.kt`.
class Caffeine {
  Caffeine._();
  static final instance = Caffeine._();
  static const _ch = MethodChannel('one_launcher/apps');
  static const _key = 'caffeineOriginal';
  static const _choiceKey = 'caffeineChoice';

  /// Android's longest timeout: the screen stays on.
  static const keepAwake = 2147483647;

  /// What a tap can turn on (long-press picks one).
  static const levels = <int>[5 * 60000, 10 * 60000, keepAwake];

  /// The level a tap turns on.
  int choice = keepAwake;

  /// The timeout Caffeine set (one of [levels]), null = off.
  final level = ValueNotifier<int?>(null);
  bool _loaded = false;

  static String nameOf(int? ms) => ms == null ? 'Off' : (ms == keepAwake ? 'Keep awake' : '${ms ~/ 60000} min');
  /// The chip's icon while on: the minutes, or an eye for Keep awake.
  static Widget glyph(int ms, {required double size, required Color color}) => ms == keepAwake
      ? Icon(Icons.visibility_rounded, size: size, color: color)
      : SizedBox.square(
          dimension: size,
          child: Center(
            child: Text(
              '${ms ~/ 60000}',
              style: TextStyle(color: color, fontSize: size * .78, height: 1, fontWeight: FontWeight.w700),
            ),
          ),
        );

  static String labelOf(int? ms) => ms == null ? 'Caffeine' : 'Caffeine · ${ms == keepAwake ? 'awake' : nameOf(ms)}';

  /// Reads the state once (the chips call it when they first show).
  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    refresh();
  }

  /// {canWrite, timeout}; also syncs [level]. A timeout someone changed elsewhere = off.
  Future<Map?> refresh() async {
    if (Apps.isDemo) return null;
    final Map? st;
    try {
      st = await _ch.invokeMapMethod('caffeineState');
    } catch (_) {
      return null;
    }
    if (st == null) return null;
    final sp = await SharedPreferences.getInstance();
    final c = sp.getInt(_choiceKey);
    if (levels.contains(c)) choice = c!;
    final timeout = (st['timeout'] as num?)?.toInt();
    if (sp.getInt(_key) != null && levels.contains(timeout)) {
      level.value = timeout;
    } else {
      if (sp.getInt(_key) != null) await sp.remove(_key); // changed in Android's settings: theirs now
      level.value = null;
    }
    return st;
  }

  /// Tap: off ↔ [choice].
  Future<void> toggle(BuildContext context) async {
    final st = await refresh();
    if (st == null || !context.mounted) return;
    await set(context, level.value == null ? choice : null, st: st);
  }

  /// Sets a level (null = off, the phone's own timeout back).
  Future<void> set(BuildContext context, int? ms, {Map? st}) async {
    st ??= await refresh();
    if (st == null || !context.mounted) return;
    if (st['canWrite'] != true) return _askPermission(context);
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getInt(_key);
    if (ms == null) {
      if (saved != null && await _apply(saved)) await sp.remove(_key);
      level.value = null;
      return;
    }
    if (saved == null) await sp.setInt(_key, (st['timeout'] as num?)?.toInt() ?? 30000);
    if (await _apply(ms)) level.value = ms;
  }

  Future<bool> _apply(int ms) async {
    try {
      return await _ch.invokeMethod<bool>('setScreenTimeout', {'ms': ms}) ?? false;
    } catch (_) {
      return false;
    }
  }

  void _askPermission(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Caffeine changes how long the screen stays on. Allow One Launcher to “Modify system settings”.'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'Allow', onPressed: () => _ch.invokeMethod('openWriteSettings')),
      ),
    );
  }

  /// Long-press: which level a tap turns on (it turns on with it), in a small menu at [anchor].
  Future<void> choose(BuildContext anchor) async {
    HapticFeedback.mediumImpact();
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero, ancestor: overlay);
    final picked = await showMenu<int>(
      context: anchor,
      color: DS.card,
      position: RelativeRect.fromRect(at & box.size, Offset.zero & overlay.size),
      items: [
        for (final ms in levels)
          CheckedPopupMenuItem(
            value: ms,
            checked: choice == ms,
            child: Text(DS.cased(nameOf(ms)), style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
          ),
      ],
    );
    if (picked == null || !anchor.mounted) return;
    choice = picked;
    await (await SharedPreferences.getInstance()).setInt(_choiceKey, picked);
    if (anchor.mounted) await set(anchor, picked);
  }
}
