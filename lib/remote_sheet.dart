import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';
import 'third/tactile/parts.dart';
import 'third/tactile/tactile.dart';
import 'tv_remote.dart';
import 'ui/components.dart' show RoleSurface, confirmReset;
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'widgets.dart';

/// Long-press on the remote button: hide it (Settings → TV remote → Remote button brings it back).
void offerHideRemote(BuildContext context, {required Prefs prefs}) {
  HapticFeedback.mediumImpact();
  showOneSheet(
    context,
    header: const SheetHeader(title: 'Remote tab', subtitle: 'Turn it back on in Settings → TV remote'),
    actions: [
      SheetAction(Icons.visibility_off_outlined, 'Hide the Remote tab', () {
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
    underNav: true, // as the Remote tab's page: the buttons scroll under the nav
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
    tv.setVolumeKeys(true); // the phone's volume buttons change the TV's while this is open
  }

  @override
  void dispose() {
    tv.setVolumeKeys(false);
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
    if (!await confirmReset(
      context,
      title: 'Forget ${prefs.tvName}?',
      body: 'The remote stops working until you pair again with a code on the TV.',
      action: 'Forget',
    )) {
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
      padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, math.max(MediaQuery.viewInsetsOf(context).bottom, MediaQuery.paddingOf(context).bottom) + DS.s24),
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
        final reconnect = !live && status != TvStatus.connecting;
        // The nav's room at the bottom (on the Remote tab's page; 0 in a sheet): the buttons
        // scroll under the nav, anything fixed at the bottom sits above it.
        final under = MediaQuery.paddingOf(context).bottom;
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
                  _Round(icon: Icons.mic_none_rounded, tooltip: 'Voice search', onTap: live ? _voice : null),
                  const SizedBox(width: DS.s8),
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
                    onSelected: (v) => switch (v) {
                      'forget' => _forget(),
                      'arrange' => showRemoteArrange(context, prefs: prefs),
                      'wake' => showWakeSetup(context, prefs: prefs),
                      _ => tv.connect(prefs.tvHost!),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'arrange',
                        child: Text('Arrange remote', style: DS.rowTitle),
                      ),
                      PopupMenuItem(
                        value: 'wake',
                        child: Text('Turn on from phone', style: DS.rowTitle),
                      ),
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
                      ? Padding(
                          key: ValueKey('typing:${ime.$2}'),
                          padding: EdgeInsets.only(bottom: under),
                          child: _TypingPanel(start: ime.$1, label: ime.$2, onKey: _press),
                        )
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
                              final hidden = prefs.remoteHidden;
                              // The groups in the user's order (⋮ → Arrange remote), spread out when
                              // they fit; scrolling when they don't.
                              final room = reconnect ? 0.0 : under;
                              return SingleChildScrollView(
                                padding: EdgeInsets.only(bottom: room),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: math.max(0, c.maxHeight - room)),
                                  child: IntrinsicHeight(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        for (final g in prefs.remoteGroups)
                                          if (!hidden.contains(g))
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: DS.s8),
                                              child: _group(g, pad),
                                            ),
                                      ],
                                    ),
                                  ),
                                ),
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
            if (reconnect)
              Padding(
                padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s16 + under),
                // With its address known, Wake-on-LAN may bring a sleeping TV back too.
                child: _Primary(label: prefs.tvMac != null ? 'Turn on TV' : 'Reconnect', onTap: _turnOn),
              ),
          ],
        );
      },
    );
  }

  /// One of the remote's groups (Prefs.remoteGroupsDefault).
  Widget _group(String id, double pad) => switch (id) {
    'now' => Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.s16),
      child: _NowPlaying(prefs: prefs, onKey: _press),
    ),
    'dpad' => _DPad(size: pad, onKey: _press, onHold: _hold),
    'nav' => Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Round(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => _press(TvKey.back), onHold: (d) => _hold(TvKey.back, d)),
        _Round(icon: Icons.home_rounded, tooltip: 'Home', onTap: () => _press(TvKey.home), onHold: (d) => _hold(TvKey.home, d)),
        _Round(icon: Icons.input_rounded, tooltip: 'Input', onTap: () => _press(TvKey.input), onHold: (d) => _hold(TvKey.input, d)),
        _Round(icon: Icons.layers_outlined, tooltip: 'Recent apps', onTap: () => _press(TvKey.appSwitch)),
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
    // Rewind / fast-forward, captions and audio track: what they do is up to the app playing.
    'media' => Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Round(icon: Icons.replay_10_rounded, tooltip: 'Rewind', onTap: () => _press(TvKey.rewind), onHold: (d) => _hold(TvKey.rewind, d)),
        _Round(icon: Icons.play_arrow_rounded, tooltip: 'Play / pause', onTap: () => _press(TvKey.playPause), onHold: (d) => _hold(TvKey.playPause, d)),
        _Round(icon: Icons.forward_10_rounded, tooltip: 'Fast-forward', onTap: () => _press(TvKey.fastForward), onHold: (d) => _hold(TvKey.fastForward, d)),
        _Round(icon: Icons.closed_caption_outlined, tooltip: 'Captions', onTap: () => _press(TvKey.captions)),
        _Round(icon: Icons.record_voice_over_outlined, tooltip: 'Audio track', onTap: () => _press(TvKey.audioTrack)),
      ],
    ),
    'volume' => Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.s16),
      child: _Volume(onKey: _press, volume: tv.volume),
    ),
    'brightness' => Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.s16),
      child: _Brightness(prefs: prefs),
    ),
    _ => _quickApps(),
  };

  Widget _quickApps() => SizedBox(
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
              child: DS.third
                  ? TKey(
                      height: 40,
                      width: null,
                      onTap: () => openRemoteApp(app),
                      child: Padding(padding: const EdgeInsets.symmetric(horizontal: DS.s12), child: Text(app.name, style: DS.rowTitle.copyWith(fontSize: 14))),
                    )
                  : ActionChip(
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
          if (DS.third)
            TKey(
              height: 40,
              width: null,
              tooltip: 'Edit quick apps',
              onTap: () => showRemoteAppsEditor(context, prefs: prefs),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.edit_outlined, size: 16, color: Tactile.inkMuted), const SizedBox(width: 6), Text(DS.cased('Edit'), style: DS.pill.copyWith(color: Tactile.ink))]),
              ),
            )
          else
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
  );

  /// Reconnect — and with the TV's address set, wake it first (it may be asleep).
  Future<void> _turnOn() async {
    HapticFeedback.mediumImpact();
    final host = prefs.tvHost!;
    if (prefs.tvMac == null) {
      await tv.connect(host);
      return;
    }
    await tv.wake(host, mac: prefs.tvMac);
  }

  /// Voice search: the phone's speech dialog, then One Launcher TV's search with the words.
  Future<void> _voice() async {
    HapticFeedback.selectionClick();
    final words = (await tv.listen())?.trim();
    if (words == null || words.isEmpty || !mounted) return;
    HapticFeedback.lightImpact();
    await tv.searchOnTv(words);
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
    child: RoleSurface(
      color: DS.cardMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)),
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
  Widget build(BuildContext context) => DS.third
      // Tactile: a long key with its legend.
      ? TKey(
          height: 52,
          width: compact ? null : double.infinity,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DS.s24),
            child: Center(child: Text(DS.cased(label), style: DS.pill.copyWith(fontSize: 14, color: Tactile.ink))),
          ),
        )
      : SizedBox(
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
      // Tactile: a round key (power: a red cap).
      child: DS.third
          ? TKey(
              width: 56,
              height: 56,
              radius: 28,
              tint: danger ? const Color(0xFFC8443F) : null,
              onTap: onTap,
              child: Icon(icon, color: danger ? Colors.white : Tactile.ink),
            )
          : Pressable(
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
/// Tactile's d-pad (ref 5): a big domed dial with a lit tick at the top and hairline arrows; it
/// tilts toward the side pressed, and its centre is a round key (OK) in a recess.
class _Dial extends StatefulWidget {
  const _Dial({required this.size, required this.onKey, this.onHold});
  final double size;
  final void Function(int code, {bool strong}) onKey;
  final void Function(int code, bool down)? onHold;

  @override
  State<_Dial> createState() => _DialState();
}

class _DialState extends State<_Dial> {
  Offset _tilt = Offset.zero; // where it's pressed, −1…1

  @override
  Widget build(BuildContext context) {
    final size = widget.size, ok = size * .4;
    Widget arrow(Alignment at, IconData icon, int code, String label) => Align(
      alignment: at,
      child: _Repeat(
        onKey: () => widget.onKey(code),
        child: Tooltip(
          message: label,
          child: SizedBox(width: size * .3, height: size * .3, child: Icon(icon, size: 30, color: Tactile.inkMuted)),
        ),
      ),
    );
    return Listener(
      onPointerDown: (e) {
        final p = (e.localPosition - Offset(size / 2, size / 2)) / (size / 2);
        if (p.distance < .45) return; // the OK key presses itself
        TactileFeel.press();
        setState(() => _tilt = p);
      },
      onPointerUp: (_) => setState(() => _tilt = Offset.zero),
      onPointerCancel: (_) => setState(() => _tilt = Offset.zero),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: _tilt),
        duration: const Duration(milliseconds: 90),
        builder: (context, t, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0015)
            ..rotateX(t.dy * .07)
            ..rotateY(-t.dx * .07),
          child: child,
        ),
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(center: const Alignment(0, -.6), radius: 1, colors: [Tactile.capTop, Tactile.capBottom]),
              border: Border.all(color: Tactile.rim, width: .8),
              boxShadow: Tactile.proud,
            ),
            child: Stack(
              children: [
                Align(
                  alignment: const Alignment(0, -.93),
                  child: Container(
                    width: 3,
                    height: 12,
                    decoration: BoxDecoration(color: Tactile.light, borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: Tactile.light.withValues(alpha: .6), blurRadius: 6)]),
                  ),
                ),
                arrow(Alignment.topCenter, Icons.keyboard_arrow_up_rounded, TvKey.up, 'Up'),
                arrow(Alignment.bottomCenter, Icons.keyboard_arrow_down_rounded, TvKey.down, 'Down'),
                arrow(Alignment.centerLeft, Icons.keyboard_arrow_left_rounded, TvKey.left, 'Left'),
                arrow(Alignment.centerRight, Icons.keyboard_arrow_right_rounded, TvKey.right, 'Right'),
                Center(
                  child: TWell(
                    radius: ok / 2 + 6,
                    padding: const EdgeInsets.all(6),
                    child: _Hold(
                      onHold: widget.onHold == null ? null : (d) => widget.onHold!(TvKey.ok, d),
                      child: TKey(
                        width: ok,
                        height: ok,
                        radius: ok / 2,
                        onTap: () => widget.onKey(TvKey.ok, strong: true),
                        child: Text('OK', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.5, color: Tactile.ink)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DPad extends StatelessWidget {
  const _DPad({required this.size, required this.onKey, this.onHold});
  final double size;
  final void Function(int code, {bool strong}) onKey;
  final void Function(int code, bool down)? onHold;

  @override
  Widget build(BuildContext context) {
    if (DS.third) return _Dial(size: size, onKey: onKey, onHold: onHold);
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
  Widget build(BuildContext context) => _bar(
    ValueListenableBuilder<(int, int, bool)?>(
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
            child: DS.third && v != null
                ? Center(child: DotMatrix('${v.$1}', dot: 2.2, color: Tactile.light, ghost: false))
                : Text(
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

/// A remote control bar (volume, brightness): Classic a soft pill; Tactile a recess in the panel.
Widget _bar(Widget child) => DS.third
    ? TWell(radius: 20, padding: const EdgeInsets.symmetric(horizontal: DS.s4), child: SizedBox(height: 64, child: child))
    : Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: DS.s4),
        decoration: BoxDecoration(color: DS.cardMuted, borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : 32)),
        child: child,
      );

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
  Widget build(BuildContext context) => _bar(
    Row(
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
  const _TypingPanel({required this.start, required this.label, required this.onKey});
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
/// The remote's groups (⋮ → Arrange remote): move each up or down, show or hide it.
const remoteGroupNames = {
  'now': ('Now playing', 'What’s on the TV, with previous · play / pause · next'),
  'dpad': ('Direction pad', 'Up, down, left, right and OK'),
  'nav': ('Navigate', 'Back · Home · Input · Recent apps · Type'),
  'media': ('Playback', 'Rewind · Play / pause · Fast-forward · Captions · Audio'),
  'volume': ('Volume', 'Mute, down, up and the level'),
  'brightness': ('Brightness', 'The TV’s backlight'),
  'apps': ('Quick apps', 'Your app buttons'),
};

Future<Object?> showRemoteArrange(BuildContext context, {required Prefs prefs}) => showOneSheetWith(
  context,
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) {
      final ids = prefs.remoteGroups;
      final hidden = prefs.remoteHidden;
      void move(int i, int by) => prefs.setRemoteGroups(
        [...ids]
          ..removeAt(i)
          ..insert(i + by, ids[i]),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
            child: SheetHeader(title: 'Arrange remote', subtitle: 'Top to bottom · hide what you don’t use'),
          ),
          for (final (i, id) in ids.indexed)
            if (remoteGroupNames[id] case (final name, final sub))
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s4, DS.s8, DS.s4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: DS.rowTitle.copyWith(color: hidden.contains(id) ? DS.inkMuted : DS.ink)),
                          Text(sub, style: DS.rowSub.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Move $name up',
                      onPressed: i == 0 ? null : () => move(i, -1),
                      icon: Icon(Icons.arrow_upward_rounded, color: i == 0 ? DS.inkFaint : DS.ink),
                    ),
                    IconButton(
                      tooltip: 'Move $name down',
                      onPressed: i == ids.length - 1 ? null : () => move(i, 1),
                      icon: Icon(Icons.arrow_downward_rounded, color: i == ids.length - 1 ? DS.inkFaint : DS.ink),
                    ),
                    IconButton(
                      tooltip: hidden.contains(id) ? 'Show $name' : 'Hide $name',
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        prefs.setRemoteHidden(id, !hidden.contains(id));
                      },
                      icon: Icon(hidden.contains(id) ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: DS.ink),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: DS.s16),
        ],
      );
    },
  ),
);

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

/// What's playing on the TV (One Launcher TV's NowPlayingServer): picture, app, title, progress,
/// and previous · play / pause · next. Asks every 2 s while the remote is open; nothing playing
/// (or no answer) folds it away.
class _NowPlaying extends StatefulWidget {
  const _NowPlaying({required this.prefs, required this.onKey});
  final Prefs prefs;
  final void Function(int code, {bool strong}) onKey;

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  Map<String, Object?>? _now;
  MemoryImage? _art;
  String _artId = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final host = widget.prefs.tvHost;
    if (host == null || TvRemote.instance.status.value != TvStatus.connected) return;
    final token = widget.prefs.tvPhoneToken;
    final now = await TvRemote.instance.nowPlaying(host, token);
    if (!mounted) return;
    final id = (now?['artId'] as String?) ?? '';
    if (id != _artId) {
      _artId = id;
      final bytes = id.isEmpty ? null : await TvRemote.instance.nowPlayingArt(host, token);
      if (!mounted) return;
      _art = bytes == null ? null : MemoryImage(bytes);
    }
    setState(() => _now = now?['active'] == true ? now : null);
  }

  @override
  Widget build(BuildContext context) {
    final n = _now;
    return AnimatedSize(
      duration: Motion.snapDuration,
      curve: Motion.settle,
      child: n == null ? const SizedBox(width: double.infinity) : _card(n),
    );
  }

  Widget _card(Map<String, Object?> n) {
    final title = n['title'] as String? ?? '';
    final sub = n['subtitle'] as String? ?? '';
    final app = n['app'] as String? ?? '';
    final pos = (n['position'] as num?)?.toDouble() ?? 0, dur = (n['duration'] as num?)?.toDouble() ?? 0;
    final playing = n['playing'] == true;
    return Container(
      padding: const EdgeInsets.all(DS.s12),
      // Tactile: a plate (lit top edge, soft shadow).
      decoration: DS.third
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(Tactile.plate, Colors.white, Tactile.dark ? .04 : .35)!, Tactile.plate],
                stops: const [0, .1],
              ),
              border: Border.all(color: Tactile.rim, width: .6),
              boxShadow: Tactile.plateShadow,
            )
          : BoxDecoration(color: DS.cardMuted, borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : 24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : 14),
                child: SizedBox.square(
                  dimension: 56,
                  child: _art != null
                      ? Image(image: _art!, fit: BoxFit.cover, gaplessPlayback: true)
                      : ColoredBox(
                          color: DS.hero,
                          child: Center(
                            child: Text(app.isEmpty ? '▶' : app[0].toUpperCase(), style: DS.rowTitle.copyWith(color: DS.heroInk, fontSize: 20)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: DS.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DS.cased('Now playing · $app'),
                      style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      title,
                      style: DS.rowTitle.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub.isNotEmpty) Text(sub, style: DS.rowSub.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          if (dur > 0) ...[
            const SizedBox(height: DS.s12),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: (pos / dur).clamp(0, 1), minHeight: 4, color: DS.third ? Tactile.light : DS.ink, backgroundColor: DS.hairline),
            ),
          ],
          const SizedBox(height: DS.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Previous',
                icon: Icon(Icons.skip_previous_rounded, color: DS.ink),
                onPressed: () => widget.onKey(TvKey.previous),
              ),
              IconButton(
                tooltip: playing ? 'Pause' : 'Play',
                iconSize: 32,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: DS.ink),
                onPressed: () {
                  widget.onKey(TvKey.playPause);
                  setState(() => _now = {...n, 'playing': !playing}); // at once; the next answer confirms
                },
              ),
              IconButton(
                tooltip: 'Next',
                icon: Icon(Icons.skip_next_rounded, color: DS.ink),
                onPressed: () => widget.onKey(TvKey.next),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ⋮ → Turn on from phone: the TV's network address for Wake-on-LAN, and where to find it.
Future<Object?> showWakeSetup(BuildContext context, {required Prefs prefs}) {
  final field = TextEditingController(text: prefs.tvMac ?? '');
  return showOneSheetWith(
    context,
    keyboard: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final valid = TvRemote.macBytes(field.text) != null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(title: 'Turn on from phone', subtitle: 'Wakes your TV when it’s asleep'),
              const SizedBox(height: DS.s8),
              Text(
                'Enter your TV’s network (MAC) address. On the TV: Settings → Network & Internet → your network → MAC address. '
                'Also turn on “Network standby” or “Wake on LAN” in the TV’s settings if it has it.',
                style: DS.rowSub,
              ),
              const SizedBox(height: DS.s16),
              TextField(
                controller: field,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                onChanged: (_) => setState(() {}),
                style: DS.rowTitle,
                decoration: InputDecoration(
                  hintText: 'c8:7e:a1:88:15:c2',
                  filled: true,
                  fillColor: DS.cardMuted,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(DS.rMedia), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: DS.s16),
              Row(
                children: [
                  if (prefs.tvMac != null)
                    TextButton(
                      onPressed: () {
                        prefs.setTvMac(null);
                        Navigator.of(ctx).pop();
                      },
                      child: Text('Remove', style: DS.rowTitle.copyWith(color: DS.alert)),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: valid
                        ? () {
                            HapticFeedback.selectionClick();
                            prefs.setTvMac(field.text.trim().toLowerCase());
                            Navigator.of(ctx).pop();
                          }
                        : null,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}
