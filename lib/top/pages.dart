import 'dart:async';

import 'package:flutter/material.dart';

import '../apps.dart';
import '../ui/motion.dart';
import '../ui/ds.dart';
import '../widgets.dart';

/// Ticks once a minute (checks every second so it flips on time).
mixin Ticking<W extends StatefulWidget> on State<W> {
  DateTime now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = DateTime.now();
      if (n.minute != now.minute) setState(() => now = n);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Shared layout for every page: small label, big condensed figure, then a detail line.
class _Page extends StatelessWidget {
  const _Page({required this.label, required this.big, this.detail, this.onTap, this.onTapLabel, this.semantics});
  final String label;
  final String big;
  final Widget? detail;
  final VoidCallback? onTap, onTapLabel;
  final String? semantics;

  /// The two glass buttons sit at the right end of the label line.
  static const _buttonsWidth = 2 * DS.tap + DS.s8;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: onTap != null,
        label: semantics,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: DS.tap,
                child: Padding(
                  padding: const EdgeInsets.only(right: _buttonsWidth),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: onTapLabel,
                      child: Text(label, style: DS.wallpaperDate, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Text(big, style: DS.clock),
                  ),
                ),
              ),
              const SizedBox(height: DS.s8), // breathing room under the big figure
              if (detail != null) ...[detail!, const SizedBox(height: DS.s4)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass pill used for details on the wallpaper ("Allow usage access", top apps…).
class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      enabled: onTap != null,
      scale: .94,
      child: Material(
        color: DS.glass,
        shape: const StadiumBorder(side: BorderSide(color: DS.glassLine)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.fromLTRB(6, 6, 12, 6), child: child),
        ),
      ),
    );
  }
}

String _duration(int ms) {
  final m = (ms / 60000).round();
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

// ---- Clock --------------------------------------------------------------------

class ClockPage extends StatefulWidget {
  const ClockPage({super.key, required this.onTap, required this.onTapDate});
  final VoidCallback onTap, onTapDate;

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> with Ticking {
  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final is24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final h = is24 ? now.hour : (now.hour % 12 == 0 ? 12 : now.hour % 12);
    final time = '${h.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    // The date is the label (tap → Calendar); the time is the big figure (tap → Clock).
    return _Page(
      label: '${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}',
      big: time,
      onTap: widget.onTap,
      onTapLabel: widget.onTapDate,
      semantics: 'Time $time. Opens Clock',
    );
  }
}

// ---- Screen time --------------------------------------------------------------

class ScreenTimePage extends StatefulWidget {
  const ScreenTimePage({super.key, required this.refresh});
  final Listenable refresh; // app resumed / page shown

  @override
  State<ScreenTimePage> createState() => _ScreenTimePageState();
}

class _ScreenTimePageState extends State<ScreenTimePage> {
  Map _data = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    widget.refresh.addListener(_load);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await Apps.instance.screenTime();
    if (mounted) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    if (_data['granted'] == false) {
      return _Page(
        label: 'Screen time today',
        big: '--',
        onTap: Apps.instance.openUsageAccess,
        detail: GlassPill(
          onTap: Apps.instance.openUsageAccess,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_open_rounded, size: 18, color: DS.onWallpaper),
              const SizedBox(width: 6),
              Text('Allow usage access', style: DS.wallpaperDate.copyWith(fontSize: 14, shadows: const [])),
            ],
          ),
        ),
      );
    }
    final total = (_data['total'] as num?)?.toInt() ?? 0;
    final top = (_data['top'] as List?) ?? const [];
    return _Page(
      label: 'Screen time today',
      big: _data.isEmpty ? '' : _duration(total),
      semantics: 'Screen time today ${_duration(total)}. Opens Digital Wellbeing',
      onTap: Apps.instance.openScreenTime,
      detail: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            for (final t in top.take(3)) ...[
              GlassPill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(AppEntry(package: t['package'] as String, label: t['label'] as String), size: 22),
                    const SizedBox(width: 6),
                    Text(_duration((t['ms'] as num).toInt()), style: DS.wallpaperDate.copyWith(fontSize: 13, shadows: const [])),
                  ],
                ),
              ),
              const SizedBox(width: DS.s8),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- Battery --------------------------------------------------------------------

class BatteryPage extends StatefulWidget {
  const BatteryPage({super.key, required this.refresh});
  final Listenable refresh;

  @override
  State<BatteryPage> createState() => _BatteryPageState();
}

class _BatteryPageState extends State<BatteryPage> {
  Map _data = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    widget.refresh.addListener(_load);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await Apps.instance.battery();
    if (mounted) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    final level = (_data['level'] as num?)?.toInt() ?? -1;
    final charging = _data['charging'] == true;
    final left = (_data['chargeMsLeft'] as num?)?.toInt() ?? -1;
    final status = _data['full'] == true
        ? 'Fully charged'
        : charging
        ? (left > 0 ? 'Charging · full in ${_duration(left)}' : 'Charging')
        : 'On battery';
    return _Page(
      label: 'Battery',
      big: level < 0 ? '' : '$level%',
      semantics: 'Battery $level percent, $status. Opens battery settings',
      onTap: Apps.instance.openBatterySettings,
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Glass track with the charge filled in.
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: DS.glass,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: DS.glassLine),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (level.clamp(0, 100)) / 100,
              child: Container(
                decoration: BoxDecoration(color: charging ? DS.hero : DS.onWallpaper, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
          const SizedBox(height: DS.s8),
          Row(
            children: [
              Icon(charging ? Icons.bolt_rounded : Icons.battery_std_rounded, size: 18, color: DS.onWallpaper, shadows: DS.wallpaperShadow),
              const SizedBox(width: 4),
              Text(status, style: DS.wallpaperDate.copyWith(fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Up next (calendar) ---------------------------------------------------------

class UpNextPage extends StatefulWidget {
  const UpNextPage({super.key, required this.refresh});
  final Listenable refresh;

  @override
  State<UpNextPage> createState() => _UpNextPageState();
}

class _UpNextPageState extends State<UpNextPage> with Ticking {
  Map _data = const {};

  @override
  void initState() {
    super.initState();
    _load();
    widget.refresh.addListener(_load);
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final d = await Apps.instance.nextEvent();
    if (mounted) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    if (_data['granted'] == false) {
      return _Page(
        label: 'Up next',
        big: '--:--',
        onTap: Apps.instance.requestCalendar,
        detail: GlassPill(
          onTap: Apps.instance.requestCalendar,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_available_rounded, size: 18, color: DS.onWallpaper),
              const SizedBox(width: 6),
              Text('Show my calendar', style: DS.wallpaperDate.copyWith(fontSize: 14, shadows: const [])),
            ],
          ),
        ),
      );
    }
    if (_data['id'] == null) {
      return _Page(
        label: 'Up next',
        big: _data.isEmpty ? '' : 'FREE',
        detail: Text('Nothing in the next two days', style: DS.wallpaperDate),
      );
    }
    final begin = DateTime.fromMillisecondsSinceEpoch((_data['begin'] as num).toInt());
    final allDay = _data['allDay'] == true;
    final is24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final h = is24 ? begin.hour : (begin.hour % 12 == 0 ? 12 : begin.hour % 12);
    final time = '${h.toString().padLeft(2, '0')}:${begin.minute.toString().padLeft(2, '0')}';
    final mins = begin.difference(now).inMinutes;
    final when = allDay
        ? (begin.day == now.day ? 'All day today' : 'All day tomorrow')
        : mins <= 0
        ? 'Happening now'
        : mins < 60
        ? 'In $mins min'
        : begin.day == now.day
        ? 'Today'
        : 'Tomorrow';
    return _Page(
      label: 'Up next · $when',
      big: allDay ? 'ALL DAY' : time,
      semantics: 'Up next: ${_data['title']}, $when',
      onTap: () => Apps.instance.openEvent((_data['id'] as num).toInt()),
      detail: Text(
        _data['title'] as String,
        style: DS.wallpaperDate.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
