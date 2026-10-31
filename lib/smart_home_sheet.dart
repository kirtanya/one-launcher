import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'smart_home.dart';
import 'ui/components.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'ui/perf.dart';
import 'widgets.dart';

/// Opens the Smart home sheet (quick chip `b:home`, the top page's "All devices", Tiles' `qa:b:home`).
Future<Object?> showSmartHome(BuildContext context) {
  SmartHome.instance.refresh();
  final h = MediaQuery.sizeOf(context).height;
  return showOneSheetWith(
    context,
    height: h * .8,
    builder: (_) => const SmartHomeBody(),
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
  const SmartHomeBody({super.key});

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
                  Padding(
                    padding: const EdgeInsets.only(top: DS.s8, bottom: DS.s8),
                    child: Text(DS.cased(room), style: DS.eyebrow),
                  ),
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
                          Icon(smartIcon(d.type), size: 24, color: ink),
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
