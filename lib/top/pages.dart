import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../ui/motion.dart';
import '../ui/ds.dart';
import '../widgets.dart';
import 'header_fonts.dart';

/// A periodic timer that only runs while the launcher is on screen (saves battery and keeps
/// other apps smooth). Coming back to the launcher fires it once straight away.
class ForegroundTimer {
  ForegroundTimer(this.every, this.tick) {
    _start();
    _life = AppLifecycleListener(onResume: () => _start(now: true), onHide: _stop);
  }

  final Duration every;
  final VoidCallback tick;
  Timer? _timer;
  late final AppLifecycleListener _life;

  void _start({bool now = false}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => tick());
    if (now) tick();
  }

  void _stop() => _timer?.cancel();

  void dispose() {
    _stop();
    _life.dispose();
  }
}

/// Ticks once a minute (checks every second so it flips on time) — only while visible.
mixin Ticking<W extends StatefulWidget> on State<W> {
  DateTime now = DateTime.now();
  ForegroundTimer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = ForegroundTimer(const Duration(seconds: 1), () {
      final n = DateTime.now();
      if (n.minute != now.minute && mounted) setState(() => now = n);
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
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
          // Short top area (small split + chips row): tighter label, and the detail line only
          // when there's room — the big figure always keeps at least half the height.
          child: LayoutBuilder(
            builder: (context, c) {
              final tight = c.maxHeight < 120;
              final showDetail = detail != null && c.maxHeight >= 96;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: tight ? 22 : 32,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: onTapLabel,
                        child: Text(
                          label,
                          style: tight ? DS.wallpaperDate.copyWith(fontSize: 14) : DS.wallpaperDate,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Text(big, style: HeaderFontScope.of(context)),
                      ),
                    ),
                  ),
                  SizedBox(height: tight ? DS.s4 : DS.s8), // breathing room under the big figure
                  if (showDetail) ...[detail!, const SizedBox(height: DS.s4)],
                ],
              );
            },
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
  ForegroundTimer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    widget.refresh.addListener(_load);
    _timer = ForegroundTimer(const Duration(minutes: 1), _load);
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    _timer?.dispose();
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
              Flexible(
                child: Text(
                  'Allow usage access',
                  style: DS.wallpaperDate.copyWith(fontSize: 14, shadows: const []),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
  ForegroundTimer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    widget.refresh.addListener(_load);
    _timer = ForegroundTimer(const Duration(seconds: 30), _load);
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    _timer?.dispose();
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
              Flexible(
                child: Text(
                  'Show my calendar',
                  style: DS.wallpaperDate.copyWith(fontSize: 14, shadows: const []),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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

// ---- App widget ------------------------------------------------------------------

/// A real Android app widget (hosted natively, shown through a platform view).
/// Taps go to the widget; horizontal swipes still move the carousel.
class AppWidgetPage extends StatelessWidget {
  const AppWidgetPage({super.key, required this.widgetId, required this.label});
  final int widgetId;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      // Previews/tests: a placeholder the size of the widget area.
      return Container(
        decoration: BoxDecoration(
          color: DS.glass,
          borderRadius: BorderRadius.circular(DS.rMedia),
          border: Border.all(color: DS.glassLine),
        ),
        alignment: Alignment.center,
        child: Text(label, style: DS.wallpaperDate),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(DS.rMedia),
      child: AndroidView(
        key: ValueKey('appwidget-$widgetId'),
        viewType: 'one_launcher/appwidget',
        creationParams: {'id': widgetId},
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}

// ---- Now playing -------------------------------------------------------------------

/// What's playing in any music app, with ⏮ ⏯ ⏭. Needs Notification access (Android only shares
/// media sessions with apps that have it); the notifications themselves are ignored.
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  ForegroundTimer? _tick; // moves the progress bar while playing
  bool? _playingOverride; // instant feedback after tapping play/pause

  @override
  void initState() {
    super.initState();
    Apps.instance.refreshMedia();
    Apps.instance.media.addListener(_changed);
    _tick = ForegroundTimer(const Duration(seconds: 1), () {
      if (mounted && (Apps.instance.media.value?['playing'] == true)) setState(() {});
    });
  }

  @override
  void dispose() {
    Apps.instance.media.removeListener(_changed);
    _tick?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() => _playingOverride = null);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) => _build(context, c.maxHeight));

  /// [h]: height available — extras drop out on short top areas so nothing overflows.
  Widget _build(BuildContext context, double h) {
    final m = Apps.instance.media.value ?? const {};
    final label = DS.wallpaperDate;
    final sub = DS.wallpaperDate.copyWith(fontSize: 14, color: DS.clockInk, fontWeight: FontWeight.w400);

    Widget header(String text) => SizedBox(
      height: 24,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );

    if (m['granted'] == false) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: DS.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header('Now playing'),
            const Spacer(),
            if (h >= 110) ...[
              Text('See what’s playing and control it from here.', style: sub, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: DS.s8),
            ],
            GlassPill(
              onTap: Apps.instance.openNotificationAccess,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_note_rounded, size: 18, color: DS.onWallpaper),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Allow notification access',
                      style: DS.wallpaperDate.copyWith(fontSize: 14, shadows: const []),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      );
    }

    if (m['active'] != true) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: DS.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header('Now playing'),
            const Spacer(),
            Row(
              children: [
                _art(null, (h - 32).clamp(32.0, 56.0)),
                const SizedBox(width: DS.s16),
                Expanded(
                  child: Text('Nothing playing.\nStart something in your music app.', style: sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const Spacer(),
          ],
        ),
      );
    }

    final playing = _playingOverride ?? (m['playing'] == true);
    final duration = (m['duration'] as num?)?.toInt() ?? 0;
    var position = (m['position'] as num?)?.toInt() ?? 0;
    if (m['playing'] == true) {
      final since = DateTime.now().millisecondsSinceEpoch - ((m['at'] as num?)?.toInt() ?? 0);
      position += (since * ((m['speed'] as num?)?.toDouble() ?? 1)).round();
    }
    final progress = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (h >= 72) header('Now playing · ${m['app'] ?? ''}'),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final artSize = c.maxHeight.clamp(40.0, 72.0);
                return Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'Open ${m['app']}',
                      child: GestureDetector(onTap: Apps.instance.mediaOpen, child: _art(m['art'] as Uint8List?, artSize)),
                    ),
                    const SizedBox(width: DS.s12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${m['title'] ?? ''}',
                            style: label.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((m['artist'] as String?)?.isNotEmpty ?? false) Text('${m['artist']}', style: sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    _Control(icon: Icons.skip_previous_rounded, label: 'Previous', enabled: m['canPrev'] != false, onTap: Apps.instance.mediaPrev),
                    _Control(
                      icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      label: playing ? 'Pause' : 'Play',
                      primary: true,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _playingOverride = !playing);
                        Apps.instance.mediaPlayPause();
                      },
                    ),
                    _Control(icon: Icons.skip_next_rounded, label: 'Next', enabled: m['canNext'] != false, onTap: Apps.instance.mediaNext),
                  ],
                );
              },
            ),
          ),
          if (duration > 0 && h >= 84) ...[
            const SizedBox(height: DS.s8),
            // Thin glass track, filled as the song plays.
            Container(
              height: 4,
              decoration: BoxDecoration(color: DS.glass, borderRadius: BorderRadius.circular(2)),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(color: DS.onWallpaper, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            const SizedBox(height: DS.s4),
          ],
        ],
      ),
    );
  }

  Widget _art(Uint8List? bytes, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: SizedBox.square(
      dimension: size,
      child: bytes == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: DS.glass,
                border: Border.all(color: DS.glassLine),
                borderRadius: BorderRadius.circular(size * .22),
              ),
              child: Icon(Icons.music_note_rounded, color: DS.onWallpaper, size: size * .45),
            )
          : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    ),
  );
}

/// Round control over the wallpaper: glass, or solid white for play/pause.
class _Control extends StatelessWidget {
  const _Control({required this.icon, required this.label, required this.onTap, this.primary = false, this.enabled = true});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary, enabled;

  @override
  Widget build(BuildContext context) {
    final size = primary ? 48.0 : 40.0;
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: DS.tap,
        child: Center(
          child: Pressable(
            scale: .88,
            enabled: enabled,
            child: Material(
              color: primary ? DS.onWallpaper : DS.glass,
              shape: CircleBorder(side: primary ? BorderSide.none : const BorderSide(color: DS.glassLine)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onTap : null,
                child: SizedBox.square(
                  dimension: size,
                  child: Icon(
                    icon,
                    size: size * .55,
                    color: primary ? const Color(0xFF1F1F1F) : DS.onWallpaper.withValues(alpha: enabled ? 1 : .4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
