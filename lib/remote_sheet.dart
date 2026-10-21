import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';
import 'tv_remote.dart';
import 'ui/components.dart' show confirmReset;
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'widgets.dart';

/// Long-press on the remote button: hide it (Settings → TV remote → Remote button brings it back).
void offerHideRemote(BuildContext context, {required Prefs prefs}) {
  HapticFeedback.mediumImpact();
  showOneSheet(
    context,
    header: const SheetHeader(title: 'TV remote button', subtitle: 'Turn it back on in Settings → TV remote'),
    actions: [
      SheetAction(Icons.visibility_off_outlined, 'Hide remote button', () {
        Navigator.pop(context);
        prefs.setRemoteButton(false);
      }),
      SheetAction(Icons.settings_remote_rounded, 'Open remote', () {
        Navigator.pop(context);
        showTvRemote(context, prefs: prefs);
      }),
    ],
  );
}

/// Dock → TV remote. First time: find the TV (or type its address) and pair with the code it
/// shows. After that it connects straight away and shows the remote.
Future<void> showTvRemote(BuildContext context, {required Prefs prefs}) {
  HapticFeedback.selectionClick();
  return showOneSheetWith(
    context,
    height: MediaQuery.sizeOf(context).height, // full screen
    keyboard: true, // typing: the sheet's content sits above the phone keyboard
    fill: true,
    scrollable: false,
    builder: (ctx) => _RemoteSheet(prefs: prefs),
  );
}

class _RemoteSheet extends StatefulWidget {
  const _RemoteSheet({required this.prefs});
  final Prefs prefs;

  @override
  State<_RemoteSheet> createState() => _RemoteSheetState();
}

class _RemoteSheetState extends State<_RemoteSheet> {
  final tv = TvRemote.instance;
  Prefs get prefs => widget.prefs;

  // Setup state.
  List<(String, String)>? _found; // null = still looking
  String? _pairingHost, _pairingName; // waiting for the code
  String? _setupError;
  bool _busy = false;
  final _ip = TextEditingController();
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    final host = prefs.tvHost;
    if (host != null) {
      if (tv.status.value != TvStatus.connected) tv.connect(host);
    } else {
      _discover();
    }
  }

  @override
  void dispose() {
    _ip.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() => _found = null);
    final list = await tv.discover();
    if (mounted) setState(() => _found = list);
  }

  Future<void> _startPair(String host, String name) async {
    setState(() {
      _busy = true;
      _setupError = null;
    });
    final err = await tv.pairStart(host);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) {
        _pairingHost = host;
        _pairingName = name;
        _code.clear();
      } else {
        _setupError = 'Couldn’t reach the TV at $host. Is it on, and on the same Wi-Fi?';
      }
    });
  }

  Future<void> _finishPair() async {
    setState(() {
      _busy = true;
      _setupError = null;
    });
    final err = await tv.pairFinish(_code.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _setupError = err;
      });
      return;
    }
    HapticFeedback.mediumImpact();
    await prefs.setTv(_pairingHost, name: _pairingName);
    await tv.connect(_pairingHost!);
    if (mounted) {
      setState(() {
        _busy = false;
        _pairingHost = null;
      });
    }
  }

  Future<void> _forget() async {
    if (!await confirmReset(context, title: 'Forget ${prefs.tvName}?', body: 'The remote stops working until you pair again with a code on the TV.', action: 'Forget')) {
      return;
    }
    final host = prefs.tvHost;
    if (host != null) await tv.forget(host);
    await prefs.setTv(null);
    _discover();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: prefs, builder: (context, _) => prefs.tvHost == null ? _setup(context) : _remote(context));
  }

  // ---- Setup: find + pair ----------------------------------------------------------------

  Widget _setup(BuildContext context) {
    final pairing = _pairingHost != null;
    return ListView(
      padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, MediaQuery.viewInsetsOf(context).bottom + DS.s24),
      children: [
        SheetHeader(
          title: pairing ? 'Enter the code' : 'Connect your TV',
          subtitle: pairing ? 'It’s on your TV screen now' : 'Google TV or Android TV on the same Wi-Fi',
        ),
        const SizedBox(height: DS.s24),
        if (pairing) ...[
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            textAlign: TextAlign.center,
            cursorColor: DS.ink,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')), _UpperCase()],
            style: DS.title.copyWith(fontSize: 34, letterSpacing: 8),
            onSubmitted: (_) => _finishPair(),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              filled: true,
              fillColor: DS.cardMuted,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(DS.rMedia), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: DS.s16),
          _Primary(label: _busy ? 'Pairing…' : 'Pair', onTap: _busy ? null : _finishPair),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _pairingHost = null),
            child: Text('Back', style: DS.rowSub),
          ),
        ] else ...[
          Text('Found on your Wi-Fi', style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 13)),
          const SizedBox(height: DS.s8),
          if (_found == null)
            const Padding(
              padding: EdgeInsets.all(DS.s24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_found!.isEmpty)
            Text('No TV found. Make sure it’s on, or type its address below (TV Settings → Network → IP address).', style: DS.rowSub)
          else
            for (final (name, host) in _found!) _TvRow(name: name, host: host, onTap: _busy ? null : () => _startPair(host, name)),
          TextButton.icon(
            onPressed: _found == null ? null : _discover,
            icon: Icon(Icons.refresh_rounded, color: DS.ink),
            label: Text('Search again', style: DS.rowTitle.copyWith(fontSize: 14)),
          ),
          const SizedBox(height: DS.s16),
          Text('Or type the TV’s address', style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 13)),
          const SizedBox(height: DS.s8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ip,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  cursorColor: DS.ink,
                  style: DS.rowTitle,
                  onSubmitted: (_) => _startPair(_ip.text.trim(), 'TV'),
                  decoration: InputDecoration(
                    hintText: '192.168.1.23',
                    hintStyle: DS.rowSub,
                    filled: true,
                    fillColor: DS.cardMuted,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : DS.s24), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: DS.s8),
              _Primary(label: 'Connect', onTap: _busy ? null : () => _startPair(_ip.text.trim(), 'TV'), compact: true),
            ],
          ),
        ],
        if (_setupError != null) ...[const SizedBox(height: DS.s16), Text(_setupError!, style: DS.rowSub.copyWith(color: DS.alert))],
      ],
    );
  }

  // ---- The remote ------------------------------------------------------------------------

  Widget _remote(BuildContext context) {
    return ValueListenableBuilder<TvStatus>(
      valueListenable: tv.status,
      builder: (context, status, _) {
        final live = status == TvStatus.connected;
        return Column(
          children: [
            // Header: TV name + status, power, more.
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SheetHeader(
                      yours: true, // the TV's own name
                      title: prefs.tvName,
                      subtitle: switch (status) {
                        TvStatus.connected => 'Connected',
                        TvStatus.connecting => 'Connecting…',
                        _ => tv.error.value ?? 'Not connected',
                      },
                    ),
                  ),
                  _Round(
                    icon: Icons.power_settings_new_rounded,
                    tooltip: 'Power',
                    danger: true,
                    onTap: live ? () => _press(TvKey.power, strong: true) : null,
                    onHold: live ? (d) => _hold(TvKey.power, d) : null,
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    icon: Icon(Icons.more_vert_rounded, color: DS.ink),
                    color: DS.card,
                    onSelected: (v) => v == 'forget' ? _forget() : tv.connect(prefs.tvHost!),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'reconnect',
                        child: Text('Reconnect', style: DS.rowTitle),
                      ),
                      PopupMenuItem(
                        value: 'forget',
                        child: Text('Forget this TV', style: DS.rowTitle),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Typing on the TV (a text field is focused there, or the keyboard button): the remote
            // makes way for a typing panel that sits right above the phone keyboard.
            Expanded(
              child: ValueListenableBuilder<(String, String)?>(
                valueListenable: tv.ime,
                builder: (context, ime, remote) => AnimatedSwitcher(
                  duration: Motion.snapDuration,
                  child: ime != null && live
                      ? _TypingPanel(key: ValueKey('typing:${ime.$2}'), start: ime.$1, label: ime.$2, onKey: _press)
                      : KeyedSubtree(key: const ValueKey('remote'), child: remote!),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: AnimatedOpacity(
                        duration: Motion.snapDuration,
                        opacity: live ? 1 : .4,
                        child: IgnorePointer(
                          ignoring: !live,
                          child: LayoutBuilder(
                            builder: (context, c) {
                              final pad = (c.maxWidth * .74).clamp(220.0, 300.0);
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _DPad(size: pad, onKey: _press, onHold: _hold),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _Round(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => _press(TvKey.back), onHold: (d) => _hold(TvKey.back, d)),
                                      _Round(icon: Icons.home_rounded, tooltip: 'Home', onTap: () => _press(TvKey.home), onHold: (d) => _hold(TvKey.home, d)),
                                      _Round(
                                        icon: Icons.play_arrow_rounded,
                                        tooltip: 'Play / pause',
                                        onTap: () => _press(TvKey.playPause),
                                        onHold: (d) => _hold(TvKey.playPause, d),
                                      ),
                                      _Round(icon: Icons.input_rounded, tooltip: 'Input', onTap: () => _press(TvKey.input), onHold: (d) => _hold(TvKey.input, d)),
                                      _Round(
                                        icon: Icons.keyboard_rounded,
                                        tooltip: 'Type on TV',
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          tv.ime.value ??= ('', '');
                                        },
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                                    child: Column(
                                      children: [
                                        _Volume(onKey: _press, volume: tv.volume),
                                        const SizedBox(height: DS.s8),
                                        _Brightness(prefs: prefs),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    height: 40,
                                    // A handful of chips: built all at once (no lazy list).
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                                      child: Row(
                                        children: [
                                          // Quick apps: the user's own (Edit at the end).
                                          for (final app in [for (final id in prefs.remoteApps) ?remoteAppFor(id)])
                                            Padding(
                                              padding: const EdgeInsets.only(right: DS.s8),
                                              child: ActionChip(
                                                label: Text(app.name, style: DS.rowTitle.copyWith(fontSize: 14)),
                                                backgroundColor: DS.cardMuted,
                                                side: BorderSide.none,
                                                shape: DS.metro ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)) : const StadiumBorder(),
                                                onPressed: () {
                                                  HapticFeedback.selectionClick();
                                                  openRemoteApp(app);
                                                },
                                              ),
                                            ),
                                          ActionChip(
                                            avatar: Icon(Icons.edit_outlined, size: 18, color: DS.ink),
                                            label: Text('Edit', style: DS.rowTitle.copyWith(fontSize: 14)),
                                            tooltip: 'Edit quick apps',
                                            backgroundColor: Colors.transparent,
                                            side: BorderSide(color: DS.hairline),
                                            shape: DS.metro ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)) : const StadiumBorder(),
                                            onPressed: () => showRemoteAppsEditor(context, prefs: prefs),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!live && status != TvStatus.connecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s16),
                child: _Primary(label: 'Reconnect', onTap: () => tv.connect(prefs.tvHost!)),
              ),
          ],
        );
      },
    );
  }

  void _press(int code, {bool strong = false}) {
    strong ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
    tv.key(code);
  }

  /// Like holding a button on the physical remote: the key goes down when the hold
  /// starts and comes up when the finger lifts, so the TV sees a real long press.
  void _hold(int code, bool down) {
    if (down) HapticFeedback.heavyImpact();
    tv.key(code, press: down ? TvPress.longStart : TvPress.longEnd);
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class _TvRow extends StatelessWidget {
  const _TvRow({required this.name, required this.host, required this.onTap});
  final String name, host;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: DS.s8),
    child: Material(
      color: DS.cardMuted,
      borderRadius: BorderRadius.circular(DS.rMedia),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(DS.s16),
          child: Row(
            children: [
              Icon(Icons.tv_rounded, color: DS.ink),
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
                    Text(host, style: DS.rowSub.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: DS.inkFaint),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Primary extends StatelessWidget {
  const _Primary({required this.label, required this.onTap, this.compact = false});
  final String label;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    width: compact ? null : double.infinity,
    child: FilledButton(
      // Classic: an ink pill. Metro (Tiles): a flat accent box, lowercase.
      style: FilledButton.styleFrom(
        backgroundColor: DS.metro ? DS.hero : DS.ink,
        foregroundColor: DS.metro ? Colors.white : DS.card,
        shape: DS.metro ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)) : const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: DS.s24),
      ),
      onPressed: onTap,
      child: Text(
        DS.cased(label),
        style: DS.rowTitle.copyWith(color: DS.metro ? Colors.white : DS.card, fontWeight: DS.metro ? FontWeight.w400 : FontWeight.w600),
      ),
    ),
  );
}

/// A round remote button (56 pt).
class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.tooltip, required this.onTap, this.onHold, this.danger = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Hold support (true = finger down, false = lifted). Off → the tooltip shows on hold.
  final void Function(bool down)? onHold;
  final bool danger;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    triggerMode: onHold == null ? null : TooltipTriggerMode.manual,
    child: _Hold(
      onHold: onHold,
      child: Pressable(
        scale: .9,
        child: Material(
          color: danger ? DS.alert.withValues(alpha: .14) : DS.cardMuted,
          // Metro: square tiles (the tile corner setting) instead of circles.
          shape: DS.metro ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)) : const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(dimension: 56, child: Icon(icon, color: danger ? DS.alert : DS.ink)),
          ),
        ),
      ),
    ),
  );
}

/// Turns a hold into a TV long press: [onHold] (true) once the hold is recognised,
/// [onHold] (false) when the finger lifts or the gesture is lost. A quick tap passes
/// through to the child.
class _Hold extends StatefulWidget {
  const _Hold({required this.onHold, required this.child});
  final void Function(bool down)? onHold;
  final Widget child;

  @override
  State<_Hold> createState() => _HoldState();
}

class _HoldState extends State<_Hold> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down) return;
    _down = down;
    widget.onHold?.call(down);
  }

  @override
  void dispose() {
    _set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.onHold == null
      ? widget.child
      : GestureDetector(onLongPressStart: (_) => _set(true), onLongPressEnd: (_) => _set(false), onLongPressCancel: () => _set(false), child: widget.child);
}

/// The round D-pad: four arrow zones around an OK button. Holding an arrow repeats it.
class _DPad extends StatelessWidget {
  const _DPad({required this.size, required this.onKey, this.onHold});
  final double size;
  final void Function(int code, {bool strong}) onKey;
  final void Function(int code, bool down)? onHold;

  @override
  Widget build(BuildContext context) {
    final ok = size * .38;
    Widget arrow(Alignment at, IconData icon, int code, String label) => Align(
      alignment: at,
      child: _Repeat(
        onKey: () => onKey(code),
        child: Tooltip(
          message: label,
          child: SizedBox(
            width: size * .3,
            height: size * .3,
            child: Icon(icon, size: 34, color: DS.ink),
          ),
        ),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        // Metro: a square pad (tile corners); Classic: round.
        decoration: DS.metro
            ? BoxDecoration(color: DS.cardMuted, borderRadius: BorderRadius.circular(DS.rCard))
            : BoxDecoration(color: DS.cardMuted, shape: BoxShape.circle),
        child: Stack(
          children: [
            arrow(Alignment.topCenter, Icons.keyboard_arrow_up_rounded, TvKey.up, 'Up'),
            arrow(Alignment.bottomCenter, Icons.keyboard_arrow_down_rounded, TvKey.down, 'Down'),
            arrow(Alignment.centerLeft, Icons.keyboard_arrow_left_rounded, TvKey.left, 'Left'),
            arrow(Alignment.centerRight, Icons.keyboard_arrow_right_rounded, TvKey.right, 'Right'),
            Center(
              child: Tooltip(
                message: 'OK',
                triggerMode: onHold == null ? null : TooltipTriggerMode.manual,
                child: _Hold(
                  onHold: onHold == null ? null : (d) => onHold!(TvKey.ok, d),
                  child: Pressable(
                    scale: .92,
                    child: Material(
                      color: DS.metro ? DS.hero : DS.ink,
                      shape: DS.metro ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)) : const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onKey(TvKey.ok, strong: true),
                        child: SizedBox.square(
                          dimension: ok,
                          child: Center(
                            child: Text(
                              DS.cased('OK'),
                              style: DS.rowTitle.copyWith(
                                color: DS.metro ? Colors.white : DS.card,
                                fontWeight: DS.metro ? FontWeight.w300 : FontWeight.w600,
                                fontSize: DS.metro ? 22 : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tap = one press; hold = repeat (every 140 ms) until let go.
class _Repeat extends StatefulWidget {
  const _Repeat({required this.onKey, required this.child});
  final VoidCallback onKey;
  final Widget child;

  @override
  State<_Repeat> createState() => _RepeatState();
}

class _RepeatState extends State<_Repeat> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onKey,
    onLongPressStart: (_) => _timer = Timer.periodic(const Duration(milliseconds: 140), (_) => widget.onKey()),
    onLongPressEnd: (_) => _timer?.cancel(),
    onLongPressCancel: () => _timer?.cancel(),
    child: widget.child,
  );
}

/// Volume: − · slider · + with the TV's level (drag to a level — the remote presses volume
/// keys until the TV gets there); tap the speaker to mute. Before the TV reports its level,
/// just − / mute / +.
class _Volume extends StatelessWidget {
  const _Volume({required this.onKey, required this.volume});
  final void Function(int code, {bool strong}) onKey;
  final ValueListenable<(int, int, bool)?> volume;

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: DS.s4),
    decoration: BoxDecoration(color: DS.cardMuted, borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : 32)),
    child: ValueListenableBuilder<(int, int, bool)?>(
      valueListenable: volume,
      builder: (context, v, _) => Row(
        children: [
          Tooltip(
            message: 'Mute',
            child: IconButton(
              onPressed: () => onKey(TvKey.mute),
              icon: Icon(v?.$3 == true ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: v?.$3 == true ? DS.alert : DS.ink),
            ),
          ),
          _Repeat(
            onKey: () => onKey(TvKey.volumeDown),
            child: Tooltip(
              message: 'Volume down',
              child: SizedBox(width: 36, height: 56, child: Icon(Icons.remove_rounded, color: DS.ink)),
            ),
          ),
          Expanded(
            child: v == null || v.$2 <= 0 ? Center(child: Text('Volume', style: DS.rowSub)) : _VolumeSlider(level: v.$1, max: v.$2),
          ),
          _Repeat(
            onKey: () => onKey(TvKey.volumeUp),
            child: Tooltip(
              message: 'Volume up',
              child: SizedBox(width: 36, height: 56, child: Icon(Icons.add_rounded, color: DS.ink)),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              v == null ? '' : '${v.$1}',
              textAlign: TextAlign.center,
              style: DS.rowTitle.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Brightness: a direct slider (Android brightness on the TV, through One Launcher TV — works on
/// TVs whose backlight follows it; sends at most every 300 ms and on release, remembered since
/// TVs don't report it) + a button to the TV's own picture panel for TVs that keep the
/// backlight there.
class _Brightness extends StatefulWidget {
  const _Brightness({required this.prefs});
  final Prefs prefs;

  @override
  State<_Brightness> createState() => _BrightnessState();
}

class _BrightnessState extends State<_Brightness> {
  late double _v = widget.prefs.tvBrightness.toDouble();
  DateTime _sent = DateTime(0);

  void _send(double v, {bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_sent) < const Duration(milliseconds: 300)) return;
    _sent = now;
    TvRemote.instance.setBrightness(v.round());
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: DS.s4),
    decoration: BoxDecoration(color: DS.cardMuted, borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : 32)),
    child: Row(
      children: [
        Tooltip(
          message: 'Brightness',
          child: SizedBox(width: 48, child: Icon(Icons.light_mode_outlined, color: DS.ink)),
        ),
        Expanded(
          child: Slider(
            value: _v,
            max: 100,
            divisions: 20,
            activeColor: DS.ink,
            inactiveColor: DS.hairline,
            thumbColor: DS.ink,
            onChanged: (x) {
              if (x.round() != _v.round()) HapticFeedback.selectionClick();
              setState(() => _v = x);
              _send(x);
            },
            onChangeEnd: (x) {
              _send(x, force: true);
              widget.prefs.setTvBrightness(x.round());
            },
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${_v.round()}%',
            textAlign: TextAlign.center,
            style: DS.rowTitle.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        // TVs whose backlight ignores Android brightness keep it in their own picture panel.
        IconButton(
          tooltip: 'TV picture settings',
          icon: Icon(Icons.tune_rounded, color: DS.ink),
          onPressed: () {
            HapticFeedback.selectionClick();
            TvRemote.instance.openPicture();
          },
        ),
      ],
    ),
  );
}

/// Shows the dragged value while dragging, then follows the TV's reported level.
class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider({required this.level, required this.max});
  final int level, max;

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) => Slider(
    value: (_drag ?? widget.level.toDouble()).clamp(0, widget.max.toDouble()),
    max: widget.max.toDouble(),
    divisions: widget.max,
    activeColor: DS.ink,
    inactiveColor: DS.hairline,
    thumbColor: DS.ink,
    onChanged: (x) {
      if (_drag == null || x.round() != _drag!.round()) HapticFeedback.selectionClick();
      setState(() => _drag = x);
    },
    onChangeEnd: (x) {
      setState(() => _drag = null);
      TvRemote.instance.setVolume(x.round());
    },
  );
}

/// Typing on the TV from the phone keyboard: a big field mirroring the TV's focused one (every
/// change is sent whole), plus the keys you need while typing — move the cursor, Enter, back.
class _TypingPanel extends StatefulWidget {
  const _TypingPanel({super.key, required this.start, required this.label, required this.onKey});
  final String start, label;
  final void Function(int code, {bool strong}) onKey;

  @override
  State<_TypingPanel> createState() => _TypingPanelState();
}

class _TypingPanelState extends State<_TypingPanel> {
  late final _text = TextEditingController(text: widget.start)..selection = TextSelection.collapsed(offset: widget.start.length);

  @override
  void initState() {
    super.initState();
    TvRemote.instance.startTyping(widget.start);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() => TvRemote.instance.ime.value = null;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s16, DS.s8),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label.isEmpty ? 'Typing on your TV' : 'Typing on your TV · ${widget.label}', style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 13)),
        const SizedBox(height: DS.s8),
        Container(
          padding: const EdgeInsets.fromLTRB(DS.s16, DS.s4, DS.s4, DS.s4),
          decoration: BoxDecoration(color: DS.hero, borderRadius: BorderRadius.circular(DS.rMedia)),
          child: Row(
            children: [
              Icon(Icons.keyboard_rounded, color: DS.heroInk),
              const SizedBox(width: DS.s12),
              Expanded(
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  cursorColor: DS.heroInk,
                  textInputAction: TextInputAction.go,
                  // No autocorrect: a word swapped after the fact means deleting and retyping on
                  // the TV — fine, but surprising mid-search.
                  autocorrect: false,
                  style: DS.rowTitle.copyWith(color: DS.heroInk, fontSize: 18),
                  onChanged: TvRemote.instance.text,
                  onSubmitted: (_) {
                    widget.onKey(TvKey.enter);
                    _done();
                  },
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Type here — it appears on the TV',
                    hintStyle: DS.rowSub.copyWith(color: DS.heroInk.withValues(alpha: .6)),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Done typing',
                icon: Icon(Icons.close_rounded, color: DS.heroInk),
                onPressed: _done,
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.s12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Round(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => widget.onKey(TvKey.back)),
            _Round(icon: Icons.chevron_left_rounded, tooltip: 'Cursor left', onTap: () => widget.onKey(TvKey.left)),
            _Round(icon: Icons.chevron_right_rounded, tooltip: 'Cursor right', onTap: () => widget.onKey(TvKey.right)),
            _Round(
              icon: Icons.keyboard_return_rounded,
              tooltip: 'Enter',
              onTap: () {
                widget.onKey(TvKey.enter);
                _done();
              },
            ),
          ],
        ),
      ],
    ),
  );
}

/// The remote's quick apps: remove the ones on the row, add common TV apps, or any app by its
/// package name (for apps not listed). Changes show on the remote at once.
Future<Object?> showRemoteAppsEditor(BuildContext context, {required Prefs prefs}) => showOneSheetWith(
  context,
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) {
      final ids = prefs.remoteApps;
      Widget row(String title, String sub, Widget trailing) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: DS.s4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DS.rowTitle),
                  Text(sub, style: DS.rowSub.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            trailing,
          ],
        ),
      );
      Widget eyebrow(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s8),
        child: Text(DS.cased(t), style: DS.eyebrow),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s4),
            child: SheetHeader(title: 'Quick apps', subtitle: 'The app buttons on your remote'),
          ),
          eyebrow('On the remote'),
          if (ids.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DS.s24),
              child: Text('None — add some below', style: DS.rowSub),
            ),
          for (final (i, id) in ids.indexed)
            if (remoteAppFor(id) case final app?)
              row(
                app.name,
                app.package,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Move ${app.name} left',
                      onPressed: i == 0
                          ? null
                          : () => prefs.setRemoteApps(
                              [...ids]
                                ..removeAt(i)
                                ..insert(i - 1, id),
                            ),
                      icon: Icon(Icons.arrow_upward_rounded, color: i == 0 ? DS.inkFaint : DS.ink),
                    ),
                    IconButton(
                      tooltip: 'Remove ${app.name}',
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        prefs.setRemoteApps([...ids]..removeAt(i));
                      },
                      icon: Icon(Icons.remove_circle_outline_rounded, color: DS.alert),
                    ),
                  ],
                ),
              ),
          eyebrow('Add'),
          for (final app in remoteAppCatalog.where((a) => !ids.contains(a.id)))
            row(
              app.name,
              app.package,
              IconButton(
                tooltip: 'Add ${app.name}',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  prefs.setRemoteApps([...ids, app.id]);
                },
                icon: Icon(Icons.add_circle_outline_rounded, color: DS.ink),
              ),
            ),
          row(
            'Other app',
            'Any app on your TV, by its package name',
            IconButton(
              tooltip: 'Add another app',
              onPressed: () => _addOtherApp(ctx, prefs),
              icon: Icon(Icons.add_circle_outline_rounded, color: DS.ink),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(DS.s24, DS.s12, DS.s24, DS.s16),
            child: Text(
              'Apps without a web link open through One Launcher TV, so it needs to be on the TV. An app the TV doesn’t have does nothing.',
              style: DS.rowSub.copyWith(fontSize: 13),
            ),
          ),
        ],
      );
    },
  ),
);

/// "Other app": a name and the app's package (e.g. in.startv.hotstar) → "c:Name|package".
Future<void> _addOtherApp(BuildContext context, Prefs prefs) async {
  final name = TextEditingController(), pkg = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (d) => AlertDialog(
      backgroundColor: DS.card,
      title: Text('Add an app', style: DS.title.copyWith(fontSize: 20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'JioHotstar'),
          ),
          TextField(
            controller: pkg,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Package name', hintText: 'in.startv.hotstar'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: Text('Cancel', style: DS.rowTitle.copyWith(color: DS.inkMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(d, true),
          child: Text('Add', style: DS.rowTitle),
        ),
      ],
    ),
  );
  final p = pkg.text.trim(), n = name.text.trim().replaceAll('|', ' ');
  if (ok == true && RegExp(r'^[A-Za-z][\w]*(\.[A-Za-z_][\w]*)+$').hasMatch(p)) {
    await prefs.setRemoteApps([...prefs.remoteApps, 'c:$n|$p']);
  }
}
