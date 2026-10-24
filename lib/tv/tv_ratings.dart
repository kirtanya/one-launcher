import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/ds.dart';
import '../ui/motion.dart';
import 'catalog.dart';
import 'ratings.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';
import 'tv_metro.dart';
import 'tv_parts.dart';
import 'tv_title.dart' show ShowImage;

/// Critics' scores and reviews on TV: the services' own badges (IMDb's yellow pill, Rotten
/// Tomatoes' tomato / splat, Metacritic's score square), built from shapes and text — no logo files.
/// Brand colours stay the same in every look; in Tiles only the corners follow the tile setting.

// ---- Brand colours (the services' own, not themeable) ----
const _imdbYellow = Color(0xFFF5C518);
const _imdbInk = Color(0xFF000000);
const _tomatoRed = Color(0xFFFA320A);
const _tomatoDark = Color(0xFFC21A00);
const _leafGreen = Color(0xFF2E8B2E);
const _splatGreen = Color(0xFF0AC855);

/// "8.8"; whole numbers without the ".0" only where asked ("★ 9").
String _score(double v, {bool trim = false}) => trim && v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

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
      label: 'IMDb ${_score(score)}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(3 * k, 2 * k, 6 * k, 2 * k),
        decoration: BoxDecoration(color: _imdbYellow, borderRadius: TvMetro.corners(5 * k)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 3.5 * k, vertical: .5 * k),
              decoration: BoxDecoration(color: _imdbInk, borderRadius: TvMetro.corners(3 * k)),
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
              _score(score),
              style: TextStyle(fontFamily: DS.font, fontSize: size, fontWeight: FontWeight.w600, height: 1.15, color: _imdbInk),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rotten Tomatoes: the red tomato (Fresh, 60 % and up) or the green splat (Rotten) + "86%".
class RottenTomatoesBadge extends StatelessWidget {
  const RottenTomatoesBadge(this.percent, {super.key, this.size = 16});
  final int percent;
  final double size;

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
            style: TextStyle(fontFamily: DS.font, fontSize: size, fontWeight: FontWeight.w600, height: 1.15, color: TvDS.ink),
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
  const MetacriticBadge(this.score, {super.key, this.size = 16});
  final int score;
  final double size;

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
          decoration: BoxDecoration(color: metascoreColour(score), borderRadius: TvMetro.corners(3)),
          child: Text(
            '$score',
            style: TextStyle(fontFamily: DS.font, fontSize: size * .95, fontWeight: FontWeight.w600, height: 1, color: Colors.white),
          ),
        ),
        SizedBox(width: size * .45),
        Text(
          'Metascore',
          style: TextStyle(fontFamily: DS.font, fontSize: size * .8, fontWeight: FontWeight.w500, color: TvDS.inkMuted),
        ),
      ],
    ),
  );
}

/// The scores in a row, only the ones there are (series usually have IMDb's alone).
class RatingsRow extends StatelessWidget {
  const RatingsRow({super.key, this.imdb, this.ratings, this.trailing = const []});
  final double? imdb; // the catalog's; OMDb's when the catalog has none
  final TitleRatings? ratings;
  final List<Widget> trailing; // e.g. the series' status

  @override
  Widget build(BuildContext context) {
    final i = imdb ?? ratings?.imdb;
    final rt = ratings?.rottenTomatoes, mc = ratings?.metascore;
    return Wrap(
      spacing: DS.s16,
      runSpacing: DS.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [if (i != null) ImdbBadge(i, size: 16), if (rt != null) RottenTomatoesBadge(rt), if (mc != null) MetacriticBadge(mc), ...trailing],
    );
  }
}

// ---- Reviews -----------------------------------------------------------------------

/// "12 Mar 2024".
String reviewDate(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, {this.size = 24});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    // Tiles: a square; else a disc.
    decoration: TvMetro.on
        ? BoxDecoration(color: TvMetro.tileFill, borderRadius: TvMetro.corners(0))
        : BoxDecoration(shape: BoxShape.circle, color: tvTint(name)),
    child: Text(
      name.characters.firstOrNull?.toUpperCase() ?? '?',
      style: TextStyle(fontFamily: DS.font, fontSize: size * .48, fontWeight: FontWeight.w600, color: Colors.white),
    ),
  );
}

class _ReviewScore extends StatelessWidget {
  const _ReviewScore(this.rating, {this.size = 11});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: size * .55, vertical: size * .1),
    decoration: BoxDecoration(color: _imdbYellow, borderRadius: TvMetro.corners(4)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size * 1.15, color: _imdbInk),
        SizedBox(width: size * .15),
        Text(
          _score(rating, trim: true),
          style: TextStyle(fontFamily: DS.font, fontSize: size, fontWeight: FontWeight.w600, height: 1.3, color: _imdbInk),
        ),
      ],
    ),
  );
}

/// One review in the row: who, their score, the first few lines. OK opens it whole.
class TvReviewCard extends StatelessWidget {
  const TvReviewCard({super.key, required this.review, required this.onSelect, this.focusNode, this.onFocus});
  final ShowReview review;
  final VoidCallback onSelect;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;

  static const w = 280.0, h = 136.0;

  @override
  Widget build(BuildContext context) {
    final r = review;
    return Semantics(
      button: true,
      label: 'Review by ${r.author}',
      child: TvFocusable(
        focusNode: focusNode,
        onFocus: onFocus,
        onSelect: onSelect,
        builder: (context, f) => AnimatedScale(
          scale: f ? 1.04 : 1,
          duration: Motion.popDuration,
          curve: Motion.pop,
          child: AnimatedContainer(
            duration: Motion.pressIn * 2,
            width: w,
            height: h,
            padding: const EdgeInsets.fromLTRB(DS.s16, DS.s12, DS.s16, DS.s12),
            decoration: BoxDecoration(
              color: f && !TvMetro.on ? const Color(0x24FFFFFF) : TvDS.surface,
              borderRadius: TvMetro.corners(TvDS.rTile - 2),
              boxShadow: TvMetro.on ? TvMetro.glow(f) : (f ? const [BoxShadow(color: TvDS.glow, blurRadius: 22)] : null),
            ),
            // Focus: a white ring (Tiles: the Metro frame).
            foregroundDecoration: TvMetro.on
                ? TvMetro.frame(f, width: TvDS.focusRing)
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(TvDS.rTile - 2),
                    border: Border.all(color: f ? TvDS.surfaceFocused : Colors.transparent, width: TvDS.focusRing),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Avatar(r.author),
                    const SizedBox(width: DS.s8),
                    Expanded(
                      child: Text(
                        r.author,
                        style: TvDS.tileName.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (r.rating != null) ...[const SizedBox(width: DS.s8), _ReviewScore(r.rating!)],
                  ],
                ),
                const SizedBox(height: DS.s8),
                Expanded(
                  child: Text(
                    r.text.replaceAll(RegExp(r'\s*\n+\s*'), ' '),
                    style: TvDS.tileName.copyWith(fontWeight: FontWeight.w400, height: 1.35, color: f ? TvDS.ink : TvDS.inkMuted),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A review, whole: who, score, date, then the text — ↑ / ↓ scroll it, Back closes.
class TvReviewPage extends StatefulWidget {
  const TvReviewPage({super.key, required this.review, required this.title});
  final ShowReview review;
  final String title; // the show / film it's about

  @override
  State<TvReviewPage> createState() => _TvReviewPageState();
}

class _TvReviewPageState extends State<TvReviewPage> {
  final _scroll = ScrollController();
  static const _step = 140.0; // one press of ↑ / ↓

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final dir = TvFocusable.direction(e.logicalKey);
    if (dir == null || !_scroll.hasClients) return KeyEventResult.ignored;
    final p = _scroll.position;
    final by = switch (dir) {
      AxisDirection.down => _step,
      AxisDirection.up => -_step,
      _ => 0.0,
    };
    if (by != 0) {
      _scroll.animateTo((p.pixels + by).clamp(0, p.maxScrollExtent), duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
    return KeyEventResult.handled; // nothing else on the page to move to
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    return Scaffold(
      backgroundColor: TvDS.canvas,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Padding(
          padding: EdgeInsets.fromLTRB(TvDS.safe.left + 72, 44, TvDS.safe.right + 72, TvDS.safe.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TvMetro.on
                  ? Text(TvMetro.cased('Review · ${widget.title}'), style: TvMetro.header.copyWith(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)
                  : Text('REVIEW · ${widget.title.toUpperCase()}', style: TvDS.heroEyebrow, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: DS.s16),
              Row(
                children: [
                  _Avatar(r.author, size: 40),
                  const SizedBox(width: DS.s12),
                  Flexible(
                    child: Text(r.author, style: TvMetro.on ? TvMetro.title(size: 26) : TvDS.panelTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (r.rating != null) ...[const SizedBox(width: DS.s12), _ReviewScore(r.rating!, size: 14)],
                  if (r.created != null) ...[const SizedBox(width: DS.s12), Text(reviewDate(r.created!), style: TvDS.heroMeta.copyWith(color: TvDS.inkMuted))],
                ],
              ),
              const SizedBox(height: DS.s20),
              Expanded(
                child: ShaderMask(
                  // The text fades out at the bottom edge while there's more below.
                  shaderCallback: (b) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0, .9, 1],
                  ).createShader(b),
                  blendMode: BlendMode.dstIn,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: DS.s32),
                    child: Text(r.text, style: TvDS.heroBody.copyWith(fontSize: 18, height: 1.55, color: TvDS.ink)),
                  ),
                ),
              ),
              const SizedBox(height: DS.s8),
              Text(TvMetro.cased('↑ ↓ to scroll · Back to close'), style: TvDS.keycap.copyWith(color: TvDS.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Seasons & episodes --------------------------------------------------------------

/// "Season 2": a tab over the episode row. OK shows that season; the chosen one stays marked.
class TvSeasonTab extends StatelessWidget {
  const TvSeasonTab({super.key, required this.label, required this.selected, required this.onSelect, this.focusNode});
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: TvFocusable(
      focusNode: focusNode,
      onSelect: onSelect,
      builder: (context, f) => AnimatedScale(
        scale: f ? 1.06 : 1,
        duration: Motion.popDuration,
        curve: Motion.pop,
        child: AnimatedContainer(
          duration: Motion.pressIn * 2,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: DS.s16),
          alignment: Alignment.center,
          // Classic: white when focused, a soft fill + ring when chosen. Tiles: the accent when
          // chosen, the Metro frame for focus.
          decoration: TvMetro.on
              ? BoxDecoration(color: selected ? TvMetro.tileFill : TvDS.surface, borderRadius: TvMetro.corners(0), boxShadow: TvMetro.glow(f))
              : BoxDecoration(
                  color: f ? TvDS.surfaceFocused : (selected ? const Color(0x29FFFFFF) : TvDS.surface),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selected && !f ? const Color(0x99FFFFFF) : Colors.transparent, width: 1.5),
                ),
          foregroundDecoration: TvMetro.on ? TvMetro.frame(f, width: 2) : null,
          child: Text(
            TvMetro.cased(label),
            style: TvDS.panelRow.copyWith(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: !TvMetro.on && f ? TvDS.onLight : (selected || f ? TvDS.ink : TvDS.inkMuted),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One episode: its still (IMDb's pill on it when the episode has a score), "E9 · Name", length ·
/// air date, two lines of plot.
class TvEpisodeCard extends StatelessWidget {
  const TvEpisodeCard({super.key, required this.episode, this.rating, this.runtime, this.onSelect, this.focusNode, this.onFocus});
  final ShowEpisode episode;
  final double? rating; // the episode's own IMDb score
  final int? runtime; // when the episode has none of its own: the show's usual length
  final VoidCallback? onSelect;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;

  static const w = 240.0, stillH = 135.0;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final mins = e.runtime ?? runtime;
    final meta = [if (mins != null) mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m', if (e.released != null) reviewDate(e.released!)];
    return Semantics(
      button: true,
      label: 'Episode ${e.episode}${e.name == null ? '' : ', ${e.name}'}${rating == null ? '' : ', IMDb ${_score(rating!)}'}',
      child: TvFocusable(
        focusNode: focusNode,
        onFocus: onFocus,
        onSelect: onSelect,
        builder: (context, f) => SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: f ? TvDS.focusScaleCard : 1,
                duration: Motion.popDuration,
                curve: Motion.pop,
                child: AnimatedContainer(
                  duration: Motion.pressIn * 2,
                  width: w,
                  height: stillH,
                  foregroundDecoration: TvMetro.on
                      ? TvMetro.frame(f, width: TvDS.focusRing)
                      : BoxDecoration(
                          borderRadius: BorderRadius.circular(TvDS.rTile - 4),
                          border: Border.all(color: f ? TvDS.surfaceFocused : Colors.transparent, width: TvDS.focusRing),
                        ),
                  decoration: BoxDecoration(
                    borderRadius: TvMetro.corners(TvDS.rTile - 4),
                    boxShadow: TvMetro.on ? TvMetro.glow(f) : (f ? const [BoxShadow(color: TvDS.glow, blurRadius: 22)] : null),
                  ),
                  child: ClipRRect(
                    borderRadius: TvMetro.corners(TvDS.rTile - 4),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ShowImage(urls: [?e.still], decodeWidth: 400, fallbackTitle: 'Episode ${e.episode}'),
                        if (rating != null) Positioned(top: DS.s8, left: DS.s8, child: ImdbBadge(rating!)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DS.s12),
              Text(
                ['E${e.episode}', ?e.name].join(' · '),
                style: TvDS.tileName.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: f ? TvDS.ink : const Color(0xE6FFFFFF)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  meta.join(' · '),
                  style: TvDS.tileName.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: TvDS.inkMuted),
                  maxLines: 1,
                ),
              ],
              if (e.overview != null) ...[
                const SizedBox(height: DS.s4),
                Text(
                  e.overview!,
                  style: TvDS.tileName.copyWith(fontSize: 12, fontWeight: FontWeight.w400, height: 1.35, color: TvDS.inkMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
