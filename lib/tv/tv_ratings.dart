import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/ds.dart';
import '../ui/rating_badges.dart';
import '../ui/motion.dart';
import 'catalog.dart';
import '../ratings.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';
import 'tv_metro.dart';
import 'tv_parts.dart';
import 'tv_title.dart' show ShowImage;

export '../ui/rating_badges.dart';

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
      children: [
        if (i != null) ImdbBadge(i, size: 16),
        if (rt != null) RottenTomatoesBadge(rt, ink: TvDS.ink),
        if (mc != null) MetacriticBadge(mc, muted: TvDS.inkMuted),
        ...trailing,
      ],
    );
  }
}

/// Critics' scores and reviews on TV: the ratings row, review cards + page, season tabs and
/// episode cards. The brand badges themselves are shared with the phone (ui/rating_badges.dart).

// ---- Reviews -----------------------------------------------------------------------

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
        builder: (context, f) => AnimatedContainer(
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
          foregroundDecoration: TvMetro.on ? TvMetro.frame(f, width: TvDS.focusRing) : TvRing(on: f, radius: TvDS.rTile - 2),
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
                  if (r.rating != null) ...[const SizedBox(width: DS.s8), ReviewScore(r.rating!)],
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
                  if (r.rating != null) ...[const SizedBox(width: DS.s12), ReviewScore(r.rating!, size: 14)],
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
  const TvSeasonTab({super.key, required this.label, required this.selected, required this.onSelect, this.focusNode, this.leading});
  final String label;
  final Widget? leading; // e.g. a service's app icon
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
      builder: (context, f) => AnimatedContainer(
        duration: Motion.pressIn * 2,
        height: 40,
        padding: EdgeInsets.only(left: leading != null ? DS.s8 : DS.s16, right: DS.s16),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: DS.s8)],
            Text(
              TvMetro.cased(label),
              style: TvDS.panelRow.copyWith(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: !TvMetro.on && f ? TvDS.onLight : (selected || f ? TvDS.ink : TvDS.inkMuted),
              ),
            ),
          ],
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
      label: 'Episode ${e.episode}${e.name == null ? '' : ', ${e.name}'}${rating == null ? '' : ', IMDb ${scoreLabel(rating!)}'}',
      child: TvFocusable(
        focusNode: focusNode,
        onFocus: onFocus,
        onSelect: onSelect,
        builder: (context, f) => SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: Motion.pressIn * 2,
                width: w,
                height: stillH,
                foregroundDecoration: TvMetro.on ? TvMetro.frame(f, width: TvDS.focusRing) : TvRing(on: f, radius: TvDS.rTile - 4),
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
