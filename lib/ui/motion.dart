import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'perf.dart';

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

  // One simulation per (ratio, stiffness), built once — not on every frame of every animation.
  static final _sims = <(double, double), SpringSimulation>{};

  @override
  double transformInternal(double t) {
    final sim = _sims.putIfAbsent((
      ratio,
      stiffness,
    ), () => SpringSimulation(SpringDescription.withDampingRatio(mass: 1, stiffness: stiffness, ratio: ratio), 0, 1, 0));
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

/// Grows + slides a child in with a spring (no fade — see build), `delay` (0..0.6) staggers siblings.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.delay = 0, this.offset = const Offset(0, 12), this.fromScale = 0.6});
  final Widget child;
  final double delay;
  final Offset offset;
  final double fromScale;

  @override
  Widget build(BuildContext context) {
    if (Perf.lite.value) return child; // lighter effects: no pop-in
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.popDuration,
      curve: Interval(delay.clamp(0, .6), 1, curve: Motion.pop),
      child: child,
      // Scale + slide only, no fade: a fade is an offscreen layer per item, and dozens of
      // icons popping at once made folder opening stutter on slower phones.
      builder: (context, t, child) => Transform.translate(
        offset: offset * (1 - t),
        child: Transform.scale(scale: fromScale + (1 - fromScale) * t, child: child),
      ),
    );
  }
}

/// Scales its child with how much of it is inside the nearest scroll view's visible area:
/// items grow 0→100% as they scroll into view and shrink back as they leave (both axes).
/// Done at paint time (no rebuilds), so it costs almost nothing while scrolling.
class EdgeScale extends SingleChildRenderObjectWidget {
  const EdgeScale({super.key, required Widget super.child, this.minScale = 0, this.startInset = 0, this.endInset = 0});

  /// Smallest scale at the very edge (0 for app icons; cards use more so they don't vanish).
  final double minScale;

  /// Parts of the viewport that count as out of view (e.g. under a pinned header or a
  /// floating search bar), in logical pixels from the start / end edge.
  final double startInset, endInset;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderEdgeScale(Scrollable.maybeOf(context)?.position)
    ..minScale = minScale
    ..startInset = startInset
    ..endInset = endInset;

  @override
  void updateRenderObject(BuildContext context, RenderEdgeScale renderObject) => renderObject
    ..position = Scrollable.maybeOf(context)?.position
    ..minScale = minScale
    ..startInset = startInset
    ..endInset = endInset;
}

/// Render side of [EdgeScale].
class RenderEdgeScale extends RenderProxyBox {
  RenderEdgeScale(this._position);

  double minScale = 0, startInset = 0, endInset = 0;

  ScrollPosition? _position;
  set position(ScrollPosition? p) {
    if (p == _position) return;
    if (attached) _position?.removeListener(markNeedsPaint);
    _position = p;
    if (attached) _position?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position?.addListener(markNeedsPaint); // repaint as the scroll view moves
  }

  @override
  void detach() {
    _position?.removeListener(markNeedsPaint);
    super.detach();
  }

  /// 0…1: share of this item (along the scroll axis) that's inside the viewport.
  double get visibleFraction => _visible();

  double _visible() {
    final pos = _position;
    final vp = RenderAbstractViewport.maybeOf(this);
    if (pos == null || vp is! RenderBox || !hasSize || !(vp as RenderBox).hasSize) return 1;
    final rect = MatrixUtils.transformRect(getTransformTo(vp as RenderObject), Offset.zero & size);
    final horizontal = pos.axis == Axis.horizontal;
    final start = horizontal ? rect.left : rect.top, end = horizontal ? rect.right : rect.bottom;
    final extent = horizontal ? (vp as RenderBox).size.width : (vp as RenderBox).size.height;
    final len = end - start;
    if (len <= 0) return 1;
    final lo = startInset, hi = extent - endInset;
    if (hi <= lo) return 1;
    return ((end.clamp(lo, hi) - start.clamp(lo, hi)) / len).clamp(0.0, 1.0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (Perf.lite.value) return super.paint(context, offset); // lighter effects: no edge scaling
    final v = minScale + (1 - minScale) * Curves.easeOut.transform(_visible());
    if (v >= .999) return super.paint(context, offset);
    if (v <= .001 || child == null) return;
    final c = offset + size.center(Offset.zero);
    final m = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(v, v, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
    layer = context.pushTransform(needsCompositing, Offset.zero, m, (ctx, o) => ctx.paintChild(child!, offset + o), oldLayer: layer as TransformLayer?);
  }
}
