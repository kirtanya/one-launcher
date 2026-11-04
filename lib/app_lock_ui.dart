import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock.dart';
import 'apps.dart';
import 'prefs.dart';
import 'ui/ds.dart';
import 'widgets.dart';

/// Asks for the PIN; true when it was right. False when dismissed.
Future<bool> askPin(BuildContext context, AppLock lock, {String title = 'Enter PIN'}) =>
    _pinSheet(context, title: title, subtitle: 'Your 4-digit app lock PIN', check: lock.verifyPin);

/// First PIN / new PIN: type it twice. Saves it; true when set.
Future<bool> setNewPin(BuildContext context, AppLock lock, {String title = 'Set a PIN'}) async {
  String? first;
  final ok = await _pinSheet(
    context,
    title: title,
    subtitle: 'Needed to unlock apps or change this later',
    confirmWith: (pin) => first = pin,
    check: (pin) => first == pin,
    confirmTitle: 'Type it again',
  );
  if (ok && first != null) await lock.setPin(first!);
  return ok && first != null;
}

/// Locking needs a PIN to exist: sets it the first time. True when the PIN is there.
Future<bool> ensurePin(BuildContext context, AppLock lock) async => lock.hasPin || await setNewPin(context, lock);

Future<bool> _pinSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required bool Function(String) check,
  void Function(String)? confirmWith,
  String? confirmTitle,
}) async {
  final done = Completer<bool>();
  await showOneSheetWith(
    context,
    scrollable: false,
    builder: (ctx) => PinPad(
      title: title,
      subtitle: subtitle,
      confirmTitle: confirmTitle,
      onFirst: confirmWith,
      check: check,
      onDone: (ok) {
        if (!done.isCompleted) done.complete(ok);
        Navigator.pop(ctx);
      },
    ),
  );
  if (!done.isCompleted) done.complete(false);
  return done.future;
}

/// 4 dots + keypad. Verify mode: [check] decides. Set mode ([onFirst] given): the first entry
/// goes to [onFirst], then [check] must match the second.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.title, required this.subtitle, required this.check, required this.onDone, this.onFirst, this.confirmTitle});
  final String title, subtitle;
  final String? confirmTitle;
  final bool Function(String) check;
  final void Function(String)? onFirst;
  final ValueChanged<bool> onDone;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _confirming = false;
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _key(String d) {
    if (_pin.length >= 4 || _shake.isAnimating) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == 4) Timer(const Duration(milliseconds: 120), _submit);
  }

  void _back() {
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _wrong() {
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0).then((_) {
      if (mounted) setState(() => _pin = '');
    });
  }

  void _submit() {
    if (!mounted) return;
    if (widget.onFirst != null && !_confirming) {
      widget.onFirst!(_pin);
      setState(() {
        _confirming = true;
        _pin = '';
      });
      return;
    }
    if (widget.check(_pin)) {
      widget.onDone(true);
    } else {
      _wrong();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => _PadKey(onTap: () => _key(d), child: Text(d, style: DS.title.copyWith(fontSize: 26, fontWeight: FontWeight.w400)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: _confirming ? (widget.confirmTitle ?? widget.title) : widget.title, subtitle: widget.subtitle),
          const SizedBox(height: DS.s16),
          AnimatedBuilder(
            animation: _shake,
            builder: (_, child) => Transform.translate(offset: Offset(math.sin(_shake.value * 6 * math.pi) * 12 * (1 - _shake.value), 0), child: child),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    key: ValueKey('pin-dot-$i'),
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? DS.ink : Colors.transparent,
                      border: Border.all(color: DS.ink, width: 1.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: DS.s24),
          for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) key(d)]),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 88, height: 72),
              key('0'),
              _PadKey(key: const ValueKey('pin-back'), onTap: _back, child: Icon(Icons.backspace_outlined, color: DS.ink)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({super.key, required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 88,
    height: 72,
    child: Center(
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: SizedBox(width: 64, height: 64, child: Center(child: child)),
      ),
    ),
  );
}

/// Lock / unlock one app (long-press menu): locking sets the PIN first time, unlocking asks for it.
Future<void> toggleAppLock(BuildContext context, Prefs prefs, AppEntry app) async {
  final lock = AppLock.of(prefs);
  if (lock.isLocked(app.package)) {
    if (await askPin(context, lock, title: 'Unlock ${app.label}')) await lock.removeLock(app.package);
    return;
  }
  if (await ensurePin(context, lock)) await lock.lock(app.package);
}

/// Settings → Apps → App lock.
Future<Object?> showAppLockPage(BuildContext context, {required Prefs prefs, required List<AppEntry> apps, double? height}) => showOneSheetWith(
  context,
  back: true,
  height: height,
  builder: (ctx) => _AppLockBody(prefs: prefs, apps: apps),
);

class _AppLockBody extends StatefulWidget {
  const _AppLockBody({required this.prefs, required this.apps});
  final Prefs prefs;
  final List<AppEntry> apps;

  @override
  State<_AppLockBody> createState() => _AppLockBodyState();
}

class _AppLockBodyState extends State<_AppLockBody> with WidgetsBindingObserver {
  String _q = '';
  bool _serviceOn = true; // assume on until asked, so the row doesn't flash
  Prefs get prefs => widget.prefs;
  AppLock get lock => AppLock.of(prefs);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final on = await Apps.instance.lockServiceOn();
    if (mounted) setState(() => _serviceOn = on);
  }

  Future<void> _switch(AppEntry a, bool on) async {
    if (on) {
      if (await ensurePin(context, lock)) await lock.lock(a.package);
    } else if (await askPin(context, lock, title: 'Unlock ${a.label}')) {
      await lock.removeLock(a.package);
    }
  }

  Future<void> _changePin() async {
    if (!lock.hasPin) {
      await setNewPin(context, lock);
    } else if (await askPin(context, lock, title: 'Current PIN')) {
      if (!mounted) return;
      await setNewPin(context, lock, title: 'New PIN');
    }
  }

  Future<void> _setTaps(int n) async {
    if (n == prefs.lockTaps) return;
    // Changing the tap count needs the PIN once one exists.
    if (lock.hasPin && !await askPin(context, lock, title: 'Change taps')) return;
    await prefs.setLockTaps(n);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final q = _q.trim().toLowerCase();
        final list = [
          for (final a in widget.apps)
            if (!a.isShortcut && (q.isEmpty || a.label.toLowerCase().contains(q))) a,
        ]..sort((a, b) {
            final la = lock.isLocked(a.package), lb = lock.isLocked(b.package);
            return la == lb ? a.label.toLowerCase().compareTo(b.label.toLowerCase()) : (la ? -1 : 1);
          });
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
              child: SheetHeader(title: 'App lock', subtitle: 'Locked apps open only on a fast double or triple tap'),
            ),
            if (!_serviceOn)
              ListTile(
                key: const ValueKey('lock-service-row'),
                contentPadding: const EdgeInsets.symmetric(horizontal: DS.s24),
                leading: Icon(Icons.shield_outlined, color: DS.ink),
                title: Text('Keep locked apps closed when opened from notifications or recents', style: DS.rowTitle.copyWith(fontSize: 14)),
                subtitle: Text('Allow Usage access for One Launcher', style: DS.rowSub),
                trailing: Icon(Icons.chevron_right_rounded, color: DS.inkFaint),
                onTap: Apps.instance.openUsageAccess,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: DS.s8),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 2, label: Text('Double tap')),
                  ButtonSegment(value: 3, label: Text('Triple tap')),
                ],
                selected: {prefs.lockTaps},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _setTaps(s.first),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: DS.s24),
              leading: Icon(Icons.pin_outlined, color: DS.ink),
              title: Text(lock.hasPin ? 'Change PIN' : 'Set PIN', style: DS.rowTitle),
              subtitle: Text(lock.hasPin ? '4 digits' : 'Also set the first time you lock an app', style: DS.rowSub),
              onTap: _changePin,
            ),
            SheetSearchField(hint: 'Search apps', onChanged: (v) => setState(() => _q = v)),
            for (final a in list)
              ListTile(
                key: ValueKey('lock-${a.package}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: DS.s24),
                leading: AppIcon(a, size: 36),
                title: Text(a.label, style: DS.rowTitle),
                trailing: Switch(value: lock.isLocked(a.package), onChanged: (v) => _switch(a, v)),
                onTap: () => _switch(a, !lock.isLocked(a.package)),
              ),
            const SizedBox(height: DS.s8),
          ],
        );
      },
    );
  }
}
