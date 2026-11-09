import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'smart_home.dart';
import 'ui/ds.dart';
import 'play_build.dart';

/// Quick light control, for the top page and the side panel's Smart home widget: one row of
/// chips (All, each room, each light: its dot turns it on or off), and for what's picked a
/// power button, brightness and colour (lights first, then rooms). [full] shows the brightness and colour rows too; compact swaps them in for the chips.
class QuickLights extends StatefulWidget {
  const QuickLights({
    super.key,
    required this.ink,
    required this.soft,
    required this.onOpen,
    this.full,
    this.inset = 16,
  });

  /// Left/right inset of the header, brightness bar and the start/end of the scrolling rows
  /// (the rows run edge to edge of the host and fade out under its edges). The host card
  /// should then pad only top and bottom (14–16); pass 0 when the host pads the sides itself.
  final double inset;

  /// Words and icons, and the quieter words (it sits on the wallpaper or a card).
  final Color ink, soft;

  /// Opens the full Smart home sheet (setup, other devices).
  final VoidCallback onOpen;

  /// true: header, chips, brightness and colour; false: header and one swappable row;
  /// null (default): picks from the space it is given (full, compact, or header only).
  final bool? full;

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
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: _ctl, height: _ctl),
    icon: Icon(icon, size: 22, color: ink.withValues(alpha: _row == row ? 1 : .7)),
    style: IconButton.styleFrom(
      minimumSize: const Size(_ctl, _ctl),
      fixedSize: const Size(_ctl, _ctl),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: _row == row ? ink.withValues(alpha: .2) : null,
    ),
  );

  /// A horizontally scrolling row that runs edge to edge: [left]/[right] padding lines its
  /// first/last item up with the header, and it fades under the host's edges.
  Widget _strip(Key key, List<Widget> children, {double? left, double? right, bool fadeLeft = true}) {
    final l = left ?? widget.inset, rt = right ?? widget.inset;
    final list = SizedBox(
      height: _rowH,
      child: ListView(
        key: key,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(left: l, right: rt),
        children: children,
      ),
    );
    final fl = fadeLeft ? l.clamp(0, 24).toDouble() : 0.0, fr = rt.clamp(0, 24).toDouble();
    if (fl == 0 && fr == 0) return list;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) {
        final w = r.width <= 0 ? 1.0 : r.width;
        return LinearGradient(
          colors: const [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [0, fl / w, 1 - fr / w, 1],
        ).createShader(r);
      },
      child: list,
    );
  }

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
    builder: (context, s, _) => LayoutBuilder(builder: (context, c) {
      final ink = widget.ink, soft = widget.soft;
      if (playBuild) return const SizedBox.shrink(); // no Smart home in the Play build
      final ready = s.status == SmartHomeStatus.ready || s.all.isNotEmpty;
      if (!ready || s.lights.isEmpty) {
        return _Line(
          inset: widget.inset,
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

      final tints = [for (final d in on) d.shade ?? kelvinColour(2700)];
      final tint = tints.isEmpty
          ? kelvinColour(2700)
          : Color.from(
              alpha: 1,
              red: tints.fold<double>(0, (a, c) => a + c.r) / tints.length,
              green: tints.fold<double>(0, (a, c) => a + c.g) / tints.length,
              blue: tints.fold<double>(0, (a, c) => a + c.b) / tints.length,
            );
      final slider = !live.any((d) => d.dimmable)
          ? null
          : _BrightBar(
              value: bright.clamp(0, 100).toDouble(),
              ink: ink,
              tint: tint,
              onChanged: (v) {
                setState(() => _drag = v);
                _brightness(live, v);
              },
              onEnd: (v) {
                setState(() => _drag = null);
                _brightness(live, v, end: true);
              },
            );
      final wide = c.maxWidth >= _wideW;
      final wideBoth = wide &&
          live.any((d) => d.dimmable) &&
          (canColour || canWhite);
      final swatches = !(canColour || canWhite)
          ? null
          : _strip(
                const ValueKey('swatches'),
                left: wideBoth ? 0 : (widget.inset - 6).clamp(0, 99).toDouble(),
                fadeLeft: !wideBoth,
                [
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
                ]);

      Widget header(bool showModes) => Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.inset),
        child: SizedBox(height: _headerH, child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpen,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                mainAxisSize: MainAxisSize.min,
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
                        : live.every((d) => d.noReply)
                        ? 'Not responding'
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
          ),
          if (s.homes.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Change home',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: _ctl, height: _ctl),
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
          if (showModes) ...[
            if (swatches != null)
              _mode(1, Icons.palette_outlined, 'Colour', ink),
            if (slider != null)
              _mode(2, Icons.brightness_6_outlined, 'Brightness', ink),
          ],
          if (s.homes.length > 1 || showModes) const SizedBox(width: DS.s4),
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
      )));

      // compact swaps rows: each keeps its own scroll (hence the keys)
      final chips = _strip(
          const ValueKey('chips'),
          [
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
                mark: !d.online ? Icons.cloud_off_rounded : d.noReply ? Icons.error_outline_rounded : null,
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
          ]);

      final both = slider != null && swatches != null;
      final bar = slider == null
          ? null
          : Padding(
              padding: EdgeInsets.only(
                left: widget.inset,
                right: wideBoth ? 0 : widget.inset,
              ),
              child: slider,
            );
      {
          final extra = both
              ? (wide ? _gap + _rowH : 2 * (_gap + _rowH))
              : (slider != null || swatches != null ? _gap + _rowH : 0.0);
          final fullH = _headerH + _gap + _rowH + extra;
          final compactH = _headerH + _cgap + _rowH;
          final mode =
              widget.full ??
              (c.maxHeight.isInfinite || c.maxHeight >= fullH
                  ? true
                  : c.maxHeight >= compactH
                  ? false
                  : null);
          if (mode == null) return header(false);
          if (!mode) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header(true),
                const SizedBox(height: _cgap),
                switch (_row) {
                  1 when swatches != null => swatches,
                  2 when bar != null => SizedBox(
                    height: _rowH,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: widget.inset),
                      child: slider,
                    ),
                  ),
                  _ => chips,
                },
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(false),
              const SizedBox(height: _gap),
              chips,
              if (both && wide) ...[
                const SizedBox(height: _gap),
                Row(
                  children: [
                    Expanded(flex: 5, child: bar!),
                    const SizedBox(width: DS.s12),
                    Expanded(flex: 6, child: swatches),
                  ],
                ),
              ] else ...[
                if (bar != null) ...[const SizedBox(height: _gap), bar],
                if (swatches != null) ...[
                  const SizedBox(height: _gap),
                  swatches,
                ],
              ],
            ],
          );
      }
    }),
  );
}

const _headerH = 44.0, _rowH = 40.0, _gap = 12.0, _cgap = 8.0, _ctl = 40.0, _wideW = 480.0;

/// Brightness as a 40 px stadium bar: the fill is the level, tinted with the lights' colour;
/// tap or drag anywhere on it.
class _BrightBar extends StatelessWidget {
  const _BrightBar({
    required this.value,
    required this.ink,
    required this.tint,
    required this.onChanged,
    required this.onEnd,
  });
  final double value;
  final Color ink, tint;
  final ValueChanged<double> onChanged, onEnd;

  void _step(double d) {
    final v = (value + d).clamp(1, 100).toDouble();
    onChanged(v);
    onEnd(v);
  }

  @override
  Widget build(BuildContext context) {
    final pct = value.round().clamp(0, 100);
    final onFill = tint.computeLuminance() > .5 ? Colors.black : Colors.white;
    Widget content(Color col) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.wb_sunny_outlined, size: 18, color: col),
          const SizedBox(width: DS.s8),
          Text('$pct%', style: DS.pill.copyWith(color: col)),
        ],
      ),
    );
    return Semantics(
      label: 'Brightness',
      slider: true,
      value: '$pct%',
      increasedValue: '${(pct + 10).clamp(1, 100)}%',
      decreasedValue: '${(pct - 10).clamp(1, 100)}%',
      onIncrease: () => _step(10),
      onDecrease: () => _step(-10),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            double at(Offset o) =>
                (o.dx / (w <= 0 ? 1 : w) * 100).clamp(1, 100).toDouble();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final v = at(d.localPosition);
                onChanged(v);
                onEnd(v);
              },
              onHorizontalDragStart: (d) => onChanged(at(d.localPosition)),
              onHorizontalDragUpdate: (d) => onChanged(at(d.localPosition)),
              onHorizontalDragEnd: (_) => onEnd(value.clamp(1, 100)),
              child: SizedBox(
                height: _rowH,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_rowH / 2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: ink.withValues(alpha: .16)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (value / 100).clamp(0, 1),
                          heightFactor: 1,
                          child: ColoredBox(color: tint),
                        ),
                      ),
                      ClipRect(
                        clipper: _Part(value / 100, fill: false),
                        child: content(ink),
                      ),
                      ClipRect(
                        clipper: _Part(value / 100, fill: true),
                        child: content(onFill),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The part of the bar under (fill) or past the fill edge, so the words stay readable on both.
class _Part extends CustomClipper<Rect> {
  const _Part(this.f, {required this.fill});
  final double f;
  final bool fill;
  @override
  Rect getClip(Size s) {
    final x = s.width * f.clamp(0, 1);
    return fill ? Rect.fromLTRB(0, 0, x, s.height) : Rect.fromLTRB(x, 0, s.width, s.height);
  }

  @override
  bool shouldReclip(_Part o) => o.f != f || o.fill != fill;
}

class _Line extends StatelessWidget {
  const _Line({
    required this.inset,
    required this.ink,
    required this.soft,
    required this.title,
    required this.sub,
    required this.onTap,
  });
  final double inset;
  final Color ink, soft;
  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
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
    )),
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
        width: _ctl,
        height: _ctl,
        alignment: Alignment.center,
        child: Container(
          width: _ctl,
          height: _ctl,
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
    this.mark,
  });
  final Color ink;

  /// After the label: offline (cloud off) or not responding (alert).
  final IconData? mark;
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
              label: switch (mark) {
                Icons.cloud_off_rounded => '$label, offline',
                Icons.error_outline_rounded => '$label, not responding',
                _ => label,
              },
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DS.cased(label),
                          style: DS.pill.copyWith(color: ink),
                          maxLines: 1,
                        ),
                        if (mark != null) ...[
                          const SizedBox(width: DS.s4),
                          Icon(mark, size: 14, color: ink),
                        ],
                      ],
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
