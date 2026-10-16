import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/perf.dart';

/// When a surface (Start, or the app list) was last landed on: its tiles / rows play their
/// entrance from that moment, each after its own small delay.
class Landing extends ChangeNotifier {
  DateTime at = DateTime(0);

  /// Leaving (turnstile on launch): everything swings away, [last] (the tapped one) after the rest.
  bool exiting = false;
  String? last;

  void play() {
    at = DateTime.now();
    exiting = false;
    notifyListeners();
  }

  void exit({String? last}) {
    at = DateTime.now();
    exiting = true;
    this.last = last;
    notifyListeners();
  }
}

final startLanding = Landing(), listLanding = Landing(), todayLanding = Landing();

/// Entrance styles the user picks from (Settings → Home view).
const landingStyles = [('turnstile', 'Turnstile'), ('cascade', 'Cascade'), ('zoom', 'Zoom'), ('slide', 'Slide'), ('none', 'None')];

/// Plays [style] on [child] each time [landing] plays, [delay] after it — and when scrolling
/// brings it into view: [reveal] for lazily built rows (they appear as they're built), or
/// [scroll] + [top]/[bottom] (its place in the scrolled content) for tiles built up front.
/// Lighter effects: no entrance.
class Landed extends StatefulWidget {
  const Landed({
    super.key,
    required this.landing,
    required this.style,
    required this.delay,
    required this.child,
    this.reveal = false,
    this.id,
    this.scroll,
    this.top = 0,
    this.bottom = 0,
  });
  final Landing landing;
  final String style;
  final Duration delay;
  final Widget child;
  final bool reveal;
  final String? id; // for the exit: the tapped tile goes last
  final ScrollController? scroll;
  final double top, bottom;

  @override
  State<Landed> createState() => _LandedState();
}

class _LandedState extends State<Landed> with SingleTickerProviderStateMixin {
  static const _dur = Duration(milliseconds: 460);
  late final _c = AnimationController(vsync: this, duration: _dur, value: 1);
  Timer? _wait;
  bool _inView = true;

  bool get _off => widget.style == 'none' || Perf.lite.value;

  @override
  void initState() {
    super.initState();
    widget.landing.addListener(_sync);
    widget.scroll?.addListener(_scrolled);
    _sync();
    // Built while scrolling (not by a landing): come in now.
    if (widget.reveal && !_off && _c.value >= 1) _c.forward(from: 0);
    if (widget.scroll != null) WidgetsBinding.instance.addPostFrameCallback((_) => _scrolled());
  }

  @override
  void didUpdateWidget(Landed old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll?.removeListener(_scrolled);
      widget.scroll?.addListener(_scrolled);
    }
  }

  /// Out of view → wait hidden; scrolled into view → come in.
  void _scrolled() {
    final sc = widget.scroll;
    if (!mounted || sc == null || !sc.hasClients || _off) return;
    final pos = sc.position;
    final visible = widget.top < pos.pixels + pos.viewportDimension && widget.bottom > pos.pixels;
    if (visible == _inView) return;
    _inView = visible;
    if (visible) {
      _wait?.cancel();
      _c.forward(from: 0);
    } else {
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    widget.landing.removeListener(_sync);
    widget.scroll?.removeListener(_scrolled);
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _sync() {
    _wait?.cancel();
    final l = widget.landing;
    if (l.exiting) {
      if (Perf.lite.value) return;
      // Swing away (turnstile), column by column; the tapped tile last.
      final delay = widget.id != null && widget.id == l.last ? const Duration(milliseconds: 260) : widget.delay * .6;
      _wait = Timer(delay, () {
        if (mounted) _c.animateBack(0, duration: const Duration(milliseconds: 260), curve: Curves.easeIn);
      });
      return;
    }
    if (_off) {
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
      final (Matrix4 m, Alignment at) = switch (widget.landing.exiting ? 'turnstile' : widget.style) {
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
        opacity: widget.style == 'none' && !widget.landing.exiting ? 1 : t.clamp(0, 1),
        child: Transform(transform: m, alignment: at, child: child),
      );
    },
  );
}
