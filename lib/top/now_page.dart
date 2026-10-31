import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../ui/motion.dart';
import '../ui/ds.dart';
import 'pages.dart' show ForegroundTimer, GlassPill;

/// The Now page: the top carousel's page 0 (home opens on page 1). It reads what the system is
/// doing from notifications — music for now — and takes over the whole top area edge to edge:
/// the wallpaper is hidden behind [NowStage] (the cover art, edge to edge), [NowPage] sits on it.
///
/// [away]: 0 while page 0 shows, 1 once you've swiped to page 1 or beyond. The carousel writes
/// it; home's [NowStage] dissolves with it while only the page's content slides.
final nowAway = ValueNotifier<double>(1);

/// The full-bleed backdrop behind the top area. Nothing is built while the page is off screen.
class NowStage extends StatelessWidget {
  const NowStage({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: nowAway,
    builder: (context, away, _) {
      if (away >= 1) return const SizedBox.shrink();
      // Stays put and dissolves while the page's content slides. The backdrop is
      // drawn once into its own layer, so the fade only re-composites it.
      return Opacity(
        opacity: (1 - away).clamp(0.0, 1.0),
        child: const RepaintBoundary(child: _Backdrop()),
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
                : Image.memory(
                    art,
                    key: ValueKey(art.length ^ art.hashCode),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    width: double.infinity,
                    height: double.infinity,
                  ),
          ),
          // The cover edge to edge; scrims keep white type readable: darker at the top (status
          // bar) and heavier toward the bottom, where the title and controls sit.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x26000000), Color(0x8C000000), Color(0xE6000000)],
                stops: [0, .3, .6, 1],
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Page 0's content, over [NowStage] (the cover): the track in big type, progress and controls.
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
            // The title is the hero now that the cover is the background.
            Text(
              '${m['title'] ?? ''}',
              style: DS.wallpaperDate.copyWith(fontSize: 28, height: 1.15, fontWeight: FontWeight.w700, shadows: const []),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (artist.isNotEmpty) ...[const SizedBox(height: 2), Text(artist, style: sub, maxLines: 1, overflow: TextOverflow.ellipsis)],
            const SizedBox(height: DS.s16),
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
