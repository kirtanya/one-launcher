import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ds.dart';

/// Corners: the tile corners in Tiles (Metro), else [classic].
BorderRadius _corners(double classic) => BorderRadius.circular(DS.metro ? DS.metroRadius : classic);

/// Critics' scores, phone and TV alike: the services' own badges (IMDb's yellow pill, Rotten
/// Tomatoes' tomato / splat, Metacritic's score square), built from shapes and text — no logo files.
/// Brand colours stay the same in every look; in Tiles (Metro) only the corners follow the tile
/// setting. Text beside a badge takes the host's ink ([ink] / [muted]).

/// Metacritic's colour for a Metascore: green from 61, yellow 40–60, red below 40.
Color metascoreColour(int score) => score >= 61
    ? const Color(0xFF66CC33)
    : score >= 40
    ? const Color(0xFFFFCC33)
    : const Color(0xFFFF0000);

// ---- Brand colours (the services' own, not themeable) ----
const _imdbYellow = Color(0xFFF5C518);
const _imdbInk = Color(0xFF000000);
const _tomatoRed = Color(0xFFFA320A);
const _tomatoDark = Color(0xFFC21A00);
const _leafGreen = Color(0xFF2E8B2E);
const _splatGreen = Color(0xFF0AC855);

/// "8.8"; whole numbers without the ".0" only where asked ("★ 9").
String scoreLabel(double v, {bool trim = false}) => trim && v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// IMDb's pill: yellow, the black "IMDb" wordmark box, the score in black. [size] = the score's
/// type size (posters 11, a title's page 16).
class ImdbBadge extends StatelessWidget {
  const ImdbBadge(this.score, {super.key, this.size = 11});
  final double score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = size / 11;
    return Semantics(
      label: 'IMDb ${scoreLabel(score)}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(3 * k, 2 * k, 6 * k, 2 * k),
        decoration: BoxDecoration(color: _imdbYellow, borderRadius: _corners(5 * k)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 3.5 * k, vertical: .5 * k),
              decoration: BoxDecoration(color: _imdbInk, borderRadius: _corners(3 * k)),
              // IMDb's wordmark is a heavy condensed face: the bundled variable font (Google Sans Flex)
              // at its heaviest and narrowest.
              child: Text(
                'IMDb',
                style: TextStyle(
                  fontFamily: DS.clockFont,
                  fontSize: size * 1.05,
                  fontWeight: FontWeight.w900,
                  fontVariations: const [FontVariation('wght', 1000), FontVariation('wdth', 25)],
                  height: 1.05,
                  letterSpacing: -.1 * k,
                  color: _imdbYellow,
                ),
              ),
            ),
            SizedBox(width: 5 * k),
            Text(
              scoreLabel(score),
              style: TextStyle(fontFamily: DS.face, fontSize: size, fontWeight: FontWeight.w600, height: 1.15, color: _imdbInk),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rotten Tomatoes: the red tomato (Fresh, 60 % and up) or the green splat (Rotten) + "86%".
class RottenTomatoesBadge extends StatelessWidget {
  const RottenTomatoesBadge(this.percent, {super.key, this.size = 16, this.ink = Colors.white});
  final int percent;
  final double size;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final fresh = percent >= 60;
    return Semantics(
      label: 'Rotten Tomatoes $percent percent, ${fresh ? 'fresh' : 'rotten'}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            key: ValueKey(fresh ? 'rt:fresh' : 'rt:rotten'),
            size: Size.square(size * 1.35),
            painter: _TomatoPainter(fresh: fresh),
          ),
          SizedBox(width: size * .35),
          Text(
            '$percent%',
            style: TextStyle(fontFamily: DS.face, fontSize: size, fontWeight: FontWeight.w600, height: 1.15, color: ink),
          ),
        ],
      ),
    );
  }
}

class _TomatoPainter extends CustomPainter {
  const _TomatoPainter({required this.fresh});
  final bool fresh;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final c = Offset(w / 2, w * .56);
    if (fresh) {
      // The tomato: a red ball lit from the top left…
      final r = w * .42;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.35, -.4),
            colors: const [Color(0xFFFF6B4A), _tomatoRed, _tomatoDark],
            stops: const [0, .55, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      // …and its green star of leaves on top.
      final leaf = Path();
      final top = Offset(w / 2, w * .2);
      for (var i = 0; i < 10; i++) {
        final a = -math.pi / 2 + i * math.pi / 5;
        final rr = i.isEven ? w * .2 : w * .07;
        final p = top + Offset(math.cos(a) * rr * 1.25, math.sin(a) * rr * .7);
        i == 0 ? leaf.moveTo(p.dx, p.dy) : leaf.lineTo(p.dx, p.dy);
      }
      leaf.close();
      canvas.drawPath(leaf, Paint()..color = _leafGreen);
    } else {
      // The splat: a lumpy green blob with a couple of drops.
      final blob = Path();
      const n = 14;
      for (var i = 0; i <= n; i++) {
        final a = i * 2 * math.pi / n;
        final rr = w * (i.isEven ? .42 : .3) * (i % 3 == 0 ? .9 : 1);
        final p = c + Offset(math.cos(a) * rr, math.sin(a) * rr * .9);
        i == 0 ? blob.moveTo(p.dx, p.dy) : blob.lineTo(p.dx, p.dy);
      }
      blob.close();
      final paint = Paint()..color = _splatGreen;
      canvas.drawPath(blob, paint);
      canvas.drawCircle(c + Offset(w * .44, -w * .36), w * .06, paint);
      canvas.drawCircle(c + Offset(-w * .44, w * .34), w * .05, paint);
    }
  }

  @override
  bool shouldRepaint(_TomatoPainter old) => old.fresh != fresh;
}

/// Metacritic: the score on its colour square (green 61+, yellow 40–60, red below) + "Metascore".
class MetacriticBadge extends StatelessWidget {
  const MetacriticBadge(this.score, {super.key, this.size = 16, this.muted = const Color(0x99FFFFFF)});
  final int score;
  final double size;
  final Color muted; // the "Metascore" label

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Metascore $score',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('mc:square'),
          width: size * 2,
          height: size * 1.8,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: metascoreColour(score), borderRadius: _corners(3)),
          child: Text(
            '$score',
            style: TextStyle(fontFamily: DS.face, fontSize: size * .95, fontWeight: FontWeight.w600, height: 1, color: Colors.white),
          ),
        ),
        SizedBox(width: size * .45),
        Text(
          'Metascore',
          style: TextStyle(fontFamily: DS.face, fontSize: size * .8, fontWeight: FontWeight.w500, color: muted),
        ),
      ],
    ),
  );
}

/// "12 Mar 2024".
String reviewDate(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';

/// A reviewer's own score: "★ 9" on IMDb yellow.
class ReviewScore extends StatelessWidget {
  const ReviewScore(this.rating, {super.key, this.size = 11});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: size * .55, vertical: size * .1),
    decoration: BoxDecoration(color: _imdbYellow, borderRadius: _corners(4)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size * 1.15, color: _imdbInk),
        SizedBox(width: size * .15),
        Text(
          scoreLabel(rating, trim: true),
          style: TextStyle(fontFamily: DS.face, fontSize: size, fontWeight: FontWeight.w600, height: 1.3, color: _imdbInk),
        ),
      ],
    ),
  );
}
