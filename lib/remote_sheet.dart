import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';
import 'tv_remote.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'widgets.dart';

/// Dock → TV remote. First time: find the TV (or type its address) and pair with the code it
/// shows. After that it connects straight away and shows the remote.
Future<void> showTvRemote(BuildContext context, {required Prefs prefs}) {
  HapticFeedback.selectionClick();
  return showOneSheetWith(
    context,
    height: MediaQuery.sizeOf(context).height * .86,
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(DS.s24), borderSide: BorderSide.none),
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
                      title: prefs.tvName,
                      subtitle: switch (status) {
                        TvStatus.connected => 'Connected',
                        TvStatus.connecting => 'Connecting…',
                        _ => tv.error.value ?? 'Not connected',
                      },
                    ),
                  ),
                  _Round(icon: Icons.power_settings_new_rounded, tooltip: 'Power', danger: true, onTap: live ? () => _press(TvKey.power, strong: true) : null),
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
                          _DPad(size: pad, onKey: _press),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _Round(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => _press(TvKey.back)),
                              _Round(icon: Icons.home_rounded, tooltip: 'Home', onTap: () => _press(TvKey.home)),
                              _Round(icon: Icons.input_rounded, tooltip: 'Input', onTap: () => _press(TvKey.input)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _Volume(onKey: _press, volume: tv.volume),
                              _Round(icon: Icons.play_arrow_rounded, tooltip: 'Play / pause', onTap: () => _press(TvKey.playPause)),
                            ],
                          ),
                          SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                              children: [
                                for (final (name, link) in const [
                                  ('YouTube', 'https://www.youtube.com'),
                                  ('Netflix', 'https://www.netflix.com/title'),
                                  ('Prime Video', 'https://app.primevideo.com'),
                                  ('Disney+', 'https://www.disneyplus.com'),
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(right: DS.s8),
                                    child: ActionChip(
                                      label: Text(name, style: DS.rowTitle.copyWith(fontSize: 14)),
                                      backgroundColor: DS.cardMuted,
                                      side: BorderSide.none,
                                      shape: const StadiumBorder(),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        tv.appLink(link);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
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
      style: FilledButton.styleFrom(
        backgroundColor: DS.ink,
        foregroundColor: DS.card,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: DS.s24),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: DS.rowTitle.copyWith(color: DS.card, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// A round remote button (56 pt).
class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.tooltip, required this.onTap, this.danger = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Pressable(
      scale: .9,
      child: Material(
        color: danger ? DS.alert.withValues(alpha: .14) : DS.cardMuted,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(dimension: 56, child: Icon(icon, color: danger ? DS.alert : DS.ink)),
        ),
      ),
    ),
  );
}

/// The round D-pad: four arrow zones around an OK button. Holding an arrow repeats it.
class _DPad extends StatelessWidget {
  const _DPad({required this.size, required this.onKey});
  final double size;
  final void Function(int code, {bool strong}) onKey;

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
        decoration: BoxDecoration(color: DS.cardMuted, shape: BoxShape.circle),
        child: Stack(
          children: [
            arrow(Alignment.topCenter, Icons.keyboard_arrow_up_rounded, TvKey.up, 'Up'),
            arrow(Alignment.bottomCenter, Icons.keyboard_arrow_down_rounded, TvKey.down, 'Down'),
            arrow(Alignment.centerLeft, Icons.keyboard_arrow_left_rounded, TvKey.left, 'Left'),
            arrow(Alignment.centerRight, Icons.keyboard_arrow_right_rounded, TvKey.right, 'Right'),
            Center(
              child: Tooltip(
                message: 'OK',
                child: Pressable(
                  scale: .92,
                  child: Material(
                    color: DS.ink,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onKey(TvKey.ok, strong: true),
                      child: SizedBox.square(
                        dimension: ok,
                        child: Center(
                          child: Text(
                            'OK',
                            style: DS.rowTitle.copyWith(color: DS.card, fontWeight: FontWeight.w600),
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

/// Volume − / mute / + in one pill, with the TV's level when it tells us.
class _Volume extends StatelessWidget {
  const _Volume({required this.onKey, required this.volume});
  final void Function(int code, {bool strong}) onKey;
  final ValueListenable<(int, int, bool)?> volume;

  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    decoration: BoxDecoration(color: DS.cardMuted, borderRadius: BorderRadius.circular(28)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Repeat(
          onKey: () => onKey(TvKey.volumeDown),
          child: Tooltip(
            message: 'Volume down',
            child: SizedBox(width: 56, height: 56, child: Icon(Icons.remove_rounded, color: DS.ink)),
          ),
        ),
        ValueListenableBuilder<(int, int, bool)?>(
          valueListenable: volume,
          builder: (context, v, _) => GestureDetector(
            onTap: () => onKey(TvKey.mute),
            child: Tooltip(
              message: 'Mute',
              child: SizedBox(
                width: 56,
                child: Center(
                  child: v == null
                      ? Icon(Icons.volume_up_rounded, color: DS.ink)
                      : v.$3
                      ? Icon(Icons.volume_off_rounded, color: DS.alert)
                      : Text('${v.$1}', style: DS.rowTitle.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ),
        _Repeat(
          onKey: () => onKey(TvKey.volumeUp),
          child: Tooltip(
            message: 'Volume up',
            child: SizedBox(width: 56, height: 56, child: Icon(Icons.add_rounded, color: DS.ink)),
          ),
        ),
      ],
    ),
  );
}
