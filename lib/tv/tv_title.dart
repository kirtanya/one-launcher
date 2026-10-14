import 'package:flutter/material.dart';

import '../apps.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'tmdb.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';
import 'tv_parts.dart';

// ---- Streaming service → the app on this TV ---------------------------------------

/// Known services → their Android TV apps (India first). Anything else is matched by name.
const _servicePackages = <String, String>{
  'netflix': 'com.netflix.ninja',
  'amazonprimevideo': 'com.amazon.amazonvideo.livingroom',
  'amazonvideo': 'com.amazon.amazonvideo.livingroom',
  'primevideo': 'com.amazon.amazonvideo.livingroom',
  'jiohotstar': 'in.startv.hotstar',
  'hotstar': 'in.startv.hotstar',
  'disneyplushotstar': 'in.startv.hotstar',
  'jiocinema': 'in.startv.hotstar',
  'zee5': 'com.graymatrix.did',
  'sonyliv': 'com.sonyliv',
  'youtube': 'com.google.android.youtube.tv',
  'youtubepremium': 'com.google.android.youtube.tv',
  'appletvplus': 'com.apple.atve.androidtv.appletv',
  'appletv': 'com.apple.atve.androidtv.appletv',
  'mxplayer': 'com.mxtech.videoplayer.television',
  'sunnxt': 'com.suntv.sunnxt',
  'aha': 'ahaflix.tv',
  'lionsgateplay': 'com.lionsgateplay.videoapp',
  'mubi': 'com.mubi',
  'crunchyroll': 'com.crunchyroll.crunchyroid',
};

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// The installed app for a streaming service, if there is one.
AppEntry? appForService(String service, List<AppEntry> apps) {
  final n = _norm(service.replaceAll(RegExp(r'(with ads|amazon channel|apple tv channel)', caseSensitive: false), ''));
  final byPkg = {for (final a in apps) a.package: a};
  for (final e in _servicePackages.entries) {
    if (n.startsWith(e.key) && byPkg[e.value] != null) return byPkg[e.value];
  }
  final first = _norm(service.split(' ').first);
  if (first.length < 3) return null;
  return apps.where((a) => _norm(a.label).contains(first) || n.contains(_norm(a.label))).firstOrNull;
}

const _kindLabel = {'stream': 'Stream', 'free': 'Free', 'ads': 'Free with ads', 'rent': 'Rent', 'buy': 'Buy'};

// ---- Poster tile ------------------------------------------------------------------

/// A show / film as a 2:3 poster: rating badge, title + year underneath.
class TvPoster extends StatelessWidget {
  const TvPoster({super.key, required this.title, required this.onSelect, this.focusNode});
  final TmdbTitle title;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  static const w = 116.0, h = 174.0;

  @override
  Widget build(BuildContext context) {
    final t = title;
    return Semantics(
      button: true,
      label: t.title,
      child: TvFocusable(
        focusNode: focusNode,
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
                  height: h,
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    border: Border.all(color: f ? TvDS.surfaceFocused : Colors.transparent, width: TvDS.focusRing),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    boxShadow: f ? const [BoxShadow(color: TvDS.glow, blurRadius: 22)] : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        TmdbImage(path: t.poster, size: 'w342', decodeWidth: 240, fallbackTitle: t.title),
                        if (t.rating != null) Positioned(top: DS.s8, right: DS.s8, child: _RatingBadge(t.rating!)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DS.s12),
              Text(
                t.title,
                style: TvDS.tileName.copyWith(fontSize: 14, color: f ? TvDS.ink : TvDS.inkMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text([if (t.year != null) t.year!, t.isTv ? 'Series' : 'Film'].join(' · '), style: TvDS.tileName.copyWith(fontSize: 12, color: TvDS.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge(this.rating);
  final double rating;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(6)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF5C518)),
        const SizedBox(width: 2),
        Text(rating.toStringAsFixed(1), style: TvDS.keycap.copyWith(fontSize: 11)),
      ],
    ),
  );
}

/// A TMDB picture, decoded small (TVs have little memory); a tinted title card if missing.
class TmdbImage extends StatelessWidget {
  const TmdbImage({super.key, required this.path, this.size = 'w500', this.decodeWidth = 400, this.fallbackTitle, this.alignment = Alignment.center});
  final String? path;
  final String size;
  final int decodeWidth;
  final String? fallbackTitle;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tvTint(fallbackTitle ?? ''), TvDS.canvas]),
      ),
      child: fallbackTitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(DS.s12),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(fallbackTitle!, style: TvDS.panelTitle.copyWith(fontSize: 17, height: 1.1), maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
            ),
    );
    if (path == null || TvApps.demo) return fallback;
    // Through Android's network (TvApps.image → TvActivity), downsized on the TV side.
    final url = Tmdb.image(path!, size: size);
    final ready = TvApps.instance.imageNow(url);
    if (ready != null) return Image(image: ready, fit: BoxFit.cover, alignment: alignment, gaplessPlayback: true);
    return FutureBuilder<MemoryImage?>(
      future: TvApps.instance.image(url, width: decodeWidth),
      builder: (context, s) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: s.data == null
            ? KeyedSubtree(key: const ValueKey(0), child: fallback)
            : Image(key: const ValueKey(1), image: s.data!, fit: BoxFit.cover, alignment: alignment, gaplessPlayback: true),
      ),
    );
  }
}

// ---- Details page ---------------------------------------------------------------

/// A show or film, cinematic: backdrop, title, ratings, where to watch (open it on this TV),
/// trailer, cast.
class TvTitlePage extends StatefulWidget {
  const TvTitlePage({super.key, required this.title, required this.apps, required this.searchTargets, required this.onOpenApp});
  final TmdbTitle title;
  final List<AppEntry> apps;
  final List<String> searchTargets; // apps that accept a search → we can jump to the title
  final void Function(AppEntry app) onOpenApp; // records "Jump back in" too

  @override
  State<TvTitlePage> createState() => _TvTitlePageState();
}

class _TvTitlePageState extends State<TvTitlePage> {
  late final Future<TmdbDetails> _details = Tmdb.instance.details(widget.title);

  /// Watch on an app: straight to the title when the app takes searches, else just open it.
  void _watch(AppEntry app) {
    if (widget.searchTargets.contains(app.package)) {
      TvApps.instance.searchIn(app.package, widget.title.title);
    } else {
      widget.onOpenApp(app);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    return Scaffold(
      backgroundColor: TvDS.canvas,
      body: LayoutBuilder(
        builder: (context, c) => Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              right: 0,
              width: c.maxWidth * .78,
              height: c.maxHeight * .86,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.06, end: 1),
                duration: const Duration(milliseconds: 2200),
                curve: Curves.easeOutCubic,
                builder: (context, s, child) => Transform.scale(scale: s, alignment: Alignment.topRight, child: child),
                child: TmdbImage(path: t.backdrop ?? t.poster, size: 'w1280', decodeWidth: 1280, alignment: Alignment.topCenter),
              ),
            ),
            const TvScrims(),
            FutureBuilder<TmdbDetails>(
              future: _details,
              builder: (context, s) => SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(TvDS.safe.left, 64, TvDS.safe.right, TvDS.safe.bottom + DS.s24),
                child: FocusTraversalGroup(child: _body(s.data, s.error, s.connectionState == ConnectionState.done)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(TmdbDetails? d, Object? error, bool done) {
    final t = d?.title ?? widget.title;
    final meta = [
      if (t.year != null) t.year!,
      if (d?.genres.isNotEmpty ?? false) d!.genres.take(3).join(', '),
      if (d?.runtime != null && d!.runtime! > 0) '${d.runtime! ~/ 60 > 0 ? '${d.runtime! ~/ 60} h ' : ''}${d.runtime! % 60} min',
      if (d?.seasons != null) '${d!.seasons} ${d.seasons == 1 ? 'season' : 'seasons'}',
    ];
    // Where to watch: services with an app here first (they're buttons), the rest listed.
    final here = <(TmdbProvider, AppEntry)>[];
    final elsewhere = <TmdbProvider>[];
    for (final p in d?.providers ?? const <TmdbProvider>[]) {
      final app = appForService(p.name, widget.apps);
      if (app != null && !here.any((h) => h.$2.package == app.package)) {
        here.add((p, app));
      } else if (app == null) {
        elsewhere.add(p);
      }
    }

    var autofocused = false;
    bool first() {
      if (autofocused) return false;
      return autofocused = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.isTv ? 'SERIES' : 'FILM', style: TvDS.heroEyebrow),
              const SizedBox(height: DS.s8),
              Text(t.title, style: TvDS.heroTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (d?.tagline != null) ...[const SizedBox(height: DS.s8), Text(d!.tagline!, style: TvDS.heroBody.copyWith(fontStyle: FontStyle.italic))],
              const SizedBox(height: DS.s12),
              Wrap(
                spacing: DS.s12,
                runSpacing: DS.s8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (t.rating != null) _Chip(icon: Icons.star_rounded, iconColor: const Color(0xFFF5C518), label: '${t.rating!.toStringAsFixed(1)} TMDB'),
                  if (d?.votes != null && d!.votes! > 0) Text('${_compact(d.votes!)} ratings', style: TvDS.heroMeta.copyWith(fontSize: 13)),
                  if (d?.certification != null) _Chip(label: d!.certification!),
                  if (meta.isNotEmpty) Text(meta.join(' · '), style: TvDS.heroMeta),
                ],
              ),
              if (t.overview != null) ...[
                const SizedBox(height: DS.s16),
                Text(t.overview!, style: TvDS.heroBody, maxLines: 4, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        const SizedBox(height: DS.s24),

        // ---- Where to watch ----
        const Text('Where to watch', style: TvDS.rowTitleFocused),
        const SizedBox(height: DS.s12),
        if (!done)
          const Text('Finding where it’s streaming…', style: TvDS.heroBody)
        else if (error != null)
          Text(error is TmdbException ? '$error.' : 'Couldn’t reach TMDB. Check the TV’s internet.', style: TvDS.heroBody)
        else
          Wrap(
            spacing: DS.s12,
            runSpacing: DS.s12,
            children: [
              for (final (p, app) in here)
                TvActionPill(
                  autofocus: first(),
                  leading: SizedBox(width: 40, height: 22.5, child: TvAppArt(app: app, width: 40)),
                  label: 'Watch on ${app.label}',
                  detail: _kindLabel[p.kind],
                  onSelect: () => _watch(app),
                ),
              if (d?.trailer != null)
                TvActionPill(
                  autofocus: first(),
                  icon: Icons.play_circle_outline_rounded,
                  label: 'Trailer',
                  onSelect: () => TvApps.instance.openUri('https://www.youtube.com/watch?v=${d!.trailer}', package: 'com.google.android.youtube.tv'),
                ),
              TvActionPill(
                autofocus: first(),
                icon: Icons.travel_explore_rounded,
                label: 'Search everywhere',
                onSelect: () => TvApps.instance.searchEverywhere(t.title),
              ),
            ],
          ),
        if (done && error == null) ...[
          const SizedBox(height: DS.s12),
          Text(
            here.isEmpty && elsewhere.isEmpty
                ? 'Not streaming in your country right now.'
                : elsewhere.isEmpty
                ? ''
                : 'Also on ${elsewhere.take(5).map((p) => '${p.name} (${_kindLabel[p.kind]!.toLowerCase()})').join(', ')}',
            style: TvDS.heroBody.copyWith(fontSize: 13),
          ),
        ],

        // ---- Cast ----
        if (d?.cast.isNotEmpty ?? false) ...[
          const SizedBox(height: DS.s24),
          const Text('Cast', style: TvDS.rowTitleFocused),
          const SizedBox(height: DS.s12),
          SizedBox(
            height: 150,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, p) in d!.cast.indexed) ...[if (i > 0) const SizedBox(width: DS.s20), _CastCard(person: p)],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: DS.s12),
        const Text(
          'Data: TMDB · where to watch by JustWatch',
          style: TextStyle(fontFamily: DS.font, fontSize: 11, color: TvDS.inkMuted),
        ),
      ],
    );
  }

  static String _compact(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K' : '$n';
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon, this.iconColor});
  final String label;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: TvDS.inkMuted),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: iconColor ?? TvDS.ink), const SizedBox(width: 4)],
        Text(label, style: TvDS.keycap),
      ],
    ),
  );
}

/// Round photo, name, role. Focusable so the remote can scroll through the cast.
class _CastCard extends StatelessWidget {
  const _CastCard({required this.person});
  final TmdbPerson person;

  @override
  Widget build(BuildContext context) => TvFocusable(
    builder: (context, f) => SizedBox(
      width: 96,
      child: Column(
        children: [
          AnimatedScale(
            scale: f ? 1.1 : 1,
            duration: Motion.popDuration,
            curve: Motion.pop,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: f ? TvDS.surfaceFocused : Colors.transparent, width: TvDS.focusRing),
              ),
              child: ClipOval(
                child: person.photo == null
                    ? ColoredBox(
                        color: TvDS.surface,
                        child: Center(child: Text(person.name.isEmpty ? '?' : person.name[0], style: TvDS.panelTitle)),
                      )
                    : TmdbImage(path: person.photo, size: 'w185', decodeWidth: 160),
              ),
            ),
          ),
          const SizedBox(height: DS.s8),
          Text(
            person.name,
            style: TvDS.tileName.copyWith(color: f ? TvDS.ink : TvDS.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (person.character != null && person.character!.isNotEmpty)
            Text(
              person.character!,
              style: TvDS.tileName.copyWith(fontSize: 11, color: TvDS.inkMuted, fontWeight: FontWeight.w400),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
        ],
      ),
    ),
  );
}
