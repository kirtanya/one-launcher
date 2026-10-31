import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'smart_home.dart';
import 'ui/components.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'ui/perf.dart';
import 'widgets.dart';

/// Opens the Smart home sheet (the nav's Smart home tab, quick chip `b:home`, the top page's
/// "All devices", Tiles' `qa:b:home`). [onRemote] adds the TV remote as the first tile.
Future<Object?> showSmartHome(BuildContext context, {VoidCallback? onRemote}) {
  SmartHome.instance.refresh();
  final h = MediaQuery.sizeOf(context).height;
  return showOneSheetWith(
    context,
    height: h * .8,
    builder: (_) => SmartHomeBody(onRemote: onRemote),
  );
}

IconData smartIcon(SmartType t) => switch (t) {
  SmartType.light => Icons.lightbulb_outline_rounded,
  SmartType.plug => Icons.electrical_services_rounded,
  SmartType.ac => Icons.ac_unit_rounded,
  SmartType.fan => Icons.air_rounded,
  SmartType.switch_ => Icons.toggle_on_outlined,
  SmartType.other => Icons.devices_other_rounded,
};

String acModeLabel(AcMode m) => switch (m) {
  AcMode.cool => 'Cool',
  AcMode.heat => 'Heat',
  AcMode.auto => 'Auto',
  AcMode.fan => 'Fan',
  AcMode.off => 'Off',
};

String _degrees(double v) =>
    '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)}°';

/// One line under a device's name: its state in words.
String smartSub(SmartDevice d) {
  if (!d.online) return 'Offline';
  if (d.type == SmartType.ac) {
    if (!d.on || d.mode == AcMode.off) return 'Off';
    return [
      if (d.setpoint != null) _degrees(d.setpoint!),
      if (d.mode != null) acModeLabel(d.mode!),
    ].join(' · ');
  }
  if (!d.on) return 'Off';
  return d.brightness != null ? 'On · ${d.brightness}%' : 'On';
}

double get _tileRadius => DS.metro ? DS.rCard : 20.0;

class SmartHomeBody extends StatelessWidget {
  const SmartHomeBody({super.key, this.onRemote});
  final VoidCallback? onRemote;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SmartHomeState>(
      valueListenable: SmartHome.instance.state,
      builder: (context, s, _) {
        final ready =
            s.status == SmartHomeStatus.ready ||
            (s.status == SmartHomeStatus.loading && s.devices.isNotEmpty);
        return Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader(
                title: 'Smart home',
                subtitle: 'Lights, plugs and AC',
              ),
              const SizedBox(height: DS.s16),
              if (onRemote != null) ...[
                _RemoteTile(onTap: onRemote!),
                const SizedBox(height: DS.s12),
              ],
              if (!ready && s.status == SmartHomeStatus.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: DS.s32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!ready)
                SmartSetupCard(state: s)
              else if (s.devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: DS.s24),
                  child: Text(
                    'No devices yet. Add some in Google Home.',
                    style: DS.rowSub,
                  ),
                )
              else
                for (final room in s.rooms) ...[
                  _RoomHeader(room: room, devices: s.inRoom(room)),
                  _Grid(devices: s.inRoom(room)),
                ],
              if (ready && s.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: DS.s12),
                  child: Text(s.error!, style: DS.rowSub),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The TV remote, living in Smart home since it took the remote's place in the nav.
class _RemoteTile extends StatelessWidget {
  const _RemoteTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    scale: Perf.lite.value ? 1 : .97,
    child: RoleSurface(
      role: SurfaceRole.key,
      color: DS.cardMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
      child: Semantics(
        button: true,
        label: 'TV remote',
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            SheetHost.close(context); // the remote opens in place of this sheet
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(DS.s16),
            child: Row(
              children: [
                Icon(Icons.settings_remote_rounded, color: DS.ink, size: 24),
                const SizedBox(width: DS.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DS.cased('TV remote'), style: DS.rowTitle),
                      Text('Control the TV', style: DS.rowSub),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: DS.inkMuted),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Grid extends StatelessWidget {
  const _Grid({required this.devices});
  final List<SmartDevice> devices;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = (c.maxWidth - DS.s12) / 2;
      return Wrap(
        spacing: DS.s12,
        runSpacing: DS.s12,
        children: [
          for (final d in devices)
            SizedBox(
              width: w,
              child: SmartTile(device: d),
            ),
        ],
      );
    },
  );
}

/// A device: tap toggles, long-press or the chevron opens its detail page.
class SmartTile extends StatelessWidget {
  const SmartTile({super.key, required this.device});
  final SmartDevice device;

  void _detail(BuildContext context) {
    HapticFeedback.selectionClick();
    showOneSheetWith(
      context,
      height: MediaQuery.sizeOf(context).height * .8,
      builder: (_) => SmartDetail(id: device.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = device;
    final lit = d.on && d.online;
    final ink = lit ? DS.heroInk : DS.ink;
    final muted = lit ? DS.heroMuted : DS.inkMuted;
    return Opacity(
      opacity: d.online ? 1 : .5,
      child: Pressable(
        scale: Perf.lite.value ? 1 : .97,
        enabled: d.online,
        child: RoleSurface(
          role: SurfaceRole.key,
          selected: lit,
          color: lit ? DS.hero : DS.cardMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_tileRadius),
          ),
          child: Semantics(
            button: true,
            label: '${d.name}, ${smartSub(d)}',
            child: InkWell(
              onTap: d.online
                  ? () {
                      HapticFeedback.selectionClick();
                      SmartHome.instance.toggle(d);
                    }
                  : null,
              onLongPress: () => _detail(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DS.s16,
                  DS.s12,
                  DS.s4,
                  DS.s12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(smartIcon(d.type), size: 24, color: ink),
                              if (lit && d.shade != null) ...[
                                const SizedBox(width: DS.s8),
                                _Dot(colour: d.shade!, ring: ink),
                              ],
                            ],
                          ),
                          const SizedBox(height: DS.s12),
                          Text(
                            d.name,
                            style: DS.rowTitle.copyWith(color: ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            smartSub(d),
                            style: DS.rowSub.copyWith(color: muted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Details',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.chevron_right_rounded, color: muted),
                      onPressed: () => _detail(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Detail page inside the sheet: on/off, brightness for lights, setpoint and mode for an AC.
class SmartDetail extends StatefulWidget {
  const SmartDetail({super.key, required this.id});
  final String id;

  @override
  State<SmartDetail> createState() => _SmartDetailState();
}

class _SmartDetailState extends State<SmartDetail> {
  double? _drag; // brightness while the thumb is down

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SmartHomeState>(
      valueListenable: SmartHome.instance.state,
      builder: (context, s, _) {
        final d = s.byId(widget.id);
        if (d == null) {
          return Padding(
            padding: const EdgeInsets.all(DS.s24),
            child: Text('This device is gone.', style: DS.rowSub),
          );
        }
        final home = SmartHome.instance;
        return Padding(
          padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(
                title: d.name,
                yours: true,
                subtitle: [
                  if (d.room.isNotEmpty) d.room,
                  smartSub(d),
                ].join(' · '),
                leading: Icon(smartIcon(d.type), color: DS.ink, size: 28),
              ),
              const SizedBox(height: DS.s16),
              OneCard(
                tone: CardTone.muted,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.online ? 'Power' : 'Offline',
                        style: DS.rowTitle,
                      ),
                    ),
                    Switch(
                      value: d.on,
                      onChanged: d.online
                          ? (v) => home.set(d.id, 'on', v)
                          : null,
                    ),
                  ],
                ),
              ),
              if (d.type == SmartType.light && d.dimmable) ...[
                const SizedBox(height: DS.s12),
                OneCard(
                  tone: CardTone.muted,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Brightness', style: DS.rowTitle),
                          ),
                          Text(
                            '${(_drag ?? d.brightness!).round()}%',
                            style: DS.rowSub,
                          ),
                        ],
                      ),
                      Slider(
                        value: (_drag ?? d.brightness!).toDouble(),
                        min: 0,
                        max: 100,
                        onChanged: d.online
                            ? (v) => setState(() => _drag = v)
                            : null,
                        onChangeEnd: (v) {
                          setState(() => _drag = null);
                          home.set(d.id, 'brightness', v.round());
                        },
                      ),
                    ],
                  ),
                ),
              ],
              if (d.type == SmartType.light && (d.canColor || d.canTemp)) ...[
                const SizedBox(height: DS.s12),
                _ColourCard(d: d),
              ],
              if (d.type == SmartType.light && d.effects) ...[
                const SizedBox(height: DS.s12),
                _EffectsCard(d: d),
              ],
              if (d.type == SmartType.ac) ...[
                const SizedBox(height: DS.s12),
                OneCard(
                  tone: CardTone.muted,
                  child: Row(
                    children: [
                      CircleButton(
                        icon: Icons.remove_rounded,
                        tooltip: 'Cooler',
                        tone: CircleTone.soft,
                        onTap: () => d.online && (d.setpoint ?? 24) > 16
                            ? home.set(d.id, 'setpoint', (d.setpoint ?? 24) - 1)
                            : null,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _degrees(d.setpoint ?? 24),
                              style: DS.title.copyWith(fontSize: 44),
                            ),
                            Text('Set to', style: DS.rowSub),
                          ],
                        ),
                      ),
                      CircleButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Warmer',
                        tone: CircleTone.soft,
                        onTap: () => d.online && (d.setpoint ?? 24) < 30
                            ? home.set(d.id, 'setpoint', (d.setpoint ?? 24) + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DS.s12),
                Wrap(
                  spacing: DS.s8,
                  runSpacing: DS.s8,
                  children: [
                    for (final m in AcMode.values)
                      _ModeChip(
                        label: acModeLabel(m),
                        selected: d.on ? d.mode == m : m == AcMode.off,
                        onTap: d.online
                            ? () => home.set(d.id, 'mode', m.name)
                            : null,
                      ),
                  ],
                ),
              ],
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: DS.s12),
                  child: Text(s.error!, style: DS.rowSub),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A room's name, with all on / all off for its devices.
class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.room, required this.devices});
  final String room;
  final List<SmartDevice> devices;

  @override
  Widget build(BuildContext context) {
    final live = devices.where((d) => d.online).toList();
    final anyOn = live.any((d) => d.on);
    return Padding(
      padding: const EdgeInsets.only(top: DS.s4, bottom: DS.s4),
      child: Row(
        children: [
          Expanded(child: Text(DS.cased(room), style: DS.eyebrow)),
          if (live.length > 1)
            TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                SmartHome.instance.setRoom(room, !anyOn);
              },
              child: Text(DS.cased(anyOn ? 'All off' : 'All on'), style: DS.pill.copyWith(color: DS.ink)),
            )
          else
            const SizedBox(height: 48),
        ],
      ),
    );
  }
}

/// A light's current colour, on its tile.
class _Dot extends StatelessWidget {
  const _Dot({required this.colour, required this.ring});
  final Color colour, ring;
  static const size = 12.0;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: colour,
      shape: BoxShape.circle,
      border: Border.all(color: ring.withValues(alpha: .35)),
    ),
  );
}

const _hues = [0.0, 30.0, 50.0, 120.0, 175.0, 210.0, 260.0, 310.0];
const _whites = [2700, 4000, 6500];

/// Colour and white warmth: quick swatches, then a hue slider and a warm → cool slider.
class _ColourCard extends StatefulWidget {
  const _ColourCard({required this.d});
  final SmartDevice d;

  @override
  State<_ColourCard> createState() => _ColourCardState();
}

class _ColourCardState extends State<_ColourCard> {
  double? _hue, _k; // while a thumb is down

  void _colour(double h, [double s = 1]) {
    HapticFeedback.selectionClick();
    SmartHome.instance.set(widget.d.id, 'color', {'h': h, 's': s});
  }

  void _white(int k) {
    HapticFeedback.selectionClick();
    SmartHome.instance.set(widget.d.id, 'colorTempK', k);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final inColour = d.colorMode == 'color' || (d.colorMode == null && d.hue != null);
    final inWhite = d.colorMode == 'temp';
    final hue = _hue ?? d.hue ?? 0;
    final lo = d.minK.toDouble(), hi = math.max(d.maxK, d.minK + 100).toDouble();
    final k = (_k ?? d.colorTempK?.toDouble() ?? 4000).clamp(lo, hi);
    return OneCard(
      tone: CardTone.muted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.canColor ? 'Colour' : 'White', style: DS.rowTitle),
          const SizedBox(height: DS.s12),
          Wrap(
            spacing: DS.s12,
            runSpacing: DS.s12,
            children: [
              if (d.canTemp)
                for (final w in _whites)
                  _Swatch(
                    colour: kelvinColour(w),
                    label: w <= 3000 ? 'Warm white' : w >= 6000 ? 'Cool white' : 'White',
                    selected: inWhite && d.colorTempK != null && (d.colorTempK! - w).abs() < 300,
                    onTap: d.online ? () => _white(w.clamp(d.minK, d.maxK)) : null,
                  ),
              if (d.canColor)
                for (final h in _hues)
                  _Swatch(
                    colour: HSVColor.fromAHSV(1, h, 1, 1).toColor(),
                    label: 'Colour',
                    selected: inColour && d.hue != null && (d.saturation ?? 1) > .6 && _hueGap(d.hue!, h) < 8,
                    onTap: d.online ? () => _colour(h) : null,
                  ),
            ],
          ),
          if (d.canColor) ...[
            const SizedBox(height: DS.s16),
            _Label('Hue', '${hue.round()}°'),
            _GradientSlider(
              colours: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()],
              value: hue.clamp(0, 360),
              min: 0,
              max: 360,
              onChanged: d.online ? (v) => setState(() => _hue = v) : null,
              onChangeEnd: (v) {
                setState(() => _hue = null);
                _colour(v, d.colorMode == 'color' ? math.max(d.saturation ?? 1, .5) : 1);
              },
            ),
          ],
          if (d.canTemp) ...[
            const SizedBox(height: DS.s8),
            _Label('Warmth', '${(k / 100).round() * 100} K'),
            _GradientSlider(
              colours: [kelvinColour(lo.round()), kelvinColour(((lo + hi) / 2).round()), kelvinColour(hi.round())],
              value: k,
              min: lo,
              max: hi,
              onChanged: d.online ? (v) => setState(() => _k = v) : null,
              onChangeEnd: (v) {
                setState(() => _k = null);
                _white(v.round());
              },
            ),
          ],
        ],
      ),
    );
  }
}

double _hueGap(double a, double b) {
  final g = (a - b).abs() % 360;
  return g > 180 ? 360 - g : g;
}

class _Label extends StatelessWidget {
  const _Label(this.title, this.value);
  final String title, value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: DS.rowSub)),
      Text(value, style: DS.rowSub),
    ],
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colour, required this.label, required this.selected, required this.onTap});
  final Color colour;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.snapDuration,
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? DS.ink : Colors.transparent, width: 2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(color: DS.ink.withValues(alpha: .12)),
          ),
        ),
      ),
    ),
  );
}

/// A slider whose track is a colour gradient (hue, warmth).
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.colours,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });
  final List<Color> colours;
  final double value, min, max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s12),
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colours),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 12,
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Colors.white,
            overlayColor: DS.ink.withValues(alpha: .08),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 2),
            trackShape: const RectangularSliderTrackShape(),
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged, onChangeEnd: onChangeEnd),
        ),
      ],
    ),
  );
}

/// Google Home's light effects: dim slowly to off, or brighten slowly.
class _EffectsCard extends StatelessWidget {
  const _EffectsCard({required this.d});
  final SmartDevice d;

  @override
  Widget build(BuildContext context) {
    void run(String e) {
      HapticFeedback.selectionClick();
      SmartHome.instance.set(d.id, 'effect', d.effect == e ? 'stop' : e);
    }

    return OneCard(
      tone: CardTone.muted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Effects', style: DS.rowTitle),
          Text(
            switch (d.effect) {
              'sleep' => 'Falling asleep: dimming slowly, then off. Tap again to stop.',
              'wake' => 'Waking up: brightening slowly. Tap again to stop.',
              _ => 'Fall asleep dims slowly, then turns off. Wake up brightens slowly.',
            },
            style: DS.rowSub,
          ),
          const SizedBox(height: DS.s12),
          Wrap(
            spacing: DS.s8,
            runSpacing: DS.s8,
            children: [
              _ModeChip(label: 'Fall asleep', selected: d.effect == 'sleep', onTap: d.online ? () => run('sleep') : null),
              _ModeChip(label: 'Wake up', selected: d.effect == 'wake', onTap: d.online ? () => run('wake') : null),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => RoleSurface(
    role: SurfaceRole.key,
    selected: selected,
    color: selected ? DS.hero : DS.cardMuted,
    shape: const StadiumBorder(),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DS.s16,
          vertical: DS.s12,
        ),
        child: Text(
          DS.cased(label),
          style: DS.pill.copyWith(color: selected ? DS.heroInk : DS.ink),
        ),
      ),
    ),
  );
}

/// Shown instead of the devices until Google Home is connected.
class SmartSetupCard extends StatelessWidget {
  const SmartSetupCard({super.key, required this.state});
  final SmartHomeState state;

  @override
  Widget build(BuildContext context) {
    final unavailable = state.status == SmartHomeStatus.unavailable;
    return GestureDetector(
      // Debug builds only: long-press fills fake devices.
      onLongPress: kDebugMode ? SmartHome.instance.debugDemo : null,
      child: OneCard(
        tone: CardTone.muted,
        padding: const EdgeInsets.all(DS.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.home_rounded, size: 32, color: DS.ink),
            const SizedBox(height: DS.s12),
            Text(
              'Control your lights, plugs and AC',
              style: DS.title.copyWith(fontSize: 20),
            ),
            const SizedBox(height: DS.s8),
            Text(
              'Connects to Google Home, so everything you set up there shows up here.',
              style: DS.rowSub,
            ),
            if (state.status == SmartHomeStatus.error &&
                state.error != null) ...[
              const SizedBox(height: DS.s8),
              Text(state.error!, style: DS.rowSub),
            ],
            const SizedBox(height: DS.s20),
            FilledButton(
              style: DS.third
                  ? null
                  : FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
              onPressed: unavailable ? null : SmartHome.instance.connect,
              child: Text(DS.cased('Connect Google Home')),
            ),
            if (unavailable)
              Padding(
                padding: const EdgeInsets.only(top: DS.s8),
                child: Text(
                  'Coming in the next update',
                  style: DS.meta,
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: DS.s8),
            OutlinedButton(
              style: DS.third
                  ? null
                  : OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
              onPressed: SmartHome.instance.openGoogleHome,
              child: Text(DS.cased('Open Google Home')),
            ),
          ],
        ),
      ),
    );
  }
}
