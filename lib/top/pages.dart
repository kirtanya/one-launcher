import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../prefs.dart';
import '../remote_sheet.dart';
import '../tv_remote.dart';
import '../third/tactile/parts.dart';
import '../ui/motion.dart';
import '../ui/components.dart';
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
      child: RoleSurface(
        role: SurfaceRole.key,
        color: DS.glass,
        shape: const StadiumBorder(side: BorderSide(color: DS.glassLine)),
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
    if (DS.third) return _lcdClock(time);
    // The date is the label (tap → Calendar); the time is the big figure (tap → Clock).
    return _Page(
      label: '${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}',
      big: time,
      onTap: widget.onTap,
      onTapLabel: widget.onTapDate,
      semantics: 'Time $time. Opens Clock',
    );
  }

  /// Tactile: the clock on a backlit dot-matrix display — date above (tap → Calendar), the time
  /// big (tap → Clock), sized to the space.
  Widget _lcdClock(String time) {
    final date = '${_days[now.weekday - 1].substring(0, 3)} ${now.day} ${_months[now.month - 1]}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: DS.s8),
      child: LayoutBuilder(
        builder: (context, c) {
          // The time fills the width (or the height, if that's what runs out first).
          final dot = ((c.maxWidth - 40) / (DotMatrix.widthOf(time, 1))).clamp(3.0, 11.0);
          final fit = ((c.maxHeight - 60) / 7).clamp(3.0, 11.0);
          final d = dot < fit ? dot : fit;
          return Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              label: 'Time $time, $date. Opens Clock',
              child: TLcd(
                radius: 18,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: widget.onTapDate,
                      child: DotMatrix(date, dot: 2.6, color: TLcd.text),
                    ),
                    SizedBox(height: d * 1.2),
                    GestureDetector(
                      onTap: widget.onTap,
                      child: DotMatrix(time, dot: d, color: TLcd.text),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
  late final _steady = SteadyPlaying(() {
    if (mounted) setState(() {});
  });
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
    _steady.dispose();
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

    final playing = _playingOverride ?? _steady(m['playing'] == true);
    final duration = (m['duration'] as num?)?.toInt() ?? 0;
    var position = (m['position'] as num?)?.toInt() ?? 0;
    if (m['playing'] == true) {
      final since = DateTime.now().millisecondsSinceEpoch - ((m['at'] as num?)?.toInt() ?? 0);
      position += (since * ((m['speed'] as num?)?.toDouble() ?? 1)).round();
    }
    final progress = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

    final art = m['art'] as Uint8List?;
    final artist = (m['artist'] as String?) ?? '';
    final pkg = m['package'] as String?;
    final canSeek = m['canSeek'] == true && duration > 0;
    final actions = [
      for (final a in (m['actions'] as List?) ?? const [])
        if (a is Map && a['icon'] is Uint8List) a,
    ].take(2).toList();
    final cs = _schemeFor(art);
    final ink = cs.onSurface, soft = cs.onSurface.withValues(alpha: .78);

    // Like Android's media controls: the cover edge to edge under a dark tint of its own colours;
    // app + output on top, title + a big play pill in the middle, ⏮ wavy seek ⏭ (+ the app's own
    // actions) along the bottom. Short top areas drop the top row, then the bottom one.
    final tall = h >= 172, mid = h >= 100;
    // Compact: one row, padded only as much as the height allows.
    final vPad = mid ? DS.s8 : ((h - 44) / 2).clamp(0.0, DS.s8);
    final rowH = tall ? DS.tap : 40.0, mainH = mid ? null : math.min(DS.tap, h - vPad * 2);
    final pillH = tall ? 64.0 : math.min(44.0, h - vPad * 2);
    final title = label.copyWith(fontSize: tall ? 22 : 18, fontWeight: FontWeight.w600, color: ink, shadows: const [], height: 1.15);
    final sub2 = sub.copyWith(fontSize: tall ? 16 : 14, color: soft, shadows: const []);

    Widget iconButton(IconData icon, String label, VoidCallback? onTap, {double size = 26}) => Semantics(
      button: true,
      label: label,
      child: Pressable(
        scale: .88,
        enabled: onTap != null,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox.square(
            dimension: DS.tap,
            child: Icon(icon, size: size, color: ink.withValues(alpha: onTap == null ? .35 : 1)),
          ),
        ),
      ),
    );

    final playPill = Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: Pressable(
        scale: .92,
        child: Material(
          color: cs.primary,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _playingOverride = !playing);
              Apps.instance.mediaPlayPause();
            },
            child: AnimatedContainer(
              duration: DS.medium,
              curve: Curves.easeOutCubic,
              // Playing: a rounder, narrower pill; paused: the long one (Material's shape change).
              width: playing ? pillH * 1.5 : pillH * 1.9,
              height: pillH,
              alignment: Alignment.center,
              child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: pillH * .5, color: cs.onPrimary),
            ),
          ),
        ),
      ),
    );

    final bottom = SizedBox(height: rowH, child: Row(
      children: [
        iconButton(Icons.skip_previous_rounded, 'Previous', m['canPrev'] == false ? null : Apps.instance.mediaPrev),
        Expanded(
          child: WavySeekBar(
            progress: progress,
            playing: playing,
            color: ink,
            track: ink.withValues(alpha: .3),
            onSeek: canSeek ? (p) => Apps.instance.mediaSeek((p * duration).round()) : null,
          ),
        ),
        iconButton(Icons.skip_next_rounded, 'Next', m['canNext'] == false ? null : Apps.instance.mediaNext),
        for (final a in actions)
          Semantics(
            button: true,
            label: '${a['name']}',
            child: Pressable(
              scale: .88,
              child: InkResponse(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Apps.instance.mediaAction('${a['id']}');
                },
                radius: 22,
                child: SizedBox.square(
                  dimension: DS.tap,
                  child: Center(
                    child: Image.memory(a['icon'] as Uint8List, width: 24, height: 24, color: ink, colorBlendMode: BlendMode.srcIn, gaplessPlayback: true),
                  ),
                ),
              ),
            ),
          ),
      ],
    ));

    return Semantics(
      button: true,
      label: 'Open ${m['app']}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: Apps.instance.mediaOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DS.rMedia + 4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (art == null) ColoredBox(color: cs.surfaceContainerHigh) else Image.memory(art, fit: BoxFit.cover, gaplessPlayback: true),
              // The cover's own dark tone over it, so everything reads without a black box.
              ColoredBox(color: Color.lerp(cs.surface, Colors.black, .35)!.withValues(alpha: .62)),
              Padding(
                padding: EdgeInsets.fromLTRB(DS.s16, tall ? DS.s12 : vPad, DS.s12, mid ? DS.s4 : vPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tall)
                      Row(
                        children: [
                          AppBadge(package: pkg, app: '${m['app'] ?? ''}', color: cs.primary, ink: cs.onPrimary),
                          const Spacer(),
                          Semantics(
                            button: true,
                            label: 'Play on another device',
                            child: Pressable(
                              scale: .9,
                              child: Material(
                                color: Colors.transparent,
                                shape: StadiumBorder(side: BorderSide(color: cs.primary, width: 1.5)),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: Apps.instance.mediaOutput,
                                  child: SizedBox(width: 56, height: 36, child: Icon(Icons.cast_rounded, size: 20, color: cs.primary)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const Spacer(),
                    SizedBox(height: mainH, child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${m['title'] ?? ''}', style: title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (artist.isNotEmpty) Text(artist, style: sub2, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        const SizedBox(width: DS.s12),
                        if (!mid) ...[
                          iconButton(Icons.skip_previous_rounded, 'Previous', m['canPrev'] == false ? null : Apps.instance.mediaPrev),
                          playPill,
                          iconButton(Icons.skip_next_rounded, 'Next', m['canNext'] == false ? null : Apps.instance.mediaNext),
                        ] else
                          playPill,
                      ],
                    )),
                    if (mid) ...[const SizedBox(height: DS.s4), bottom] else const Spacer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ColorScheme _schemeFor(Uint8List? art) => coverScheme(art, () {
    if (mounted) setState(() {});
  });

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
/// Media apps report "paused" for a moment between tracks; holding "playing" through that keeps
/// the wave and the play pill from wobbling when the song changes.
class SteadyPlaying {
  SteadyPlaying(this.onChange);
  final VoidCallback onChange; // rebuild once a real pause has lasted
  int _lastOn = 0;
  Timer? _t;

  bool call(bool raw) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (raw) {
      _lastOn = now;
      _t?.cancel();
      _t = null;
      return true;
    }
    final left = 1500 - (now - _lastOn);
    if (left <= 0) return false;
    _t ??= Timer(Duration(milliseconds: left), () {
      _t = null;
      onChange();
    });
    return true;
  }

  void dispose() => _t?.cancel();
}

/// A cover's colours (Material's dynamic colour, dark), shared by the Now playing card and the Now
/// page. Worked out once per cover; until then (and with no cover) a muted rose. [onReady] runs
/// once the colours for [art] are in.
ColorScheme coverScheme(Uint8List? art, VoidCallback onReady) {
  if (art == null || art.isEmpty) return _coverFallback;
  final key = Object.hash(art.length, art[art.length ~/ 3], art[art.length ~/ 2], art[art.length * 2 ~/ 3]);
  final done = _coverDone[key];
  if (done != null) return done;
  final pending = _coverPending.putIfAbsent(key, () {
    if (_coverPending.length > 4) _coverPending.remove(_coverPending.keys.first);
    return ColorScheme.fromImageProvider(provider: MemoryImage(art), brightness: Brightness.dark).then((cs) {
      if (_coverDone.length > 4) _coverDone.remove(_coverDone.keys.first);
      return _coverDone[key] = cs;
    });
  });
  pending.then((_) => onReady(), onError: (_) {});
  return _coverFallback;
}

final _coverDone = <int, ColorScheme>{};
final _coverPending = <int, Future<ColorScheme>>{};
final _coverFallback = ColorScheme.fromSeed(seedColor: const Color(0xFFB4637A), brightness: Brightness.dark);

/// The playing app's icon in a tonal circle, like Android's media controls.
class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.package, required this.app, required this.color, required this.ink});
  final String? package;
  final String app;
  final Color color, ink;

  @override
  Widget build(BuildContext context) {
    final mono = package == null ? null : Apps.instance.monoNow(package!);
    final full = package == null || mono != null ? null : Apps.instance.iconNow(package!);
    return ExcludeSemantics(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: mono != null
            ? Image(image: mono, width: 22, height: 22, color: ink, colorBlendMode: BlendMode.srcIn, gaplessPlayback: true)
            : full != null
            ? ClipOval(child: Image(image: full, width: 26, height: 26, gaplessPlayback: true))
            : Icon(Icons.music_note_rounded, size: 20, color: ink),
      ),
    );
  }
}

/// Material 3's wavy seek bar: the played part is a gentle wave that moves while playing and
/// flattens when paused; the rest is a flat, fainter line; a short upright bar is the thumb.
/// Drag or tap to seek when [onSeek] is set.
class WavySeekBar extends StatefulWidget {
  const WavySeekBar({super.key, required this.progress, required this.playing, required this.color, required this.track, this.onSeek});
  final double progress; // 0..1
  final bool playing;
  final Color color, track;
  final ValueChanged<double>? onSeek;

  @override
  State<WavySeekBar> createState() => _WavySeekBarState();
}

class _WavySeekBarState extends State<WavySeekBar> with TickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _amp = AnimationController(vsync: this, duration: DS.medium, value: widget.playing ? 1 : 0);
  double? _drag; // local position while the finger is down

  @override
  void initState() {
    super.initState();
    if (widget.playing) _phase.repeat();
  }

  @override
  void didUpdateWidget(WavySeekBar old) {
    super.didUpdateWidget(old);
    if (widget.playing != old.playing) {
      if (widget.playing) {
        _phase.repeat();
        _amp.forward();
      } else {
        _amp.reverse().whenComplete(() {
          if (mounted && !widget.playing) _phase.stop();
        });
      }
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    _amp.dispose();
    super.dispose();
  }

  double _at(Offset local, double w) => ((local.dx - 8) / (w - 16)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final seek = widget.onSeek;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final bar = RepaintBoundary(
          child: CustomPaint(
            size: Size(w, DS.tap),
            painter: _WavePainter(
              progress: _drag ?? widget.progress,
              phase: _phase,
              amp: _amp,
              color: widget.color,
              track: widget.track,
              thick: _drag != null,
            ),
          ),
        );
        if (seek == null) return ExcludeSemantics(child: bar);
        return Semantics(
          slider: true,
          label: 'Seek',
          value: '${((_drag ?? widget.progress) * 100).round()}%',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => setState(() => _drag = _at(d.localPosition, w)),
            onHorizontalDragUpdate: (d) => setState(() => _drag = _at(d.localPosition, w)),
            onHorizontalDragEnd: (_) {
              final p = _drag;
              setState(() => _drag = null);
              if (p != null) seek(p);
            },
            onHorizontalDragCancel: () => setState(() => _drag = null),
            onTapUp: (d) {
              HapticFeedback.selectionClick();
              seek(_at(d.localPosition, w));
            },
            child: bar,
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.progress, required this.phase, required this.amp, required this.color, required this.track, required this.thick})
    : super(repaint: Listenable.merge([phase, amp]));
  final double progress;
  final Animation<double> phase, amp;
  final Color color, track;
  final bool thick;

  static const _wavelength = 28.0, _height = 3.0, _stroke = 3.5, _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    final cy = size.height / 2;
    final w = size.width - pad * 2;
    final x = pad + w * progress;
    final a = _height * Curves.easeOutCubic.transform(amp.value);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    // Remaining: flat and faint, starting just past the thumb.
    if (x + _gap < size.width - pad) {
      canvas.drawLine(Offset(x + _gap + _stroke / 2, cy), Offset(size.width - pad, cy), line..color = track);
    }
    // Played: the wave, ending just before the thumb; its height eases in from the left edge.
    final end = x - _gap - _stroke / 2;
    if (end > pad) {
      final path = Path()..moveTo(pad, cy);
      final shift = phase.value * 2 * math.pi;
      for (var px = pad; px <= end; px += 1) {
        final ramp = ((px - pad) / 12).clamp(0.0, 1.0);
        path.lineTo(px, cy + math.sin((px - pad) / _wavelength * 2 * math.pi - shift) * a * ramp);
      }
      canvas.drawPath(path, line..color = color);
    }
    // Thumb: an upright rounded bar.
    final th = thick ? 26.0 : 20.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, cy), width: thick ? 6 : 4.5, height: th), const Radius.circular(3)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.progress != progress || o.color != color || o.track != track || o.thick != thick;
}

class _Control extends StatelessWidget {
  const _Control({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  bool get enabled => true;

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
            child: RoleSurface(
              role: SurfaceRole.key,
              color: primary ? DS.onWallpaper : DS.glass,
              shape: CircleBorder(side: primary ? BorderSide.none : const BorderSide(color: DS.glassLine)),
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

/// Top page "TV remote" (off until switched on in the top pages): what's on the TV and play /
/// pause, volume and mute, without opening the remote. Connects on the first tap if needed.
class TvRemotePage extends StatefulWidget {
  const TvRemotePage({super.key, required this.prefs});
  final Prefs prefs;

  @override
  State<TvRemotePage> createState() => _TvRemotePageState();
}

class _TvRemotePageState extends State<TvRemotePage> {
  final tv = TvRemote.instance;
  String? _title;
  ForegroundTimer? _tick;

  @override
  void initState() {
    super.initState();
    _poll();
    _tick = ForegroundTimer(const Duration(seconds: 4), _poll);
  }

  @override
  void dispose() {
    _tick?.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    final host = widget.prefs.tvHost;
    if (host == null || tv.status.value != TvStatus.connected) return;
    final now = await tv.nowPlaying(host, widget.prefs.tvPhoneToken);
    if (mounted) setState(() => _title = now?['active'] == true ? '${now!['title']} · ${now['app']}' : null);
  }

  Future<void> _key(int code) async {
    HapticFeedback.selectionClick();
    final host = widget.prefs.tvHost;
    if (host == null) return;
    if (tv.status.value != TvStatus.connected) await tv.connect(host);
    await tv.key(code);
    Future.delayed(const Duration(milliseconds: 600), _poll);
  }

  @override
  Widget build(BuildContext context) {
    final label = DS.wallpaperDate;
    final sub = DS.wallpaperDate.copyWith(fontSize: 14, color: DS.clockInk, fontWeight: FontWeight.w400);
    final paired = widget.prefs.tvHost != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 24,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(paired ? 'TV · ${widget.prefs.tvName}' : 'TV remote', style: label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const Spacer(),
          ValueListenableBuilder<TvStatus>(
            valueListenable: tv.status,
            builder: (context, status, _) => Text(
              !paired ? 'Set up your TV to control it from here.' : (status != TvStatus.connected ? 'Tap a button to connect' : (_title ?? 'Nothing playing')),
              style: sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: DS.s8),
          if (!paired)
            GlassPill(
              onTap: () => showTvRemote(context, prefs: widget.prefs),
              child: Text('Set up a TV', style: DS.wallpaperDate.copyWith(fontSize: 14, shadows: const [])),
            )
          else
            Row(
              children: [
                _Control(icon: Icons.volume_down_rounded, label: 'Volume down', onTap: () => _key(TvKey.volumeDown)),
                _Control(icon: Icons.volume_off_rounded, label: 'Mute', onTap: () => _key(TvKey.mute)),
                _Control(icon: Icons.play_arrow_rounded, label: 'Play / pause', primary: true, onTap: () => _key(TvKey.playPause)),
                _Control(icon: Icons.volume_up_rounded, label: 'Volume up', onTap: () => _key(TvKey.volumeUp)),
                _Control(
                  icon: Icons.settings_remote_rounded,
                  label: 'Open remote',
                  onTap: () => showTvRemote(context, prefs: widget.prefs),
                ),
              ],
            ),
          const Spacer(),
        ],
      ),
    );
  }
}
