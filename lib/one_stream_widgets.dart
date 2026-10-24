import 'dart:async';

import 'package:flutter/material.dart';

import 'one_stream.dart';
import 'one_stream_extras.dart';
import 'one_stream_sheet.dart';
import 'ui/ds.dart';

/// A One Stream poster (or backdrop) from its https link; while it loads or when it can't,
/// a tinted panel with the title. Corners: the design language's media radius. Posters big enough
/// carry IMDb's pill top left once the title's IMDb score is known (One Stream's own score is
/// TMDB's, so it's never shown as IMDb's).
class OneStreamArt extends StatelessWidget {
  const OneStreamArt({super.key, required this.title, this.backdrop = false, this.radius});
  final OneStreamTitle title;
  final bool backdrop; // wide picture first (Today widget)
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final t = title;
    final url = backdrop ? (t.backdrop ?? t.poster) : (t.poster ?? t.backdrop);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [DS.hero, DS.cardMuted]),
      ),
      // A backdrop has its words on top already (Today widget): no title on the stand-in.
      child: backdrop
          ? null
          : Padding(
              padding: const EdgeInsets.all(DS.s8),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  t.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: DS.rowSub.copyWith(color: DS.heroInk, fontWeight: FontWeight.w600),
                ),
              ),
            ),
    );
    final art = ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? DS.rMedia),
      child: url == null
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: backdrop ? 640 : 240,
              frameBuilder: (context, child, frame, sync) => frame == null && !sync ? fallback : child,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
    if (backdrop || t.imdb == null) return art;
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 72
          ? art // a small thumbnail: no room for it
          : Stack(
              fit: StackFit.expand,
              children: [
                art,
                Positioned(top: 6, left: 6, child: PosterImdbPill(imdb: t.imdb)),
              ],
            ),
    );
  }
}

/// Search → "Movies & shows": One Stream's results for [query] as a sideways row of posters
/// (title + year / episode under). Asks ~400 ms after typing stops, from 2 letters; shows
/// nothing while One Stream is missing or finds nothing. Tap → its sheet (here, not in One Stream).
/// [header] / [wrap] / [ink]: the host search's own look (Classic card or Metro rows);
/// [gap]: space around it, only while it shows.
class OneStreamSearchRow extends StatefulWidget {
  const OneStreamSearchRow({
    super.key,
    required this.query,
    required this.header,
    this.wrap,
    this.gap = EdgeInsets.zero,
    this.ink,
    this.inkMuted,
    this.inset = DS.s12,
    this.onOpen,
  });
  final String query;
  final VoidCallback? onOpen; // a poster was opened (search history counts the search as used)
  final Widget header;
  final Widget Function(Widget child)? wrap;
  final EdgeInsets gap;
  final Color? ink, inkMuted;
  final double inset; // the row's side padding (lines the first poster up with the header)

  static const debounce = Duration(milliseconds: 400);

  @override
  State<OneStreamSearchRow> createState() => _OneStreamSearchRowState();
}

class _OneStreamSearchRowState extends State<OneStreamSearchRow> {
  List<OneStreamTitle> _found = const [];
  Timer? _wait;
  String _asked = '';

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(OneStreamSearchRow old) {
    super.didUpdateWidget(old);
    if (old.query.trim() != widget.query.trim()) _schedule();
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _schedule() {
    _wait?.cancel();
    final q = widget.query.trim();
    if (q.length < 2) {
      if (_found.isNotEmpty) setState(() => _found = const []);
      return;
    }
    // The last results stay up while the next search runs (no flicker between letters).
    _wait = Timer(OneStreamSearchRow.debounce, () async {
      _asked = q;
      final r = await OneStream.instance.search(q);
      if (mounted && _asked == q) setState(() => _found = r);
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: OneStream.instance.available,
    builder: (context, on, _) {
      if (!on || _found.isEmpty || widget.query.trim().length < 2) return const SizedBox.shrink();
      final ink = widget.ink ?? DS.ink, muted = widget.inkMuted ?? DS.inkMuted;
      final row = SizedBox(
        height: 196,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: widget.inset),
          itemCount: _found.length,
          separatorBuilder: (_, _) => const SizedBox(width: DS.s12),
          itemBuilder: (context, i) {
            final t = _found[i];
            return Semantics(
              button: true,
              label: '${t.title}, ${t.caption}',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(DS.rMedia),
                onTap: () {
                  widget.onOpen?.call();
                  showOneStreamTitle(context, t);
                },
                child: SizedBox(
                  width: 96,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 96, height: 144, child: OneStreamArt(title: t)),
                      const SizedBox(height: 6),
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: DS.font, color: ink, fontSize: 13, fontWeight: DS.metro ? FontWeight.w400 : FontWeight.w500),
                      ),
                      Text(
                        DS.cased(t.caption),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: DS.font, color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [widget.header, row]);
      return Padding(padding: widget.gap, child: widget.wrap?.call(body) ?? body);
    },
  );
}
