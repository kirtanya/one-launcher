import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/ds.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';

/// Quick settings (Sony's "Quick Settings", docs/GOOGLE_TV_VIEW.md), TV only: a dark band along
/// the bottom with one row of items — icon, name, and the current value in blue (or an arrow for
/// a page that opens). OK on an item with choices grows a small picker up out of it; ↑ ↓ change
/// it live, OK / Back close the picker, Back again closes the panel.
/// Only what really works on this TV (QuickSettings.kt): volume, mute, sleep timer, screensaver,
/// inputs, network, Bluetooth and the TV's own pages that open here. No brightness or picture
/// mode: TVs ignore the one and keep the other to themselves, so they'd only pretend.
/// Opens from Google TV's Settings icon and from the remote's Settings key while we're in front.
Future<void> showTvQuickSettings(BuildContext context, {List<TvQuickItem> extras = const []}) async {
  if (tvQuickSettingsOpen) return;
  tvQuickSettingsOpen = true;
  try {
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Close',
      barrierColor: const Color(0x55000000),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, a, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, .25), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: a, child: child),
      ),
      pageBuilder: (context, _, _) => TvQuickSettings(extras: extras),
    );
  } finally {
    tvQuickSettingsOpen = false;
  }
}

/// The panel is showing (the Settings key closes it again).
bool tvQuickSettingsOpen = false;

/// An item the home adds (Customise home): opens something, shown with an arrow.
class TvQuickItem {
  const TvQuickItem(this.id, this.icon, this.name, this.onSelect);
  final String id;
  final IconData icon;
  final String name;
  final VoidCallback onSelect;
}

class TvQuickSettings extends StatefulWidget {
  const TvQuickSettings({super.key, this.extras = const []});
  final List<TvQuickItem> extras;

  @override
  State<TvQuickSettings> createState() => _TvQuickSettingsState();
}

/// One item in the band: [value] in blue, or an arrow when it opens a page; [choices] → a picker.
class _Item {
  const _Item(this.id, this.icon, this.name, {this.value, this.choices = const [], this.at = 0, this.onPick, this.onSelect, this.note, this.level = false});
  final String id;
  final IconData icon;
  final String name;
  final String? value;
  final List<String> choices; // the picker's rows, top to bottom
  final int at; // the chosen row
  final void Function(int i)? onPick; // ↑ ↓ in the picker: applied live
  final VoidCallback? onSelect; // no picker: OK does this
  final String? note; // a line under the picker ("Then: screen off")
  final bool level; // volume: the picker is a level (big number), not a list
}

class _TvQuickSettingsState extends State<TvQuickSettings> {
  static const _blue = Color(0xFF5AB4FF);
  static const _band = Color(0xF21A1A1A);
  static const _sleepChoices = [0, 15, 30, 45, 60, 90, 120];

  Map<String, Object?> _s = const {};
  bool _loaded = false;
  String? _picking; // the item whose picker is open
  int _pickAt = 0;
  final _nodes = <String, FocusNode>{};
  final _links = <String, LayerLink>{};
  final _scroll = ScrollController();
  Timer? _tick; // the sleep timer's minutes left (once a minute while open)

  FocusNode _node(String id) => _nodes[id] ??= FocusNode(debugLabel: 'qs $id');
  LayerLink _link(String id) => _links[id] ??= LayerLink();
  TvApps get tv => TvApps.instance;

  @override
  void initState() {
    super.initState();
    _load(first: true);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    final s = await tv.qsState();
    if (!mounted) return;
    setState(() {
      _s = s;
      _loaded = true;
    });
    if (first) WidgetsBinding.instance.addPostFrameCallback((_) => _items.isEmpty ? null : _node(_items.first.id).requestFocus());
  }

  List<String> get _linkIds => [for (final l in (_s['links'] as List? ?? const [])) '$l'];
  bool _has(String id) => _linkIds.contains(id);

  void _close() => Navigator.of(context).pop();

  /// Opens one of the TV's pages (the panel closes first).
  void _openPage(String id, {VoidCallback? otherwise}) {
    _close();
    tv.qsOpen(id).then((ok) {
      if (!ok) otherwise?.call();
    });
  }

  String _sleepValue() {
    final at = (_s['sleepAt'] as num?)?.toInt() ?? 0;
    final left = at - DateTime.now().millisecondsSinceEpoch;
    if (at <= 0 || left <= 0) return 'Off';
    final min = (left / 60000).ceil();
    return min >= 60 ? '${min ~/ 60} h ${min % 60} min' : '$min min';
  }

  List<_Item> get _items {
    if (!_loaded) return const [];
    final vol = (_s['volume'] as num?)?.toInt();
    final max = (_s['volumeMax'] as num?)?.toInt() ?? 0;
    final fixed = _s['volumeFixed'] == true;
    final muted = _s['muted'] == true;
    final net = '${_s['network'] ?? 'unknown'}';
    final bt = _s['bluetooth'] as bool?;
    final inputs = [for (final i in (_s['inputs'] as List? ?? const [])) '$i'];
    return [
      _Item('settings', Icons.settings_outlined, 'Settings', onSelect: () => _openPage('settings', otherwise: tv.openSettings)),
      for (final e in widget.extras)
        _Item(
          e.id,
          e.icon,
          e.name,
          onSelect: () {
            _close();
            e.onSelect();
          },
        ),
      if (vol != null && max > 0)
        _Item(
          'volume',
          muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
          'Volume',
          value: fixed ? 'Fixed' : '$vol',
          level: true,
          at: vol,
          choices: fixed ? const [] : [for (var i = 0; i <= max; i++) '$i'],
          onPick: (i) async {
            final got = await tv.qsVolume(i);
            if (mounted && got != null) setState(() => _s = {..._s, 'volume': got});
          },
          note: fixed ? 'The TV’s sound system sets the volume' : null,
        ),
      if (vol != null)
        _Item(
          'mute',
          muted ? Icons.volume_off_outlined : Icons.volume_mute_outlined,
          'Mute',
          value: muted ? 'On' : 'Off',
          onSelect: () async {
            final now = await tv.qsMute(!muted);
            if (mounted && now != null) setState(() => _s = {..._s, 'muted': now});
          },
        ),
      _Item(
        'sleep',
        Icons.bedtime_outlined,
        'Sleep timer',
        value: _sleepValue(),
        choices: [for (final m in _sleepChoices) m == 0 ? 'Off' : (m >= 60 ? '${m ~/ 60} h${m % 60 > 0 ? ' ${m % 60} min' : ''}' : '$m min')],
        at: 0,
        onPick: (i) async {
          final at = await tv.qsSleep(_sleepChoices[i]);
          if (mounted) setState(() => _s = {..._s, 'sleepAt': at});
        },
        // What happens at the end: the screen goes off only through the accessibility service.
        note: _s['sleepOff'] == true ? 'Then the screen turns off' : 'Then the screensaver starts',
      ),
      if (_has('screensaver')) _Item('screensaver', Icons.nightlight_outlined, 'Screensaver', onSelect: () => _openPage('screensaver')),
      if (_has('inputs')) _Item('inputs', Icons.input_rounded, 'Inputs', value: inputs.isEmpty ? null : (inputs.length == 1 ? inputs.first : '${inputs.length} inputs'), onSelect: () => _openPage('inputs')),
      _Item(
        'network',
        net == 'ethernet' ? Icons.settings_ethernet_rounded : (net == 'none' ? Icons.wifi_off_rounded : Icons.wifi_rounded),
        'Network',
        value: switch (net) {
          'wifi' => 'Wi-Fi',
          'ethernet' => 'Ethernet',
          'none' => 'Not connected',
          'other' => 'Connected',
          _ => null,
        },
        onSelect: _has('network') ? () => _openPage('network') : null,
      ),
      if (bt != null || _has('bluetooth'))
        _Item('bluetooth', Icons.bluetooth_rounded, 'Bluetooth', value: bt == null ? null : (bt ? 'On' : 'Off'), onSelect: _has('bluetooth') ? () => _openPage('bluetooth') : null),
      if (_has('display')) _Item('display', Icons.tv_rounded, 'Display', onSelect: () => _openPage('display')),
      if (_has('sound')) _Item('sound', Icons.speaker_outlined, 'Sound', onSelect: () => _openPage('sound')),
      if (_has('sony')) _Item('sony', Icons.tune_rounded, 'TV quick settings', onSelect: () => _openPage('sony')),
      if (_has('accessibility')) _Item('accessibility', Icons.accessibility_new_rounded, 'Accessibility', onSelect: () => _openPage('accessibility')),
    ];
  }

  void _select(_Item it) {
    HapticFeedback.selectionClick();
    if (_picking != null) return setState(() => _picking = null); // OK in the picker: done
    if (it.choices.isNotEmpty) {
      final at = it.id == 'sleep' ? _sleepAt() : it.at;
      return setState(() {
        _picking = it.id;
        _pickAt = at.clamp(0, it.choices.length - 1);
      });
    }
    it.onSelect?.call();
  }

  /// The sleep picker opens on the nearest choice to the time left.
  int _sleepAt() {
    final at = (_s['sleepAt'] as num?)?.toInt() ?? 0;
    final left = (at - DateTime.now().millisecondsSinceEpoch) / 60000;
    if (at <= 0 || left <= 0) return 0;
    var best = 1;
    for (var i = 1; i < _sleepChoices.length; i++) {
      if ((_sleepChoices[i] - left).abs() < (_sleepChoices[best] - left).abs()) best = i;
    }
    return best;
  }

  bool _move(List<_Item> items, int i, AxisDirection d) {
    final it = items[i];
    if (_picking == it.id) {
      // ↑ = higher in the list (the picker grows up: the top row is the last choice for levels).
      final by = switch (d) {
        AxisDirection.up => it.level ? 1 : -1,
        AxisDirection.down => it.level ? -1 : 1,
        _ => 0,
      };
      final to = (_pickAt + by).clamp(0, it.choices.length - 1);
      if (by != 0 && to != _pickAt) {
        setState(() => _pickAt = to);
        it.onPick?.call(to);
      }
      return true;
    }
    switch (d) {
      case AxisDirection.left when i > 0:
        _node(items[i - 1].id).requestFocus();
      case AxisDirection.right when i < items.length - 1:
        _node(items[i + 1].id).requestFocus();
      default:
        break;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final picking = items.where((it) => it.id == _picking).firstOrNull;
    return PopScope(
      canPop: _picking == null, // Back closes the picker first
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _picking = null);
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close)),
            // The title reads over anything: the bottom of the home fades to black behind it.
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 300,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xCC000000), Color(0xEE000000)],
                      stops: [0, .45, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(TvDS.safe.left - 8, 0, 0, DS.s12),
                    child: Text('Quick settings', style: TvDS.panelTitle.copyWith(fontSize: 20)),
                  ),
                  Container(
                    height: 132,
                    color: _band,
                    child: FocusTraversalGroup(
                      child: ListView.separated(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        padding: EdgeInsets.fromLTRB(TvDS.safe.left - 16, 14, TvDS.safe.right, 14),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 4),
                        itemBuilder: (context, i) {
                          final it = items[i];
                          return CompositedTransformTarget(
                            link: _link(it.id),
                            child: _QuickItem(
                              item: it,
                              focusNode: _node(it.id),
                              open: _picking == it.id,
                              onSelect: () => _select(it),
                              onMove: (d) => _move(items, i, d),
                              onFocus: () {
                                if (_picking != null && _picking != it.id) setState(() => _picking = null);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The picker: grows up out of its item.
            if (picking != null)
              CompositedTransformFollower(
                link: _link(picking.id),
                targetAnchor: Alignment.topLeft,
                followerAnchor: Alignment.bottomLeft,
                offset: const Offset(0, -6),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: _Picker(item: picking, at: _pickAt),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickItem extends StatelessWidget {
  const _QuickItem({required this.item, required this.focusNode, required this.open, required this.onSelect, required this.onMove, required this.onFocus});
  final _Item item;
  final FocusNode focusNode;
  final bool open;
  final VoidCallback onSelect, onFocus;
  final bool Function(AxisDirection) onMove;

  static const _blue = _TvQuickSettingsState._blue;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final settings = it.id == 'settings';
    final dead = it.onSelect == null && it.choices.isEmpty; // shows its state, nothing to open here
    return Semantics(
      button: true,
      label: '${it.name}${it.value != null ? ', ${it.value}' : ''}',
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 104,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(color: f || open ? const Color(0xFF3A3A3A) : const Color(0x00000000), borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              // Settings: a round blue button, like the TV's own.
              Container(
                width: 34,
                height: 34,
                decoration: settings ? const BoxDecoration(color: _blue, shape: BoxShape.circle) : null,
                child: Icon(it.icon, size: settings ? 20 : 24, color: settings ? const Color(0xFF0B1A2A) : (dead ? TvDS.inkMuted : TvDS.ink)),
              ),
              const SizedBox(height: 8),
              Text(it.name, style: TvDS.hint.copyWith(fontSize: 12.5, color: dead ? TvDS.inkMuted : TvDS.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              if (it.value != null)
                Text(it.value!, style: TvDS.hint.copyWith(fontSize: 12.5, color: _blue), maxLines: 1, overflow: TextOverflow.ellipsis)
              else if (!dead)
                const Icon(Icons.open_in_new_rounded, size: 14, color: _blue),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small picker over an item: a list (the chosen row lit) or, for volume, a level.
class _Picker extends StatelessWidget {
  const _Picker({required this.item, required this.at});
  final _Item item;
  final int at;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Align(
        alignment: Alignment.bottomLeft,
        heightFactor: t,
        child: Opacity(opacity: t, child: child),
      ),
      child: Container(
        width: it.level ? 104 : 168,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFA262626),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 18)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (it.level) ...[
              const Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: TvDS.inkMuted),
              Text(it.choices[at], textAlign: TextAlign.center, style: TvDS.panelTitle.copyWith(fontSize: 30, color: _TvQuickSettingsState._blue)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: it.choices.length < 2 ? 0 : at / (it.choices.length - 1),
                    minHeight: 4,
                    backgroundColor: const Color(0x33FFFFFF),
                    color: _TvQuickSettingsState._blue,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: TvDS.inkMuted),
            ] else
              for (final (i, c) in it.choices.indexed)
                Container(
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(color: i == at ? const Color(0xFF4A5868) : const Color(0x00000000), borderRadius: BorderRadius.circular(6)),
                  child: Text(c, style: TvDS.hint.copyWith(fontSize: 14, color: i == at ? TvDS.ink : TvDS.inkMuted)),
                ),
            if (it.note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                child: Text(it.note!, style: TvDS.hint.copyWith(fontSize: 11.5, color: TvDS.inkMuted)),
              ),
          ],
        ),
      ),
    );
  }
}
