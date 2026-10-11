import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Snapping motion for One Launcher: everything settles on a spring, not a plain ease.
class Motion {
  /// Page swipe spring: stiff and slightly under-damped, so it lands with a crisp snap.
  static final page = SpringDescription.withDampingRatio(mass: 1, stiffness: 520, ratio: 0.86);

  /// Snappier spring for small things (buttons, pills, icons).
  static final small = SpringDescription.withDampingRatio(mass: 1, stiffness: 700, ratio: 0.62);

  /// Folder open/close and content swaps.
  static const snap = SpringCurve(ratio: 0.72);
  static const snapDuration = Duration(milliseconds: 460);

  /// Critically damped: snaps into place without overshooting (for things that must stay in bounds).
  static const settle = SpringCurve(ratio: 1, stiffness: 220);

  /// Pop-in for icons: a little overshoot.
  static const pop = SpringCurve(ratio: 0.55);
  static const popDuration = Duration(milliseconds: 520);

  static const pressIn = Duration(milliseconds: 90);
}

/// A spring as a Curve, so implicit animations (AnimatedSize, AnimatedRotation…) can snap.
class SpringCurve extends Curve {
  const SpringCurve({this.ratio = 0.7, this.stiffness = 180});
  final double ratio;
  final double stiffness;

  @override
  double transformInternal(double t) {
    final sim = SpringSimulation(SpringDescription.withDampingRatio(mass: 1, stiffness: stiffness, ratio: ratio), 0, 1, 0);
    // The curve's 0..1 time maps to the first second of the spring, which has settled by then.
    return sim.x(t);
  }
}

/// Squishes slightly on press and springs back on release. Wrap any tappable.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.scale = 0.96, this.enabled = true});
  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: 1);

  void _to(double target, {bool spring = false}) {
    if (spring) {
      _c.animateWith(SpringSimulation(Motion.small, _c.value, target, _c.velocity));
    } else {
      _c.animateTo(target, duration: Motion.pressIn, curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (_) => _to(widget.scale),
      onPointerUp: (_) => _to(1, spring: true),
      onPointerCancel: (_) => _to(1, spring: true),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Transform.scale(scale: _c.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// Fades + slides a child in with a spring, `delay` (0..0.6) staggers siblings.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.delay = 0, this.offset = const Offset(0, 12), this.fromScale = 0.86});
  final Widget child;
  final double delay;
  final Offset offset;
  final double fromScale;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.popDuration,
      curve: Interval(delay.clamp(0, .6), 1, curve: Motion.pop),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: offset * (1 - t),
          child: Transform.scale(scale: fromScale + (1 - fromScale) * t, child: child),
        ),
      ),
    );
  }
}
