import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'smart_home.dart';
import 'ui/ds.dart';

/// Quick light control, for the top page and the side panel's Smart home widget: one row of
/// chips (All, each room, each light: its dot turns it on or off), and for what's picked a
/// power button, brightness and colour (lights first, then rooms). [full] shows the brightness and colour rows too; compact swaps them in for the chips.
class QuickLights extends StatefulWidget {
  const QuickLights({
    super.key,
    required this.ink,
    required this.soft,
    required this.onOpen,
    this.full = true,
  });

  /// Words and icons, and the quieter words (it sits on the wallpaper or a card).
  final Color ink, soft;

  /// Opens the full Smart home sheet (setup, other devices).
  final VoidCallback onOpen;
  final bool full;

  @override
  State<QuickLights> createState() => _QuickLightsState();
}

const _swatchHues = [0.0, 30.0, 50.0, 120.0, 210.0, 260.0, 310.0];
const _swatchWhites = [2700, 4000, 6500];

class _QuickLightsState extends State<QuickLights> {
  /// null: all lights; `room:<name>`: a room's; else one light's id.
  String? _pick;
  double? _drag;

  /// Compact: what the second row shows — 0 the chips, 1 colours, 2 brightness.
  int _row = 0;

  Widget _mode(int row, IconData icon, String label, Color ink) => IconButton(
    tooltip: label,
    isSelected: _row == row,
    onPressed: () => setState(() => _row = _row == row ? 0 : row),
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, color: ink.withValues(alpha: _row == row ? 1 : .7)),
    style: IconButton.styleFrom(
      backgroundColor: _row == row ? ink.withValues(alpha: .2) : null,
    ),
  );
  DateTime _sent = DateTime(0);

  SmartHome get _home => SmartHome.instance;

  List<SmartDevice> _target(SmartHomeState s) {
    final lights = s.lights;
    final p = _pick;
    if (p == null) return lights;
    if (p.startsWith('room:')) {
      final room = p.substring(5);
      return [
        for (final d in lights)
          if ((d.room.isEmpty ? 'Other' : d.room) == room) d,
      ];
    }
    return [
      for (final d in lights)
        if (d.id == p) d,
    ];
  }

  String _title(SmartHomeState s) {
    final p = _pick;
    if (p == null) {
      return s.homes.length > 1 ? (s.homeName ?? 'All lights') : 'All lights';
    }
    if (p.startsWith('room:')) return p.substring(5);
    return s.byId(p)?.name ?? 'Light';
  }

  void _brightness(List<SmartDevice> t, double v, {bool end = false}) {
    final now = DateTime.now();
    // While dragging, a step every 150 ms; the bridge keeps only the newest anyway.
    if (!end && now.difference(_sent) < const Duration(milliseconds: 150)) {
      return;
    }
    _sent = now;
    _home.setLights(t, 'brightness', v.round());
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SmartHomeState>(
    valueListenable: _home.state,
    builder: (context, s, _) {
      final ink = widget.ink, soft = widget.soft;
      final ready = s.status == SmartHomeStatus.ready || s.all.isNotEmpty;
      if (!ready || s.lights.isEmpty) {
        return _Line(
          ink: ink,
          soft: soft,
          title: ready ? 'No lights here' : 'Smart home',
          sub: ready
              ? 'Add lights in Google Home'
              : 'Tap to connect Google Home',
          onTap: widget.onOpen,
        );
      }
      // A light or room that went away (or another home picked): back to all.
      var target = _target(s);
      if (target.isEmpty) {
        _pick = null;
        target = s.lights;
      }
      final live = [
        for (final d in target)
          if (d.online) d,
      ];
      final on = live.where((d) => d.on).toList();
      final dim = [
        for (final d in on)
          if (d.dimmable) d,
      ];
      final bright =
          _drag ??
          (dim.isEmpty
              ? 0.0
              : dim.fold<int>(0, (a, d) => a + d.brightness!) / dim.length);
      final canColour = live.any((d) => d.canColor),
          canWhite = live.any((d) => d.canTemp);
      final single = target.length == 1 ? target.first : null;
      final rooms = {
        for (final d in s.lights) d.room.isEmpty ? 'Other' : d.room,
      }.toList();

      final slider = !live.any((d) => d.dimmable)
          ? null
          : SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                activeTrackColor: ink,
                inactiveTrackColor: ink.withValues(alpha: .22),
                thumbColor: ink,
                overlayColor: ink.withValues(alpha: .1),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              ),
              child: Semantics(
                label: 'Brightness',
                child: Slider(
                  value: bright.clamp(0, 100).toDouble(),
                  max: 100,
                  onChanged: (v) {
                    setState(() => _drag = v);
                    _brightness(live, v);
                  },
                  onChangeEnd: (v) {
                    setState(() => _drag = null);
                    _brightness(live, v, end: true);
                  },
                ),
              ),
            );
      final swatches = !(canColour || canWhite)
          ? null
          : SizedBox(
              height: 40,
              child: ListView(
                key: const ValueKey('swatches'),
                scrollDirection: Axis.horizontal,
                children: [
                  if (canWhite)
                    for (final k in _swatchWhites)
                      _Swatch(
                        colour: kelvinColour(k),
                        label: k <= 3000
                            ? 'Warm white'
                            : k >= 6000
                            ? 'Cool white'
                            : 'White',
                        ring: ink,
                        selected:
                            single?.colorMode == 'temp' &&
                            single!.colorTempK != null &&
                            (single.colorTempK! - k).abs() < 300,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _home.setLights(live, 'colorTempK', k);
                        },
                      ),
                  if (canColour)
                    for (final h in _swatchHues)
                      _Swatch(
                        colour: HSVColor.fromAHSV(1, h, 1, 1).toColor(),
                        label: 'Colour',
                        ring: ink,
                        selected:
                            single?.colorMode == 'color' &&
                            single!.hue != null &&
                            (single.hue! - h).abs() < 8,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _home.setLights(live, 'color', {'h': h, 's': 1.0});
                        },
                      ),
                ],
              ),
            );

      final header = Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DS.rowTitle.copyWith(color: ink),
                  ),
                  Text(
                    live.isEmpty
                        ? 'Offline'
                        : on.isEmpty
                        ? (single != null ? 'Off' : 'All off')
                        : single != null
                        ? (dim.isEmpty ? 'On' : 'On · ${bright.round()}%')
                        : '${on.length} of ${live.length} on',
                    maxLines: 1,
                    style: DS.rowSub.copyWith(color: soft),
                  ),
                ],
              ),
            ),
          ),
          if (s.homes.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Change home',
              icon: Icon(Icons.home_work_outlined, color: ink),
              onSelected: (id) {
                setState(() => _pick = null);
                _home.chooseHome(id);
              },
              itemBuilder: (_) => [
                for (final (id, name) in s.homes)
                  CheckedPopupMenuItem(
                    value: id,
                    checked: id == s.homeId,
                    child: Text(name),
                  ),
              ],
            ),
          if (!widget.full) ...[
            if (swatches != null)
              _mode(1, Icons.palette_outlined, 'Colour', ink),
            if (slider != null)
              _mode(2, Icons.brightness_6_outlined, 'Brightness', ink),
          ],
          _Power(
            ink: ink,
            on: on.isNotEmpty,
            enabled: live.isNotEmpty,
            onTap: () {
              HapticFeedback.selectionClick();
              _home.setLights(target, 'on', on.isEmpty);
            },
          ),
        ],
      );

      final chips = SizedBox(
        height: 40,
        child: ListView(
          key: const ValueKey(
            'chips',
          ), // compact swaps rows: each keeps its own scroll
          scrollDirection: Axis.horizontal,
          children: [
            _Chip(
              ink: ink,
              label: 'All',
              selected: _pick == null,
              onTap: () => setState(() => _pick = null),
            ),
            for (final d in s.lights)
              _Chip(
                ink: ink,
                label: d.name,
                selected: _pick == d.id,
                enabled: d.online,
                dot: d.online && d.on ? (d.shade ?? kelvinColour(2700)) : null,
                onTap: () => setState(() => _pick = d.id),
                onPower: d.online
                    ? () {
                        HapticFeedback.selectionClick();
                        _home.toggle(d);
                      }
                    : null,
              ),
            if (rooms.length > 1)
              for (final r in rooms)
                _Chip(
                  ink: ink,
                  label: r,
                  selected: _pick == 'room:$r',
                  onTap: () => setState(() => _pick = 'room:$r'),
                ),
          ],
        ),
      );

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          SizedBox(height: widget.full ? DS.s8 : DS.s4),
          if (widget.full) chips,
          if (widget.full) ...[
            if (slider != null) ...[const SizedBox(height: DS.s4), slider],
            ?swatches,
          ] else
            switch (_row) {
              1 when swatches != null => swatches,
              2 when slider != null => SizedBox(height: 40, child: slider),
              _ => chips,
            },
        ],
      );
    },
  );
}

class _Line extends StatelessWidget {
  const _Line({
    required this.ink,
    required this.soft,
    required this.title,
    required this.sub,
    required this.onTap,
  });
  final Color ink, soft;
  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Row(
      children: [
        Icon(Icons.lightbulb_outline_rounded, color: ink),
        const SizedBox(width: DS.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: DS.rowTitle.copyWith(color: ink)),
              Text(
                sub,
                style: DS.rowSub.copyWith(color: soft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// On/off for what's picked: filled while anything in it is on.
class _Power extends StatelessWidget {
  const _Power({
    required this.ink,
    required this.on,
    required this.enabled,
    required this.onTap,
  });
  final Color ink;
  final bool on, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: on,
    label: 'Power',
    child: GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? ink : Colors.transparent,
            border: Border.all(
              color: ink.withValues(alpha: on ? 1 : .5),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.power_settings_new_rounded,
            size: 22,
            color: on
                ? (ink.computeLuminance() > .5 ? Colors.black : Colors.white)
                : ink.withValues(alpha: enabled ? 1 : .4),
          ),
        ),
      ),
    ),
  );
}

/// A pick: All, a room, or a light (whose dot is its own on/off).
class _Chip extends StatelessWidget {
  const _Chip({
    required this.ink,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.dot,
    this.onPower,
  });
  final Color ink;
  final String label;
  final bool selected, enabled;
  final Color? dot;
  final VoidCallback onTap;
  final VoidCallback? onPower;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: DS.s8),
    child: Opacity(
      opacity: enabled ? 1 : .45,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: BorderSide(color: ink.withValues(alpha: selected ? .9 : .25)),
          ),
          color: ink.withValues(alpha: selected ? .2 : .06),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onPower != null || dot != null)
              Semantics(
                button: true,
                toggled: dot != null,
                label: '$label on or off',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPower,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dot ?? Colors.transparent,
                        border: Border.all(
                          color: ink.withValues(alpha: .6),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Semantics(
              button: true,
              selected: selected,
              label: label,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    onPower != null || dot != null ? 4 : 14,
                    0,
                    14,
                    0,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      DS.cased(label),
                      style: DS.pill.copyWith(color: ink),
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colour,
    required this.label,
    required this.ring,
    required this.selected,
    required this.onTap,
  });
  final Color colour, ring;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.only(right: DS.s4),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? ring : Colors.transparent,
            width: 2,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(color: ring.withValues(alpha: .3)),
          ),
        ),
      ),
    ),
  );
}
