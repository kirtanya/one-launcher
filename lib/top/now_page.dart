import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../ui/motion.dart';
import '../ui/ds.dart';
import 'pages.dart' show ForegroundTimer, GlassPill;

/// The Now page: the top carousel's page 0 (home opens on page 1). It reads what the system is
/// doing from notifications — music for now — and takes over the whole top area edge to edge:
/// the wallpaper is hidden behind [NowStage] (the blurred cover art), [NowPage] sits on it.
///
/// [away]: 0 while page 0 shows, 1 once you've swiped to page 1 or beyond. The carousel writes
/// it; home's [NowStage] slides with it so the stage moves with the page, not over it.
final nowAway = ValueNotifier<double>(1);

/// The full-bleed backdrop behind the top area. Nothing is built while the page is off screen.
class NowStage extends StatelessWidget {
  const NowStage({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: nowAway,
    builder: (context, away, _) {
      if (away >= 1) return const SizedBox.shrink();
      return LayoutBuilder(
        // Slides out with the page (no fade: big Opacity layers drop frames on the phone).
        builder: (context, c) => Transform.translate(
          offset: Offset(-c.maxWidth * away, 0),
          child: const ClipRect(child: _Backdrop()),
        ),
      );
    },
  );
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map?>(
    valueListenable: Apps.instance.media,
    builder: (context, m, _) {
      final art = m?['active'] == true ? m!['art'] as Uint8List? : null;
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF0E0E10)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            child: art == null
                ? const SizedBox.expand()
                : ImageFiltered(
                    key: ValueKey(art.length ^ art.hashCode),
                    imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48, tileMode: TileMode.clamp),
                    child: Transform.scale(scale: 1.3, child: Image.memory(art, fit: BoxFit.cover, gaplessPlayback: true)),
                  ),
          ),
          // Keep white type readable on any cover: darker at the top (status bar) and bottom.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x40000000), Color(0xB3000000)],
                stops: [0, .45, 1],
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Page 0's content, over [NowStage]: the cover, the track in big type, progress and controls.
class NowPage extends StatefulWidget {
  const NowPage({super.key});

  @override
  State<NowPage> createState() => _NowPageState();
}

class _NowPageState extends State<NowPage> {
  ForegroundTimer? _tick; // moves the progress bar while playing
  bool? _playingOverride; // instant feedback after tapping play/pause

  @override
  void initState() {
    super.initState();
    Apps.instance.refreshMedia();
    Apps.instance.media.addListener(_changed);
    _tick = ForegroundTimer(const Duration(seconds: 1), () {
      if (mounted && Apps.instance.media.value?['playing'] == true) setState(() {});
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

  static String _time(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) => _build(c.maxHeight));

  Widget _build(double h) {
    final m = Apps.instance.media.value ?? const {};
    final eyebrow = DS.wallpaperDate.copyWith(fontSize: 13, letterSpacing: 1.2, color: DS.clockInk, shadows: const []);
    final sub = DS.wallpaperDate.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: DS.clockInk, shadows: const []);

    if (m['granted'] == false || m['active'] != true) {
      final granted = m['granted'] != false;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: DS.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DS.cased('NOW'), style: eyebrow),
            const Spacer(),
            Text(
              granted ? 'All quiet' : 'See what’s playing',
              style: DS.wallpaperDate.copyWith(fontSize: 28, fontWeight: FontWeight.w600, shadows: const []),
            ),
            const SizedBox(height: DS.s4),
            Text(
              granted ? 'Play some music and it shows up here.' : 'Allow notification access and music shows up here.',
              style: sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (!granted) ...[
              const SizedBox(height: DS.s12),
              GlassPill(
                onTap: Apps.instance.openNotificationAccess,
                child: Text('Allow access', style: sub.copyWith(color: DS.onWallpaper)),
              ),
            ],
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
    position = position.clamp(0, duration > 0 ? duration : position);
    final progress = duration > 0 ? position / duration : 0.0;
    final artist = (m['artist'] as String?) ?? '';
    // Short top areas drop the progress bar first, then the eyebrow.
    final showBar = duration > 0 && h >= 190;
    final showEyebrow = h >= 150;
    final art = (h * .42).clamp(56.0, 120.0);

    // Tapping anywhere but the controls opens the player.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: Apps.instance.mediaOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DS.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showEyebrow)
              Text(DS.cased('NOW PLAYING · ${(m['app'] ?? '').toString().toUpperCase()}'), style: eyebrow, maxLines: 1, overflow: TextOverflow.ellipsis),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Semantics(
                  button: true,
                  label: 'Open ${m['app']}',
                  child: Container(
                    width: art,
                    height: art,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(art * .12),
                      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))],
                      color: const Color(0x33FFFFFF),
                    ),
                    child: m['art'] is Uint8List
                        ? Image.memory(m['art'] as Uint8List, fit: BoxFit.cover, gaplessPlayback: true)
                        : Icon(Icons.music_note_rounded, color: DS.onWallpaper, size: art * .4),
                  ),
                ),
                const SizedBox(width: DS.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${m['title'] ?? ''}',
                        style: DS.wallpaperDate.copyWith(fontSize: 24, height: 1.15, fontWeight: FontWeight.w700, shadows: const []),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (artist.isNotEmpty) ...[const SizedBox(height: 2), Text(artist, style: sub, maxLines: 1, overflow: TextOverflow.ellipsis)],
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (showBar) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: const Color(0x33FFFFFF),
                  valueColor: const AlwaysStoppedAnimation(DS.onWallpaper),
                ),
              ),
              const SizedBox(height: DS.s4),
              Row(
                children: [
                  Text(_time(position), style: sub.copyWith(fontSize: 12)),
                  const Spacer(),
                  Text(_time(duration), style: sub.copyWith(fontSize: 12)),
                ],
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Button(icon: Icons.skip_previous_rounded, label: 'Previous', enabled: m['canPrev'] != false, onTap: Apps.instance.mediaPrev),
                const SizedBox(width: DS.s24),
                _Button(
                  icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  label: playing ? 'Pause' : 'Play',
                  primary: true,
                  onTap: () {
                    setState(() => _playingOverride = !playing);
                    Apps.instance.mediaPlayPause();
                  },
                ),
                const SizedBox(width: DS.s24),
                _Button(icon: Icons.skip_next_rounded, label: 'Next', enabled: m['canNext'] != false, onTap: Apps.instance.mediaNext),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bare controls on the stage: white glyphs, play/pause a solid white disc.
class _Button extends StatelessWidget {
  const _Button({required this.icon, required this.label, required this.onTap, this.primary = false, this.enabled = true});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary, enabled;

  @override
  Widget build(BuildContext context) {
    final size = primary ? 56.0 : DS.tap;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        scale: .88,
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap();
                }
              : null,
          child: Container(
            width: size,
            height: size,
            decoration: primary ? const BoxDecoration(color: DS.onWallpaper, shape: BoxShape.circle) : null,
            child: Icon(
              icon,
              size: primary ? 32 : 34,
              color: primary ? const Color(0xFF111111) : DS.onWallpaper.withValues(alpha: enabled ? 1 : .4),
            ),
          ),
        ),
      ),
    );
  }
}
