import 'package:flutter/material.dart';

import 'one_stream.dart';
import 'ratings.dart';
import 'tiles/tiles_home.dart' show tileAccent, tileAccentText;
import 'tv/catalog.dart' show ShowTitle;
import 'ui/ds.dart';
import 'ui/motion.dart';
import 'ui/rating_badges.dart';
import 'widgets.dart';

/// The phone's critics' scores and reviews for One Stream titles (data: ratings.dart, shared with
/// the TV): the ratings row, IMDb's pill on posters (only once a score is known — posters never
/// ask), review cards and the full review. Classic: rounded, Sentence case; Metro: flat, lowercase.
/// The services' badges keep their brand colours in both.

/// A One Stream title as the key scores and reviews are asked by: its IMDb id, else its TMDB id.
ShowTitle? extrasTitleOf(OneStreamTitle t) {
  final id = t.imdb ?? (t.tmdb == null ? null : 'tmdb${t.tmdb}');
  return id == null ? null : ShowTitle(id: id, type: t.isTv ? 'series' : 'movie', title: t.title, year: t.year?.toString());
}

/// IMDb's pill for a poster, when its score is already known (else nothing). Rebuilds when saved
/// scores arrive.
class PosterImdbPill extends StatelessWidget {
  const PosterImdbPill({super.key, required this.imdb, this.size = 10});
  final String? imdb;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (imdb == null) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: TitleExtras.instance.changed,
      builder: (context, _, _) {
        final r = TitleExtras.instance.imdbNow(imdb);
        return r == null ? const SizedBox.shrink() : ImdbBadge(r, size: size);
      },
    );
  }
}

/// IMDb · Rotten Tomatoes · Metacritic: only the ones there are; nothing at all when none.
class PhoneRatingsRow extends StatelessWidget {
  const PhoneRatingsRow({super.key, required this.ratings});
  final TitleRatings? ratings;

  @override
  Widget build(BuildContext context) {
    final r = ratings;
    if (r == null || r.isEmpty) return const SizedBox.shrink();
    return Wrap(
      key: const ValueKey('ratings'),
      spacing: DS.s16,
      runSpacing: DS.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (r.imdb != null) ImdbBadge(r.imdb!, size: 14),
        if (r.rottenTomatoes != null) RottenTomatoesBadge(r.rottenTomatoes!, size: 14, ink: DS.ink),
        if (r.metascore != null) MetacriticBadge(r.metascore!, size: 14, muted: DS.inkMuted),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, {this.size = 28});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    // Metro: an accent square; Classic: a disc in a calm colour from the name.
    decoration: DS.metro
        ? BoxDecoration(color: tileAccent(), borderRadius: BorderRadius.circular(DS.metroRadius * .5))
        : BoxDecoration(shape: BoxShape.circle, color: HSLColor.fromAHSL(1, (name.hashCode % 360).abs().toDouble(), .38, .46).toColor()),
    child: Text(
      name.characters.firstOrNull?.toUpperCase() ?? '?',
      style: TextStyle(fontFamily: DS.font, fontSize: size * .46, fontWeight: FontWeight.w600, color: Colors.white),
    ),
  );
}

/// One review in the sideways row: who, their score, the first lines. Tap → the whole review.
class PhoneReviewCard extends StatelessWidget {
  const PhoneReviewCard({super.key, required this.review, required this.onTap});
  final ShowReview review;
  final VoidCallback onTap;

  static const w = 264.0, h = 148.0;

  @override
  Widget build(BuildContext context) {
    final r = review;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : 16),
      side: DS.metro ? BorderSide(color: DS.ink.withValues(alpha: .25), width: 1) : BorderSide.none,
    );
    return Semantics(
      button: true,
      label: 'Review by ${r.author}${r.rating == null ? '' : ', ${scoreLabel(r.rating!, trim: true)} out of 10'}',
      excludeSemantics: true,
      child: Pressable(
        scale: .97,
        child: Material(
          color: DS.metro ? Colors.transparent : DS.cardMuted,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: SizedBox(
              width: w,
              height: h,
              child: Padding(
                padding: const EdgeInsets.all(DS.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Avatar(r.author, size: 24),
                        const SizedBox(width: DS.s8),
                        Expanded(
                          child: Text(
                            r.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DS.rowTitle.copyWith(fontSize: 14, fontWeight: DS.metro ? FontWeight.w400 : FontWeight.w600),
                          ),
                        ),
                        if (r.rating != null) ...[const SizedBox(width: DS.s8), ReviewScore(r.rating!, size: 11)],
                      ],
                    ),
                    const SizedBox(height: DS.s8),
                    Expanded(
                      child: Text(
                        r.text.replaceAll(RegExp(r'\s*\n+\s*'), ' '),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: DS.rowSub.copyWith(fontSize: 13, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The reviews: "Reviews · 12", then the cards sideways. Nothing when there are none.
class PhoneReviewsSection extends StatelessWidget {
  const PhoneReviewsSection({super.key, required this.reviews, required this.title, required this.header});
  final ShowReviews? reviews;
  final String title; // the show / film
  final Widget Function(String text) header; // the sheet's own section header

  @override
  Widget build(BuildContext context) {
    final list = reviews?.list ?? const <ShowReview>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('reviews'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header('Reviews · ${reviews!.total}'),
        SizedBox(
          height: PhoneReviewCard.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: DS.s24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: DS.s12),
            itemBuilder: (context, i) => PhoneReviewCard(review: list[i], onTap: () => showReview(context, list[i], title)),
          ),
        ),
      ],
    );
  }
}

/// A review, whole, in its own sheet: who, score, date, the text.
Future<void> showReview(BuildContext context, ShowReview r, String title) => showOneSheetWith(
  context,
  back: true,
  builder: (ctx) => Padding(
    key: const ValueKey('review-sheet'),
    padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DS.metro ? DS.cased('Review · $title') : 'REVIEW · ${title.toUpperCase()}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DS.metro
              ? TextStyle(fontFamily: DS.font, color: tileAccentText(), fontSize: 16, fontWeight: FontWeight.w400)
              : DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 12),
        ),
        const SizedBox(height: DS.s12),
        Row(
          children: [
            _Avatar(r.author, size: 36),
            const SizedBox(width: DS.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DS.rowTitle.copyWith(fontSize: 18, fontWeight: DS.metro ? FontWeight.w300 : FontWeight.w600),
                  ),
                  if (r.created != null) Text(reviewDate(r.created!), style: DS.rowSub.copyWith(fontSize: 13)),
                ],
              ),
            ),
            if (r.rating != null) ...[const SizedBox(width: DS.s12), ReviewScore(r.rating!, size: 13)],
          ],
        ),
        const SizedBox(height: DS.s16),
        Text(r.text, style: DS.rowSub.copyWith(color: DS.ink, fontSize: 15, height: 1.5)),
      ],
    ),
  ),
);

/// A season's episode as a row: still (with how far in), "E9 · Name", air date, two lines of plot,
/// and that episode's own IMDb pill when it has a score.
class PhoneEpisodeRow extends StatelessWidget {
  const PhoneEpisodeRow({super.key, required this.episode, required this.still, this.rating, this.selected = false, this.onTap, this.progressBar});
  final OneStreamEpisode episode;
  final Widget still; // the sheet draws pictures its own way
  final double? rating;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? progressBar;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final when = [if (!e.aired) DS.cased('Coming ${e.airDate ?? 'soon'}') else ?e.airDate, if (e.progress >= .95) DS.cased('Watched')].join(' · ');
    return Material(
      color: selected ? DS.cardMuted : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: DS.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                height: 63,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : 10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      still,
                      if (rating != null) Positioned(top: 4, left: 4, child: ImdbBadge(rating!, size: 9)),
                      if (progressBar != null) Positioned(left: 0, right: 0, bottom: 0, child: progressBar!),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: DS.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${e.code} · ${e.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DS.rowTitle.copyWith(fontSize: 15, fontWeight: DS.metro ? FontWeight.w400 : FontWeight.w500),
                    ),
                    if (when.isNotEmpty) Text(when, maxLines: 1, style: DS.rowSub.copyWith(fontSize: 12)),
                    if (e.overview != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(e.overview!, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.rowSub.copyWith(fontSize: 13, height: 1.3)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
