import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/perf.dart';

/// When a surface (Start, or the app list) was last landed on: its tiles / rows play their
/// entrance from that moment, each after its own small delay.
class Landing extends ChangeNotifier {
  DateTime at = DateTime(0);
  void play() {
    at = DateTime.now();
    notifyListeners();
  }
}

final startLanding = Landing(), listLanding = Landing();

/// Entrance styles the user picks from (Settings → Home view).
const landingStyles = [('turnstile', 'Turnstile'), ('cascade', 'Cascade'), ('zoom', 'Zoom'), ('slide', 'Slide'), ('none', 'None')];

/// Plays [style] on [child] each time [landing] plays, [delay] after it. Rows built later
/// (scrolling) appear settled. Lighter effects: no entrance.
class Landed extends StatefulWidget {
  const Landed({super.key, required this.landing, required this.style, required this.delay, required this.child});
  final Landing landing;
  final String style;
  final Duration delay;
  final Widget child;

  @override
  State<Landed> createState() => _LandedState();
}

class _LandedState extends State<Landed> with SingleTickerProviderStateMixin {
  static const _dur = Duration(milliseconds: 460);
  late final _c = AnimationController(vsync: this, duration: _dur, value: 1);
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    widget.landing.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.landing.removeListener(_sync);
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _sync() {
    _wait?.cancel();
    if (widget.style == 'none' || Perf.lite.value) {
      _c.value = 1;
      return;
    }
    final since = DateTime.now().difference(widget.landing.at) - widget.delay;
    if (since >= _dur) {
      _c.value = 1;
    } else if (since.isNegative) {
      _c.value = 0;
      _wait = Timer(-since, () {
        if (mounted) _c.forward(from: 0);
      });
    } else {
      _c.forward(from: since.inMicroseconds / _dur.inMicroseconds);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final t = Curves.easeOutCubic.transform(_c.value), u = 1 - t;
      // Same tree at every frame (Opacity + Transform), so the child never remounts.
      final (Matrix4 m, Alignment at) = switch (widget.style) {
        'turnstile' => (
          Matrix4.identity()
            ..setEntry(3, 2, .0012)
            ..rotateY(-u * math.pi * .45),
          Alignment.centerLeft,
        ),
        'cascade' => (Matrix4.translationValues(0, 28 * u, 0), Alignment.center),
        'zoom' => (Matrix4.diagonal3Values(.8 + .2 * t, .8 + .2 * t, 1), Alignment.center),
        'slide' => (Matrix4.translationValues(72 * u, 0, 0), Alignment.center),
        _ => (Matrix4.identity(), Alignment.center),
      };
      return Opacity(
        opacity: widget.style == 'none' ? 1 : t.clamp(0, 1),
        child: Transform(transform: m, alignment: at, child: child),
      );
    },
  );
}
