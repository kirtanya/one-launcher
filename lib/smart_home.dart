import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'apps.dart';

/// Smart home: lights, plugs and AC through Google Home.
///
/// Dart side only for now. The Kotlin bridge (wrapping the Google Home APIs SDK,
/// developers.home.google.com/apis/android/sdk) is pending; until it exists the channel is
/// missing, which shows up as [SmartHomeStatus.unavailable] and the UI offers a setup card.
///
/// ## Channel contract: `MethodChannel('one_launcher/home')`
/// Dart → Kotlin:
/// - `status` → `String`: `"signedOut"` (no Google account / permissions yet) or `"ready"`.
/// - `connect` → `String` (same values as `status`): runs sign-in + the Home permission flow.
///   May throw `PlatformException` (message shown to the user).
/// - `devices` → `List<Map>`: every device the user granted, one map each:
///   `id` String (stable), `name` String, `room` String? (structure room, may be empty),
///   `type` `"light"|"plug"|"ac"|"fan"|"switch"|"other"`, `online` bool, `on` bool,
///   `brightness` int 0..100? (lights), `setpoint` double? (°C, AC),
///   `mode` `"cool"|"heat"|"auto"|"fan"|"off"`? (AC).
///   Lights may add: `canColor` / `canTemp` bool, `hue` double 0..360, `saturation` double 0..1,
///   `colorTempK` int (Kelvin) with `minK` / `maxK`, `colorMode` `"color"|"temp"` (which one
///   it shows now), `effects` bool (sleep/wake supported) and `effect` `"sleep"|"wake"`? (running).
/// - `set` `{id: String, trait, value}` → void; throw a `PlatformException` when the command
///   fails (Dart rolls the optimistic change back). Traits: `on` bool, `brightness` int 0..100,
///   `setpoint` double °C, `mode` String, `color` `{h: 0..360, s: 0..1}`, `colorTempK` int,
///   `effect` `"sleep"|"wake"|"stop"`.
///   For an AC, `on` is its OnOff trait; mode `"off"` is the same as `on: false`.
/// Kotlin → Dart (via `invokeMethod` on the same channel):
/// - `homeChanged` with the same `List<Map>` as `devices`: pushed on any device change.
enum SmartHomeStatus { unavailable, signedOut, loading, ready, error }

enum SmartType { light, plug, ac, fan, switch_, other }

enum AcMode { cool, heat, auto, fan, off }

class SmartDevice {
  const SmartDevice({
    required this.id,
    required this.name,
    this.room = '',
    this.type = SmartType.other,
    this.online = true,
    this.on = false,
    this.brightness,
    this.colorTempK,
    this.minK = 2000,
    this.maxK = 6500,
    this.hue,
    this.saturation,
    this.colorMode,
    this.canColor = false,
    this.canTemp = false,
    this.effects = false,
    this.effect,
    this.setpoint,
    this.mode,
  });

  factory SmartDevice.fromMap(Map m) => SmartDevice(
    id: m['id'] as String,
    name: m['name'] as String? ?? 'Device',
    room: m['room'] as String? ?? '',
    type: switch (m['type']) {
      'light' => SmartType.light,
      'plug' => SmartType.plug,
      'ac' => SmartType.ac,
      'fan' => SmartType.fan,
      'switch' => SmartType.switch_,
      _ => SmartType.other,
    },
    online: m['online'] as bool? ?? true,
    on: m['on'] as bool? ?? false,
    brightness: (m['brightness'] as num?)?.toInt().clamp(0, 100),
    colorTempK: (m['colorTempK'] as num?)?.toInt(),
    minK: (m['minK'] as num?)?.toInt() ?? 2000,
    maxK: (m['maxK'] as num?)?.toInt() ?? 6500,
    hue: (m['hue'] as num?)?.toDouble(),
    saturation: (m['saturation'] as num?)?.toDouble(),
    colorMode: m['colorMode'] as String?,
    canColor: m['canColor'] as bool? ?? false,
    canTemp: m['canTemp'] as bool? ?? false,
    effects: m['effects'] as bool? ?? false,
    effect: m['effect'] as String?,
    setpoint: (m['setpoint'] as num?)?.toDouble(),
    mode: AcMode.values.where((e) => e.name == m['mode']).firstOrNull,
  );

  final String id, name, room;
  final SmartType type;
  final bool online, on;

  /// 0–100, lights that dim.
  final int? brightness;

  /// Warm/cool white in Kelvin (within [minK]..[maxK]), for lights that have it ([canTemp]).
  final int? colorTempK;
  final int minK, maxK;

  /// Colour as hue 0..360 and saturation 0..1, for lights that have it ([canColor]).
  final double? hue, saturation;

  /// What the light shows now: `"color"` or `"temp"` (white); null when unknown.
  final String? colorMode;
  final bool canColor, canTemp;

  /// Sleep / wake effects supported, and the one running (`"sleep"`, `"wake"`).
  final bool effects;
  final String? effect;

  /// AC target in °C and its mode.
  final double? setpoint;
  final AcMode? mode;

  bool get dimmable => brightness != null;

  /// The light's colour on screen: its hue, or its white's warmth; null for plain lights.
  Color? get shade {
    final white = colorMode == 'temp' || (colorMode == null && hue == null);
    if (!white && hue != null) return HSVColor.fromAHSV(1, hue!.clamp(0, 360), (saturation ?? 1).clamp(0, 1), 1).toColor();
    if (colorTempK != null) return kelvinColour(colorTempK!);
    return null;
  }

  SmartDevice copyWith({
    bool? on,
    int? brightness,
    double? setpoint,
    AcMode? mode,
    double? hue,
    double? saturation,
    int? colorTempK,
    String? colorMode,
    String? effect,
    bool clearEffect = false,
  }) => SmartDevice(
    id: id,
    name: name,
    room: room,
    type: type,
    online: online,
    on: on ?? this.on,
    brightness: brightness ?? this.brightness,
    colorTempK: colorTempK ?? this.colorTempK,
    minK: minK,
    maxK: maxK,
    hue: hue ?? this.hue,
    saturation: saturation ?? this.saturation,
    colorMode: colorMode ?? this.colorMode,
    canColor: canColor,
    canTemp: canTemp,
    effects: effects,
    effect: clearEffect ? null : effect ?? this.effect,
    setpoint: setpoint ?? this.setpoint,
    mode: mode ?? this.mode,
  );
}

/// A white light's colour at [k] Kelvin (warm amber → neutral → cool blue), for the screen only.
Color kelvinColour(int k) {
  const stops = [(2000, Color(0xFFFFA24A)), (2700, Color(0xFFFFC27F)), (4000, Color(0xFFFFE9CF)), (5000, Color(0xFFFFF6EC)), (6500, Color(0xFFDDE8FF))];
  if (k <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    if (k <= stops[i].$1) {
      final (a, ca) = stops[i - 1];
      final (b, cb) = stops[i];
      return Color.lerp(ca, cb, (k - a) / (b - a))!;
    }
  }
  return stops.last.$2;
}

class SmartHomeState {
  const SmartHomeState({
    this.status = SmartHomeStatus.unavailable,
    this.devices = const [],
    this.error,
  });
  final SmartHomeStatus status;
  final List<SmartDevice> devices;

  /// The last failure, for the `error` status and for a command that was rolled back.
  final String? error;

  /// Rooms in the order their first device appears; devices without a room go under "Other".
  List<String> get rooms =>
      {for (final d in devices) d.room.isEmpty ? 'Other' : d.room}.toList();

  List<SmartDevice> inRoom(String room) => [
    for (final d in devices)
      if ((d.room.isEmpty ? 'Other' : d.room) == room) d,
  ];

  SmartDevice? byId(String id) => devices.where((d) => d.id == id).firstOrNull;
}

class SmartHome {
  SmartHome._();
  static final instance = SmartHome._();

  static const googleHomePackage = 'com.google.android.apps.chromecast.app';
  static const _ch = MethodChannel('one_launcher/home');

  final state = ValueNotifier<SmartHomeState>(const SmartHomeState());
  bool _listening = false, _demoLocal = false, _demo = false;

  SmartHomeState get value => state.value;

  void _listen() {
    if (_listening) return;
    _listening = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'homeChanged') _apply(call.arguments);
    });
  }

  void _apply(Object? raw) {
    final list = [
      for (final m in (raw as List? ?? const [])) SmartDevice.fromMap(m as Map),
    ];
    state.value = SmartHomeState(status: SmartHomeStatus.ready, devices: list);
  }

  /// Asks the bridge where things stand and loads the devices. Safe to call often.
  Future<void> refresh() async {
    if (_demo) return;
    _listen();
    try {
      final s = await _ch.invokeMethod<String>('status');
      if (s == 'ready') {
        state.value = SmartHomeState(
          status: SmartHomeStatus.loading,
          devices: value.devices,
        );
        _apply(await _ch.invokeMethod<List>('devices'));
      } else {
        state.value = const SmartHomeState(status: SmartHomeStatus.signedOut);
      }
    } on MissingPluginException {
      state.value = const SmartHomeState(status: SmartHomeStatus.unavailable);
    } catch (e) {
      state.value = SmartHomeState(
        status: SmartHomeStatus.error,
        error: _msg(e),
      );
    }
  }

  /// Sign in to Google Home and grant access, then load the devices.
  Future<void> connect() async {
    _listen();
    state.value = const SmartHomeState(status: SmartHomeStatus.loading);
    try {
      final s = await _ch.invokeMethod<String>('connect');
      if (s == 'ready') {
        _apply(await _ch.invokeMethod<List>('devices'));
      } else {
        state.value = const SmartHomeState(status: SmartHomeStatus.signedOut);
      }
    } on MissingPluginException {
      state.value = const SmartHomeState(status: SmartHomeStatus.unavailable);
    } catch (e) {
      state.value = SmartHomeState(
        status: SmartHomeStatus.error,
        error: _msg(e),
      );
    }
  }

  static String _msg(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : '$e';

  /// Sends one change. The screen updates at once; if the bridge says no, it goes back.
  Future<void> set(String id, String trait, Object value) async {
    final before = this.value.byId(id);
    if (before == null) return;
    _replace(before, _optimistic(before, trait, value));
    if (_demoLocal) return;
    try {
      await _ch.invokeMethod<void>('set', {
        'id': id,
        'trait': trait,
        'value': value,
      });
    } on MissingPluginException {
      _rollback(before, null);
      state.value = SmartHomeState(
        status: SmartHomeStatus.unavailable,
        devices: const [],
      );
    } catch (e) {
      _rollback(before, _msg(e));
    }
  }

  Future<void> toggle(SmartDevice d) => set(d.id, 'on', !d.on);

  /// Every online device in [room] on or off at once (each one rolls back on its own).
  Future<void> setRoom(String room, bool on) => Future.wait([
    for (final d in value.inRoom(room))
      if (d.online && d.on != on) set(d.id, 'on', on),
  ]);

  static SmartDevice _optimistic(SmartDevice d, String trait, Object v) =>
      switch (trait) {
        'on' => d.copyWith(
          on: v as bool,
          mode: d.type == SmartType.ac && v == true && d.mode == AcMode.off
              ? AcMode.cool
              : null,
        ),
        'brightness' => d.copyWith(
          brightness: (v as num).toInt().clamp(0, 100),
          on: v > 0 ? true : null,
        ),
        'setpoint' => d.copyWith(setpoint: (v as num).toDouble()),
        'color' => d.copyWith(
          hue: ((v as Map)['h'] as num).toDouble(),
          saturation: (v['s'] as num).toDouble(),
          colorMode: 'color',
          on: true,
        ),
        'colorTempK' => d.copyWith(colorTempK: (v as num).toInt(), colorMode: 'temp', on: true),
        'effect' => v == 'stop' ? d.copyWith(clearEffect: true) : d.copyWith(effect: v as String),
        'mode' => d.copyWith(
          mode: AcMode.values.firstWhere(
            (m) => m.name == v,
            orElse: () => d.mode ?? AcMode.auto,
          ),
          on: v != 'off',
        ),
        _ => d,
      };

  void _replace(SmartDevice old, SmartDevice now) {
    final s = value;
    state.value = SmartHomeState(
      status: s.status,
      devices: [for (final d in s.devices) d.id == old.id ? now : d],
    );
  }

  void _rollback(SmartDevice before, String? error) {
    final s = value;
    state.value = SmartHomeState(
      status: s.status,
      devices: [for (final d in s.devices) d.id == before.id ? before : d],
      error: error,
    );
  }

  /// Opens the Google Home app (through the launcher's own launch path), or its Play Store
  /// page when it isn't installed.
  Future<void> openGoogleHome() async {
    final installed = (await Apps.instance.list()).any(
      (a) => a.package == googleHomePackage,
    );
    if (installed) return Apps.instance.launch(googleHomePackage);
    return Apps.instance.playSearch('Google Home');
  }

  /// Fake devices: 2 rooms. [local] changes stay on screen (no bridge); tests pass false to
  /// go through a mocked channel.
  void debugDemo({bool local = true}) {
    _demo = true;
    _demoLocal = local;
    state.value = const SmartHomeState(
      status: SmartHomeStatus.ready,
      devices: [
        SmartDevice(
          id: 'l1',
          name: 'Ceiling light',
          room: 'Living room',
          type: SmartType.light,
          on: true,
          brightness: 70,
          colorTempK: 3000,
          hue: 280,
          saturation: .8,
          colorMode: 'color',
          canColor: true,
          canTemp: true,
          effects: true,
        ),
        SmartDevice(
          id: 'p1',
          name: 'Lamp plug',
          room: 'Living room',
          type: SmartType.plug,
        ),
        SmartDevice(
          id: 'a1',
          name: 'AC',
          room: 'Living room',
          type: SmartType.ac,
          on: true,
          setpoint: 24,
          mode: AcMode.cool,
        ),
        SmartDevice(
          id: 'l2',
          name: 'Bedside light',
          room: 'Bedroom',
          type: SmartType.light,
          brightness: 40,
        ),
        SmartDevice(
          id: 'a2',
          name: 'AC',
          room: 'Bedroom',
          type: SmartType.ac,
          setpoint: 26,
          mode: AcMode.off,
        ),
      ],
    );
  }

  /// Back to the first-run state (tests).
  @visibleForTesting
  void reset() {
    _demo = _demoLocal = false;
    state.value = const SmartHomeState();
  }
}
