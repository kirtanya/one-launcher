import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tactile.dart';

/// Tactile's parts (docs/TACTILE_LANGUAGE.md §7). Each is a mechanism: it has a depth, moves the
/// way the real thing would, and gives its feel (TactileFeel) at the moment of contact.

/// A plate (level +1, ref 2): a big moulded slab with a lit top edge and a large soft shadow.
class TPlate extends StatelessWidget {
  const TPlate({super.key, required this.child, this.radius = 24, this.padding = EdgeInsets.zero, this.color, this.onTap, this.onLongPress});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: Tactile.rim, width: .6),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: Tactile.plateShadow,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color ?? Tactile.plate, Colors.white, Tactile.dark ? .03 : .35)!, color ?? Tactile.plate],
          stops: const [0, .08], // the chamfer catching the light
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          splashFactory: NoSplash.splashFactory, // hardware doesn't ripple; it presses
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A recess in the panel (level −2): wells, screens, tracks, trays.
class TWell extends StatelessWidget {
  const TWell({super.key, required this.child, this.radius = 16, this.padding = EdgeInsets.zero, this.floor, this.depth = 2});
  final Widget child;
  final double radius, depth;
  final EdgeInsetsGeometry padding;
  final Color? floor;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: WellPainter(radius: radius, floor: floor ?? Tactile.well, depth: depth),
    child: Padding(padding: padding, child: child),
  );
}

/// A tray (ref 1): a recessed housing holding a row of keys, 4 dp gutters.
class TTray extends StatelessWidget {
  const TTray({super.key, required this.children, this.radius = 16});
  final List<Widget> children;
  final double radius;

  @override
  Widget build(BuildContext context) => TWell(
    radius: radius,
    padding: const EdgeInsets.all(4),
    depth: 2.5,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(width: 4), c],
      ],
    ),
  );
}

/// An LED (refs 1, 3): dark glass when off; lit, it glows with a bloom and a specular pip.
class TLed extends StatelessWidget {
  const TLed({super.key, required this.on, this.color, this.size = 7});
  final bool on;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Tactile.light;
    return AnimatedContainer(
      duration: Duration(milliseconds: on ? 120 : 220), // lights fast, cools slower
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? c : Tactile.ledOff,
        boxShadow: on
            ? [BoxShadow(color: c.withValues(alpha: .65), blurRadius: size * 1.2, spreadRadius: size * .1)]
            : [BoxShadow(color: Tactile.highlight, offset: const Offset(0, .6), blurRadius: 0)],
      ),
      alignment: const Alignment(-.3, -.4),
      child: on
          ? Container(
              width: size * .32,
              height: size * .32,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xCCFFFFFF)),
            )
          : null,
    );
  }
}

/// A key (ref 1): a moulded cap that travels down 2 dp the moment it's touched (with the feel),
/// springs back on release, and fires on release like a real switch. [latched] keeps it down
/// with its [led] lit (the current tab). [tint]: a coloured cap (still shaded like plastic).
class TKey extends StatefulWidget {
  const TKey({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.latched = false,
    this.led = false,
    this.width = 48,
    this.height = 48,
    this.radius = 12,
    this.tint,
    this.tooltip,
  });
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final bool latched, led;
  final double? width; // null: as wide as its child
  final double height, radius;
  final Color? tint;
  final String? tooltip;

  @override
  State<TKey> createState() => _TKeyState();
}

class _TKeyState extends State<TKey> {
  bool _down = false;

  void _press(bool down) {
    if (down == _down || widget.onTap == null) return;
    setState(() => _down = down);
    down ? TactileFeel.press() : TactileFeel.release();
  }

  @override
  Widget build(BuildContext context) {
    final sunk = _down || widget.latched;
    final travel = _down ? 2.0 : (widget.latched ? 1.5 : 0.0);
    final key = Listener(
      onPointerDown: (_) => _press(true),
      onPointerUp: (_) => _press(false),
      onPointerCancel: (_) => _press(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _down ? 60 : 140),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          width: widget.width,
          height: widget.height,
          transform: Matrix4.translationValues(0, travel, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: Tactile.capFace(widget.tint),
            border: Border.all(color: Tactile.rim, width: .6),
            boxShadow: Tactile.raised(pressed: sunk),
          ),
          foregroundDecoration: sunk
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius),
                  // Pressed: a little darker, the top lip shading the face.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: Tactile.dark ? .25 : .08), Colors.transparent],
                    stops: const [0, .35],
                  ),
                )
              : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              widget.child,
              if (widget.led)
                Positioned(top: 6, right: 6, child: TLed(on: widget.led, size: 6)),
            ],
          ),
        ),
      ),
    );
    return widget.tooltip == null ? key : Tooltip(message: widget.tooltip!, child: key);
  }
}

/// The switch (ref 4): a debossed well with a soft thumb that follows the finger, snaps to the
/// nearer end past halfway and lands against the wall with a latch; a tick as it crosses the
/// middle. Tap flips it. On, the well glows faintly in the theme's light.
class TSwitch extends StatefulWidget {
  const TSwitch({super.key, required this.value, required this.onChanged, this.width = 58, this.height = 32});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width, height;

  @override
  State<TSwitch> createState() => _TSwitchState();
}

class _TSwitchState extends State<TSwitch> {
  double? _drag; // thumb position 0–1 while dragging
  bool _past = false;

  double get _thumb => widget.height - 6;
  double get _travel => widget.width - _thumb - 6;

  void _land(bool v) {
    setState(() => _drag = null);
    TactileFeel.latch();
    if (v != widget.value) widget.onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final p = _drag ?? (widget.value ? 1.0 : 0.0);
    final on = p > .5;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onChanged == null ? null : () => _land(!widget.value),
      onHorizontalDragStart: widget.onChanged == null
          ? null
          : (_) {
              setState(() => _drag = widget.value ? 1 : 0);
              _past = widget.value;
              TactileFeel.tick();
            },
      onHorizontalDragUpdate: widget.onChanged == null
          ? null
          : (d) {
              // A little give past the ends, like a rubber stop.
              final next = ((_drag ?? 0) + d.delta.dx / _travel).clamp(-.06, 1.06);
              if ((next > .5) != _past) {
                _past = next > .5;
                TactileFeel.tick();
              }
              setState(() => _drag = next);
            },
      onHorizontalDragEnd: widget.onChanged == null ? null : (_) => _land((_drag ?? 0) > .5),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: on ? Color.lerp(Tactile.well, Tactile.light, Tactile.dark ? .28 : .22) : Tactile.well),
                duration: const Duration(milliseconds: 180),
                builder: (context, c, _) => CustomPaint(painter: WellPainter(radius: widget.height / 2, floor: c!, depth: 2.4)),
              ),
            ),
            AnimatedPositioned(
              duration: _drag == null ? const Duration(milliseconds: 240) : Duration.zero,
              curve: const Cubic(.3, 1.4, .5, 1), // lands with a little bounce off the wall
              left: 3 + p.clamp(0.0, 1.0) * _travel,
              top: 3,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 90),
                scale: _drag != null && (p < 0 || p > 1) ? .96 : 1, // pressed against a stop
                child: Container(
                  width: _thumb,
                  height: _thumb,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_thumb * .38),
                    gradient: Tactile.capFace(),
                    border: Border.all(color: Tactile.rim, width: .6),
                    boxShadow: Tactile.raised(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A backlit screen in a well (ref 2): readouts, the clock, the search field. A faint pixel grid
/// over the glass.
class TLcd extends StatelessWidget {
  const TLcd({super.key, required this.child, this.radius = 14, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12)});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  static Color get glass => Tactile.dark ? Color.lerp(const Color(0xFF0E1714), Tactile.light, .06)! : Color.lerp(const Color(0xFFC9D3C9), Tactile.light, .12)!;
  static Color get text => Tactile.dark ? Color.lerp(Tactile.light, Colors.white, .25)! : const Color(0xFF1D2A1F);

  @override
  Widget build(BuildContext context) => TWell(
    radius: radius,
    floor: glass,
    depth: 3,
    child: CustomPaint(
      foregroundPainter: _PixelGrid(),
      child: Padding(
        padding: padding,
        child: DefaultTextStyle.merge(style: TextStyle(color: text), child: child),
      ),
    ),
  );
}

class _PixelGrid extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: .05);
    for (var y = 1.5; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_PixelGrid old) => false;
}

/// A dot-matrix readout (refs 2, 3): 5×7 dots per character, lit ones in the screen's ink with a
/// faint glow, unlit ones as ghost dots — like a real LED / LCD matrix. Digits, A–Z and a few
/// marks; anything else is a gap. [dot] is the dot pitch in dp.
class DotMatrix extends StatelessWidget {
  const DotMatrix(this.text, {super.key, this.dot = 4, this.color, this.ghost = true, this.gap = 1});
  final String text;
  final double dot;
  final Color? color;
  final bool ghost;
  final int gap; // dot columns between characters

  /// The width [text] takes, in dp.
  static double widthOf(String text, double dot, {int gap = 1}) => text.isEmpty ? 0 : (text.length * (5 + gap) - gap) * dot;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? Tactile.ink;
    return CustomPaint(
      size: Size(widthOf(text, dot, gap: gap), dot * 7),
      painter: _DotMatrixPainter(text.toUpperCase(), dot, c, ghost, gap),
    );
  }
}

class _DotMatrixPainter extends CustomPainter {
  _DotMatrixPainter(this.text, this.dot, this.color, this.ghost, this.gap);
  final String text;
  final double dot;
  final Color color;
  final bool ghost;
  final int gap;

  // 5×7 glyphs, one string of 7 rows × 5 columns ('#' lit).
  static const _glyphs = <String, String>{
    '0': ' ### #   ##  ### # ###  ##   # ### ', '1': '  #   ##    #    #    #    #   ### ', '2': ' ### #   #    #   #   #   #   #####',
    '3': '#####   #   #     #     ##   # ### ', '4': '   #   ##  # # #  # #####   #    # ', '5': '######    ####     #    ##   # ### ',
    '6': '  ##  #   #    #### #   ##   # ### ', '7': '#####    #   #   #   #    #    #   ', '8': ' ### #   ##   # ### #   ##   # ### ',
    '9': ' ### #   ##   # ####    #   #  ##  ', ':': '      ##   ##        ##   ##       ', ' ': '                                   ',
    ',': '                     ##   ##   #   ', '.': '                          ##   ##  ', '-': '               #####               ',
    '%': '##   ##  #   #   #   #   #  ##   ##', '/': '         #   #   #   #   #         ', '?': ' ### #   #    #   #   #         #  ',
    'A': ' ### #   ##   #######   ##   ##   #', 'B': '#### #   ##   ##### #   ##   ##### ', 'C': ' ### #   ##    #    #    #   # ### ',
    'D': '#### #   ##   ##   ##   ##   ##### ', 'E': '######    #    #### #    #    #####', 'F': '######    #    #### #    #    #    ',
    'G': ' ### #   ##    # ####   ##   # ####', 'H': '#   ##   ##   #######   ##   ##   #', 'I': ' ###   #    #    #    #    #   ### ',
    'J': '  ###   #    #    #    # #  #  ##  ', 'K': '#   ##  # # #  ##   # #  #  # #   #', 'L': '#    #    #    #    #    #    #####',
    'M': '#   ### ### # ## # ##   ##   ##   #', 'N': '#   ##   ###  ## # ##  ###   ##   #', 'O': ' ### #   ##   ##   ##   ##   # ### ',
    'P': '#### #   ##   ##### #    #    #    ', 'Q': ' ### #   ##   ##   ## # ##  #  ## #', 'R': '#### #   ##   ##### # #  #  # #   #',
    'S': ' #####    #     ###     #    ##### ', 'T': '#####  #    #    #    #    #    #  ', 'U': '#   ##   ##   ##   ##   ##   # ### ',
    'V': '#   ##   ##   ##   ##   # # #   #  ', 'W': '#   ##   ##   ## # ## # ## # # # # ', 'X': '#   ##   # # #   #   # # #   ##   #',
    'Y': '#   ##   # # #   #    #    #    #  ', 'Z': '#####    #   #   #   #   #    #####',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final r = dot * .38;
    final lit = Paint()..color = color;
    final glow = Paint()
      ..color = color.withValues(alpha: .35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, dot * .45);
    final off = Paint()..color = color.withValues(alpha: .07);
    for (var i = 0; i < text.length; i++) {
      final g = (_glyphs[text[i]] ?? _glyphs[' ']!).padRight(35);
      final x0 = i * (5 + gap) * dot;
      for (var row = 0; row < 7; row++) {
        for (var col = 0; col < 5; col++) {
          final on = g[row * 5 + col] == '#';
          final c = Offset(x0 + (col + .5) * dot, (row + .5) * dot);
          if (on) {
            canvas.drawCircle(c, r * 1.4, glow);
            canvas.drawCircle(c, r, lit);
          } else if (ghost) {
            canvas.drawCircle(c, r, off);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DotMatrixPainter old) => old.text != text || old.color != color || old.dot != dot;
}

/// A knob (refs 1–3): a bezel ring, a domed cap, a lit pointer, a dotted scale over a 270° sweep.
/// Turn it by dragging up/down (or around); it moves in [steps] detents, ticking at each and
/// clicking harder at the ends. [value] is 0–1.
class TKnob extends StatefulWidget {
  const TKnob({super.key, required this.value, required this.onChanged, this.steps = 10, this.size = 76});
  final double value;
  final ValueChanged<double> onChanged;
  final int steps;
  final double size;

  @override
  State<TKnob> createState() => _TKnobState();
}

class _TKnobState extends State<TKnob> {
  double _start = 0, _y0 = 0;

  int get _step => (widget.value * widget.steps).round();

  void _to(int step) {
    final s = step.clamp(0, widget.steps);
    if (s == _step) return;
    (s == 0 || s == widget.steps) ? TactileFeel.latch() : TactileFeel.tick();
    widget.onChanged(s / widget.steps);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final angle = (-135 + 270 * widget.value) * 3.14159265 / 180;
    return GestureDetector(
      onVerticalDragStart: (d) {
        _start = widget.value;
        _y0 = d.globalPosition.dy;
        TactileFeel.tick();
      },
      // A full turn of the range for ~2.4 knob heights of drag.
      onVerticalDragUpdate: (d) => _to(((_start + (_y0 - d.globalPosition.dy) / (size * 2.4)) * widget.steps).round()),
      onTapUp: (d) => _to(_step + (d.localPosition.dx > size / 2 ? 1 : -1)), // tap a side: one step that way
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _KnobScale(widget.steps, widget.value),
          child: Padding(
            padding: EdgeInsets.all(size * .13),
            child: DecoratedBox(
              // Bezel: a lip around the hole the cap sits in (dark at the top, lit at the bottom).
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tactile.shade, Tactile.highlight]),
              ),
              child: Padding(
                padding: EdgeInsets.all(size * .045),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(center: const Alignment(-.3, -.5), radius: .9, colors: [Tactile.capTop, Tactile.capBottom]),
                    boxShadow: Tactile.proud,
                  ),
                  child: Transform.rotate(
                    angle: angle,
                    child: Align(
                      alignment: const Alignment(0, -.78),
                      child: Container(
                        width: size * .05,
                        height: size * .17,
                        decoration: BoxDecoration(
                          color: Tactile.light,
                          borderRadius: BorderRadius.circular(size),
                          boxShadow: [BoxShadow(color: Tactile.light.withValues(alpha: .6), blurRadius: 5)],
                        ),
                      ),
                    ),
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

class _KnobScale extends CustomPainter {
  _KnobScale(this.steps, this.value);
  final int steps;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    for (var i = 0; i <= steps; i++) {
      final a = (-135 + 270 * i / steps - 90) * 3.14159265 / 180;
      final on = i / steps <= value + 1e-6;
      canvas.drawCircle(
        c + Offset(r * _cos(a), r * _sin(a)),
        i == 0 || i == steps ? 1.9 : 1.3,
        Paint()..color = on ? Tactile.ink.withValues(alpha: .75) : Tactile.ink.withValues(alpha: .25),
      );
    }
  }

  static double _cos(double a) => _sinCos(a, true);
  static double _sin(double a) => _sinCos(a, false);
  static double _sinCos(double a, bool cos) => cos ? math.cos(a) : math.sin(a);

  @override
  bool shouldRepaint(_KnobScale old) => old.value != value || old.steps != steps;
}

/// A knob setting in a row: title and the value as a dot-matrix readout on the left, the knob
/// on the right.
class TKnobRow extends StatelessWidget {
  const TKnobRow({super.key, required this.title, required this.readout, required this.value, required this.steps, required this.onChanged});
  final String title, readout;
  final double value;
  final int steps;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.3, color: Tactile.inkMuted)),
              const SizedBox(height: 10),
              TLcd(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                radius: 10,
                child: DotMatrix(readout, dot: 2.6, color: TLcd.text),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        TKnob(value: value, steps: steps, onChanged: onChanged),
      ],
    ),
  );
}

/// Every slider in the third view as a fader (ref 2): an inset groove and a moulded pill cap with
/// a printed line. Applied through the app's SliderTheme, so existing sliders change in place.
SliderThemeData tactileSliderTheme() => SliderThemeData(
  trackHeight: 6,
  trackShape: const _GrooveTrack(),
  thumbShape: const _FaderCap(),
  overlayShape: SliderComponentShape.noOverlay,
  tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1.2),
  activeTickMarkColor: Tactile.ink.withValues(alpha: .35),
  inactiveTickMarkColor: Tactile.ink.withValues(alpha: .25),
  showValueIndicator: ShowValueIndicator.never,
);

class _GrooveTrack extends SliderTrackShape with BaseSliderTrackShape {
  const _GrooveTrack();

  @override
  void paint(PaintingContext context, Offset offset,
      {required RenderBox parentBox, required SliderThemeData sliderTheme, required Animation<double> enableAnimation, required Offset thumbCenter,
      Offset? secondaryOffset, bool isEnabled = false, bool isDiscrete = false, required TextDirection textDirection}) {
    final rect = getPreferredRect(parentBox: parentBox, offset: offset, sliderTheme: sliderTheme, isEnabled: isEnabled, isDiscrete: isDiscrete);
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(rect.left, rect.top);
    WellPainter(radius: rect.height / 2, floor: Tactile.dark ? const Color(0xFF151417) : const Color(0xFFCDD0D4), depth: 1.2).paint(canvas, rect.size);
    canvas.restore();
    // The lit part of the groove, up to the cap: the theme's light, faintly.
    final lit = RRect.fromLTRBR(rect.left + 1, rect.top + 1, thumbCenter.dx, rect.bottom - 1, Radius.circular(rect.height / 2));
    canvas.drawRRect(lit, Paint()..color = Tactile.light.withValues(alpha: .45));
  }
}

class _FaderCap extends SliderComponentShape {
  const _FaderCap();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(34, 22);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation, required Animation<double> enableAnimation, required bool isDiscrete, required TextPainter labelPainter,
      required RenderBox parentBox, required SliderThemeData sliderTheme, required TextDirection textDirection, required double value, required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final canvas = context.canvas;
    final pressed = activationAnimation.value;
    final rect = Rect.fromCenter(center: center + Offset(0, pressed * 1), width: 34, height: 22);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(11));
    for (final s in Tactile.raised(pressed: pressed > .5)) {
      canvas.drawRRect(rr.shift(s.offset), Paint()
        ..color = s.color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma));
    }
    canvas.drawRRect(rr, Paint()..shader = Tactile.capFace().createShader(rect));
    canvas.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = Tactile.rim);
    // The printed grip line.
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: rect.center, width: 2, height: 10), const Radius.circular(1)), Paint()..color = Tactile.ink.withValues(alpha: .7));
  }
}
