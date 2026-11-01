import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'apps.dart';
import 'prefs.dart';

/// App lock: locked apps open only on a fast double (or triple) tap, and taking an app out of
/// the lock needs a 4-digit PIN. The native guard (closes locked apps opened from
/// notifications / recents) is told the list via [Apps.setLockedApps] and the one app we
/// are about to open via [Apps.lockAllow].
class AppLock {
  AppLock(this.prefs, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final Prefs prefs;
  final DateTime Function() _now;

  /// Each tap must come within this of the previous one.
  static const window = Duration(milliseconds: 350);

  static final _of = Expando<AppLock>();

  /// The gate of the running app, for services without a [Prefs] (smart home).
  static AppLock? current;

  /// One gate per [Prefs] (tap counts must be shared by every screen).
  static AppLock of(Prefs prefs) => current = _of[prefs] ??= AppLock(prefs);

  String? _tapped;
  DateTime? _at;
  int _count = 0;

  bool isLocked(String package) => prefs.isLocked(package);

  /// True when [package] may open now: not locked, or this is the Nth fast tap. A swallowed tap
  /// gives a light haptic (and, through [gate], the "App not supported" toast).
  bool tap(String package) {
    if (!isLocked(package)) return true;
    final t = _now();
    final fast = _tapped == package && _at != null && t.difference(_at!) <= window;
    _count = fast ? _count + 1 : 1;
    _tapped = package;
    _at = t;
    HapticFeedback.lightImpact();
    if (_count >= prefs.lockTaps) {
      _count = 0;
      _tapped = null;
      return true;
    }
    return false;
  }

  /// Use before any launch side effects: false = swallowed (nothing else should happen);
  /// true = go ahead (a locked app was told to the native guard first).
  Future<bool> gate(String package) async {
    if (!tap(package)) {
      Apps.instance.clearLaunchFrom();
      // Same vague toast the native guard shows, so a lock doesn't announce itself.
      Apps.instance.toast('App not supported');
      return false;
    }
    if (isLocked(package)) await Apps.instance.lockAllow(package);
    return true;
  }

  /// Sends the list to the native guard (call at startup and after every change).
  Future<void> sync() => Apps.instance.setLockedApps(prefs.lockedApps);

  Future<void> _save(List<String> list) async {
    await prefs.setLockedApps(list);
    await sync();
  }

  bool get hasPin => prefs.lockPinHash != null;

  /// Locks [package]. The PIN must already exist (the UI sets it on first use).
  Future<void> lock(String package) async {
    if (isLocked(package)) return;
    await _save([...prefs.lockedApps, package]);
  }

  /// Unlocks [package] when [pin] is right.
  Future<bool> unlock(String package, String pin) async {
    if (!verifyPin(pin)) return false;
    await removeLock(package);
    return true;
  }

  /// For callers that already checked the PIN (the PIN pad).
  Future<void> removeLock(String package) => _save([...prefs.lockedApps]..remove(package));

  Future<void> setPin(String pin) => prefs.setLockPinHash(hashPin(pin));

  bool verifyPin(String pin) {
    final saved = prefs.lockPinHash;
    if (saved == null) return false;
    final i = saved.indexOf(':');
    if (i < 0) return false;
    return hashPin(pin, salt: saved.substring(0, i)) == saved;
  }

  /// 'salt:sha256(salt + pin)'.
  static String hashPin(String pin, {String? salt}) {
    salt ??= _hex(List.generate(8, (_) => Random.secure().nextInt(256)));
    return '$salt:${_hex(sha256(utf8.encode('$salt:$pin')))}';
  }

  static String _hex(List<int> b) => [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
}

const _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

/// SHA-256 (no package:crypto in this app).
List<int> sha256(List<int> data) {
  const m = 0xffffffff;
  int rr(int x, int n) => ((x >> n) | (x << (32 - n))) & m;
  final h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  final msg = [...data, 0x80];
  while (msg.length % 64 != 56) {
    msg.add(0);
  }
  final bits = data.length * 8;
  for (var i = 7; i >= 0; i--) {
    msg.add((bits >> (i * 8)) & 0xff);
  }
  final w = List<int>.filled(64, 0);
  for (var o = 0; o < msg.length; o += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = (msg[o + i * 4] << 24) | (msg[o + i * 4 + 1] << 16) | (msg[o + i * 4 + 2] << 8) | msg[o + i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rr(w[i - 15], 7) ^ rr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rr(w[i - 2], 17) ^ rr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & m;
    }
    var [a, b, c, d, e, f, g, hh] = h;
    for (var i = 0; i < 64; i++) {
      final s1 = rr(e, 6) ^ rr(e, 11) ^ rr(e, 25);
      final ch = (e & f) ^ ((~e & m) & g);
      final t1 = (hh + s1 + ch + _k[i] + w[i]) & m;
      final s0 = rr(a, 2) ^ rr(a, 13) ^ rr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & m;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & m;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & m;
    }
    final v = [a, b, c, d, e, f, g, hh];
    for (var i = 0; i < 8; i++) {
      h[i] = (h[i] + v[i]) & m;
    }
  }
  return [
    for (final x in h) ...[(x >> 24) & 0xff, (x >> 16) & 0xff, (x >> 8) & 0xff, x & 0xff],
  ];
}
