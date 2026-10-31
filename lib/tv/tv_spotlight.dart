part of 'tv_home.dart';

/// Spotlight (Customise → Home view → Spotlight), TV only: cinematic and nearly colourless.
/// The focused item's picture fills a pure-black screen; its title block sits bottom-left and
/// is only to look at. Everything you steer lives in one column on the right: Classic's content
/// rows turned on their side (Continue watching, Your apps, Jump back in, the apps' own rows),
/// one column at a time. ↑ ↓ move in the column, ← → switch columns (each keeps its place),
/// ↑ from the first card reaches the top bar (search, voice, customise, clock — top right).
class _Spotlight extends StatefulWidget {
  const _Spotlight({
    super.key,
    required this.rows,
    required this.prefs,
    required this.hero,
    required this.backdrop,
    required this.header,
    required this.missingLabel,
    required this.onShow,
    required this.onOpen,
    required this.onOptions,
    required this.onHeader,
    required this.moving,
    required this.onShift,
    required this.onEndMove,
  });
  final List<TvRow> rows; // the content rows (no chip rows)
  final Prefs prefs;
  final TvItem? hero, backdrop;
  final List<String> header;
  final String? missingLabel;
  final void Function(TvItem item, {bool now}) onShow;
  final void Function(TvItem item) onOpen;
  final void Function(TvRow row, int i) onOptions;
  final void Function(String id) onHeader;

  /// Move mode (Hold OK → Move): the moving app's key ('row:item'); ↑ ↓ slide it, OK / Back end.
  final String? moving;
  final void Function(TvRow row, int i, int by) onShift;
  final VoidCallback onEndMove;

  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> {
  int _col = 0;
  final _at = <String, int>{}; // each column's focused card
  final _nodes = <String, FocusNode>{};
  final _top = <String, FocusNode>{};
  final _scrolls = <String, ScrollController>{}; // one per column (old and new overlap while switching)
  int _dir = 1; // the last ← / → : the new column slides in from that side

  // Customise → Cards & motion → Card size scales the column and its cards.
  static double get _k => TvLook.number('cardScale');
  static double get _cardH => 158 * _k;
  static double get _colW => 300 * _k;
  static double get _chipH => 60 * _k; // quick actions: small cards
  static const _gap = 16.0, _chipGap = 10.0;

  ScrollController _scrollOf(String row) => _scrolls[row] ??= ScrollController();
  static double get _pillH => 64 * _k; // a column's small cards
  static bool _small(TvRow row) => row.id == 'quick';

  /// Customise → Columns: this column's cards small (pill / short card) instead of big.
  static bool _compact(TvRow row) =>
      !_small(row) &&
      TvLook.str(switch (row.id) {
            'continue' => 'spotCardContinue',
            'fav' => 'spotCardFav',
            'recent' => 'spotCardRecent',
            _ => 'spotCardOther',
          }) ==
          'small';
  static double _extent(TvRow row) => _small(row) ? _chipH + _chipGap : (_compact(row) ? _pillH + _chipGap : _cardH + _gap);

  List<TvRow> get _rows => widget.rows;
  TvRow? get _row => _rows.isEmpty ? null : _rows[_col.clamp(0, _rows.length - 1)];

  FocusNode _node(String row, int i) => _nodes['$row:$i'] ??= FocusNode(debugLabel: 'spotlight $row:$i');
  FocusNode _topNode(String id) => _top[id] ??= FocusNode(debugLabel: 'spotlight top $id');

  bool _landed = false; // focus went to the first card once the rows arrived

  @override
  void initState() {
    super.initState();
    _landWhenReady();
  }

  Timer? _landLater;

  @override
  void didUpdateWidget(_Spotlight old) {
    super.didUpdateWidget(old);
    // Columns arrive / change as things load: stay on the same column (by name, not position).
    if (old.rows.isNotEmpty) {
      final was = old.rows[_col.clamp(0, old.rows.length - 1)].id;
      final now = _rows.indexWhere((r) => r.id == was);
      if (now >= 0) _col = now;
    }
    if (_col >= _rows.length && _rows.isNotEmpty) _col = _rows.length - 1;
    _landWhenReady();
    // The focused card went away with the change: focus the column's card again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only on the home screen itself: a panel or page on top (Customise…) keeps its focus.
      if (!mounted || !_landed || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final f = FocusManager.instance.primaryFocus;
      if (f == null || !(_nodes.containsValue(f) || _top.containsValue(f))) _focusCard(_at[_row?.id] ?? 0, animate: false);
    });
  }

  /// The rows load after the first frame: land on the first content card as soon as there is one
  /// (quick actions are ready before the rest; they alone only after a moment).
  void _landWhenReady() {
    if (_landed || _rows.isEmpty) return;
    if (_rows.every((r) => r.id == 'quick')) {
      _landLater ??= Timer(const Duration(seconds: 4), () {
        if (mounted && !_landed) {
          _landed = true;
          land();
        }
      });
      return;
    }
    _landed = true;
    _landLater?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) => land());
  }

  @override
  void dispose() {
    _landLater?.cancel();
    for (final n in [..._nodes.values, ..._top.values]) {
      n.dispose();
    }
    for (final c in _scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Back / first open: the first column's first card.
  void land() {
    if (!mounted || _rows.isEmpty) return;
    setState(() => _col = 0);
    _at[_rows.first.id] = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusCard(0, animate: false));
  }

  void _focusCard(int i, {bool animate = true}) {
    final row = _row;
    if (row == null || row.items.isEmpty) return;
    final at = i.clamp(0, row.items.length - 1);
    _at[row.id] = at;
    _node(row.id, at).requestFocus();
    // The focused card keeps its place near the top of the column; the rest slide past it.
    // The column holds still while focus moves inside what's in view; it scrolls only when the
    // card would leave it — past the clear part at the bottom (the last fifth fades), or above.
    final sc = _scrollOf(row.id);
    if (sc.hasClients) {
      final p = sc.position;
      final ext = _extent(row);
      final top = 4 + at * ext, bottom = top + ext;
      final clear = p.viewportDimension * .78;
      var y = p.pixels;
      if (bottom > y + clear) y = bottom - clear;
      if (top < y) y = top - 4;
      y = y.clamp(0.0, p.maxScrollExtent);
      if (y != p.pixels) {
        animate ? sc.animateTo(y, duration: TvLook.anim(const Duration(milliseconds: 320)), curve: Curves.easeOutCubic) : sc.jumpTo(y);
      }
    }
  }

  void _switch(int dir) {
    if (_rows.length < 2) return;
    HapticFeedback.selectionClick();
    setState(() {
      _dir = dir;
      _col = (_col + dir) % _rows.length;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusCard(_at[_row!.id] ?? 0, animate: false));
  }

  /// Moves inside the column: ↑ ↓ cards, ← → columns, ↑ from the top card to the top bar.
  bool _move(int i, AxisDirection d) {
    final n = _row?.items.length ?? 0;
    final row = _row;
    if (widget.moving != null && row != null) {
      // "Edit" / "All apps" stay at the end; ← → do nothing until OK / Back.
      final last = row.items.last.key == 'q:edit' || row.items.last.key == 'all-apps' ? n - 2 : n - 1;
      final by = d == AxisDirection.up && i > 0 ? -1 : (d == AxisDirection.down && i < last ? 1 : 0);
      if (by != 0) {
        widget.onShift(row, i, by);
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusCard(i + by)); // focus is per place: follow the app
      }
      return true;
    }
    switch (d) {
      case AxisDirection.up:
        if (i == 0) {
          _topNode(widget.header.first).requestFocus();
        } else {
          _focusCard(i - 1);
        }
      case AxisDirection.down:
        if (i < n - 1) _focusCard(i + 1);
      case AxisDirection.left:
        _switch(-1);
      case AxisDirection.right:
        _switch(1);
    }
    return true;
  }

  bool _moveTop(int i, AxisDirection d) {
    final ids = widget.header;
    switch (d) {
      case AxisDirection.left when i > 0:
        _topNode(ids[i - 1]).requestFocus();
      case AxisDirection.right when i < ids.length - 1:
        _topNode(ids[i + 1]).requestFocus();
      case AxisDirection.down:
        _focusCard(_at[_row?.id] ?? 0);
      default:
        break;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    return LayoutBuilder(
      builder: (context, c) => Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF000000)),
          // ---- The picture: the whole screen, shaded toward the text and the column ----
          Positioned.fill(
            child: TvLook.str('backdrop') == 'off' ? const SizedBox.expand() : _Backdrop(item: widget.backdrop, glowOnly: TvLook.str('backdrop') == 'glow'),
          ),
          const _SpotlightScrims(),

          // ---- Title block: only to read ----
          Positioned(
            left: TvDS.safe.left,
            bottom: TvDS.safe.bottom + DS.s48,
            width: math.min(TvDS.heroW + 60, c.maxWidth - _colW - TvDS.safe.horizontal - DS.s48),
            child: ExcludeFocus(
              child: _HeroInfo(item: TvLook.on('hero') ? widget.hero : null, chip: null, rowTitle: row?.title),
            ),
          ),

          // ---- The column ----
          Positioned(
            top: TvDS.safe.top + 64,
            right: TvDS.safe.right,
            bottom: 0,
            width: _colW,
            child: row == null
                ? const SizedBox.shrink()
                // ← → : the new column slides in from that side as the old one leaves.
                : AnimatedSwitcher(
                    duration: TvLook.anim(const Duration(milliseconds: 280)),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                    transitionBuilder: (child, a) {
                      final incoming = child.key == ValueKey('col:${row.id}');
                      final from = Offset((incoming ? .25 : -.25) * _dir, 0);
                      return FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: from, end: Offset.zero).animate(a),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(key: ValueKey('col:${row.id}'), child: _column(row)),
                  ),
          ),

          // ---- Clock, top left; search · voice · customise, top right ----
          Positioned(
            top: TvDS.safe.top,
            left: TvDS.safe.left,
            child: SizedBox(
              height: 40,
              child: Center(child: _Clock(prefs: widget.prefs)),
            ),
          ),
          Positioned(
            top: TvDS.safe.top,
            right: TvDS.safe.right,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, id) in widget.header.indexed) ...[
                  if (i > 0) const SizedBox(width: DS.s12),
                  _TopButton(
                    id: id,
                    compact: true,
                    text: id == 'perms' ? widget.missingLabel : null,
                    focusNode: _topNode(id),
                    onSelect: () => widget.onHeader(id),
                    onMove: (d) => _moveTop(i, d),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(TvRow row) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Which column, and that there are others: ‹ Continue watching › · 1 / 3
        SizedBox(
          height: 32,
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (_rows.length > 1) const Icon(Icons.chevron_left_rounded, size: 20, color: TvDS.inkMuted),
                    Flexible(
                      child: Text(TvMetro.cased(row.title), style: TvDS.rowTitleFocused, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (_rows.length > 1) const Icon(Icons.chevron_right_rounded, size: 20, color: TvDS.inkMuted),
                  ],
                ),
              ),
              if (_rows.length > 1) Text('${_col + 1} / ${_rows.length}', style: TvDS.hint.copyWith(color: TvDS.inkMuted)),
            ],
          ),
        ),
        const SizedBox(height: DS.s12),
        Expanded(
          // Cards fade out toward the bottom of the screen.
          // Cards scrolled past go under the column's top edge (with a little room for the focus
          // ring, and wide open sideways for it) instead of drawing over the title and top bar.
          child: ClipRect(
            clipper: const _ColumnClip(),
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                stops: [0, .78, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: ListView.builder(
                key: ValueKey('spotlight:${row.id}'),
                controller: _scrollOf(row.id),
                clipBehavior: Clip.none,
                physics: const NeverScrollableScrollPhysics(), // the remote steers it (_focusCard)
                padding: EdgeInsets.only(top: 4, bottom: _cardH * 2),
                itemCount: row.items.length,
                itemExtent: _extent(row),
                itemBuilder: (context, i) {
                  final item = row.items[i];
                  void focus() {
                    _at[row.id] = i;
                    widget.onShow(item);
                  }

                  return Align(
                    alignment: Alignment.topCenter,
                    child: _MoveMark(
                      on: widget.moving == '${row.id}:${item.key}',
                      child: _compact(row)
                        ? _SmallCard(
                            key: ValueKey('${row.id}:${item.key}'),
                            item: item,
                            width: _colW,
                            height: _pillH,
                            focusNode: _node(row.id, i),
                            onSelect: () => widget.moving != null ? widget.onEndMove() : widget.onOpen(item),
                            onOptions: () => widget.onOptions(row, i),
                            onMove: (d) => _move(i, d),
                            onFocus: focus,
                          )
                        : _small(row)
                        ? _QuickCard(
                            key: ValueKey('${row.id}:${item.key}'),
                            item: item,
                            width: _colW,
                            height: _chipH,
                            focusNode: _node(row.id, i),
                            onSelect: () => widget.moving != null ? widget.onEndMove() : widget.onOpen(item),
                            onOptions: () => widget.onOptions(row, i),
                            onMove: (d) => _move(i, d),
                            onFocus: focus,
                          )
                        : _Card(
                            key: ValueKey('${row.id}:${item.key}'),
                            item: item,
                            width: _colW,
                            height: _cardH,
                            focusNode: _node(row.id, i),
                            onSelect: () => widget.moving != null ? widget.onEndMove() : widget.onOpen(item),
                            onOptions: () => widget.onOptions(row, i),
                            onMove: (d) => _move(i, d),
                            onFocus: focus,
                          ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Spotlight's shading: a long fall-off from the bottom-left (the title) and from the right (the
/// column), plus a band under the top bar — the picture stays clear in the upper middle.
class _SpotlightScrims extends StatelessWidget {
  const _SpotlightScrims();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [Color(0xF5000000), Color(0xA6000000), Color(0x00000000)],
              stops: [0, .36, .66],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xFF000000), Color(0xBF000000), Color(0x00000000)],
              stops: [0, .3, .62],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x00000000)], stops: [0, .22]),
          ),
        ),
      ],
    ),
  );
}

/// A quick action in Spotlight's column: a small card — its icon (or the app's banner) and name.
/// Outline + fill on focus, never a size change.
class _QuickCard extends StatelessWidget {
  const _QuickCard({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    required this.focusNode,
    required this.onSelect,
    required this.onOptions,
    this.onMove,
    this.onFocus,
  });
  final TvItem item;
  final double width, height;
  final FocusNode focusNode;
  final VoidCallback onSelect, onOptions;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final edit = item.key == 'q:edit';
    final icon = edit ? Icons.add_rounded : tvActions[item.key]?.$2;
    return Semantics(
      button: true,
      label: edit ? 'Edit quick actions' : item.title,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onLongSelect: onOptions,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => AnimatedContainer(
          duration: TvLook.anim(Motion.pressIn * 2),
          width: width,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: DS.s16),
          decoration: BoxDecoration(
            color: f ? TvDS.surfaceFocused : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: f ? Colors.transparent : const Color(0x1FFFFFFF)),
          ),
          child: Row(
            children: [
              if (item.app != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(width: 48, height: 27, child: TvAppArt(app: item.app!, width: 48)),
                )
              else
                Icon(icon ?? Icons.bolt_rounded, size: 24, color: f ? TvDS.onLight : TvDS.ink),
              const SizedBox(width: DS.s12),
              Expanded(
                child: Text(
                  edit ? 'Edit quick actions' : item.title,
                  style: TvDS.panelRow.copyWith(fontSize: 16, color: f ? TvDS.onLight : TvDS.ink),
                  maxLines: 1,
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

/// Spotlight's small card (Customise → a column's page → Cards: Small). A pill, white when
/// focused: an app's round icon and name, or a show's still and title.
class _SmallCard extends StatelessWidget {
  const _SmallCard({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    required this.focusNode,
    required this.onSelect,
    required this.onOptions,
    this.onMove,
    this.onFocus,
  });
  final TvItem item;
  final double width, height;
  final FocusNode focusNode;
  final VoidCallback onSelect, onOptions;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final app = item.kind == TvKind.app || item.key == 'all-apps' ? item.app : null;
    final pill = item.kind == TvKind.app || item.key == 'all-apps';
    return Semantics(
      button: true,
      label: item.title,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onLongSelect: onOptions,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => pill ? _pill(app, f) : _show(f),
      ),
    );
  }

  Widget _pill(AppEntry? app, bool f) => AnimatedContainer(
    duration: TvLook.anim(Motion.pressIn * 2),
    width: width,
    height: height,
    padding: EdgeInsets.symmetric(horizontal: height * .14),
    decoration: BoxDecoration(
      color: f ? TvDS.surfaceFocused : const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(height / 2),
      border: Border.all(color: f ? Colors.transparent : const Color(0x1FFFFFFF)),
    ),
    child: Row(
      children: [
        if (app != null)
          ClipOval(
            child: TvAppIcon(app: app, size: height * .66),
          )
        else
          SizedBox.square(
            dimension: height * .66,
            child: Icon(Icons.apps_rounded, size: height * .4, color: f ? TvDS.onLight : TvDS.ink),
          ),
        SizedBox(width: height * .2),
        Expanded(
          child: Text(
            item.key == 'all-apps' ? 'All apps' : (app?.label ?? item.title),
            style: TvDS.panelRow.copyWith(fontSize: 16, color: f ? TvDS.onLight : TvDS.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  /// A show as a pill like the apps': its still as the icon, the title. The left panel says the
  /// rest (episode, time left); this is just the way in.
  Widget _show(bool f) {
    final h = height * .62;
    Widget picture;
    if (item.art != null) {
      picture = Image(
        image: item.art!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => ColoredBox(color: tvTint(item.title)),
      );
    } else if (item.image != null) {
      final ready = TvApps.instance.imageNow(item.image!);
      picture = FutureBuilder<MemoryImage?>(
        future: ready != null ? Future.value(ready) : TvApps.instance.image(item.image!),
        builder: (context, s) => s.data == null ? ColoredBox(color: tvTint(item.title)) : Image(image: s.data!, fit: BoxFit.cover, gaplessPlayback: true),
      );
    } else {
      picture = ColoredBox(color: tvTint(item.title));
    }
    return AnimatedContainer(
      duration: TvLook.anim(Motion.pressIn * 2),
      width: width,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height * .14),
      decoration: BoxDecoration(
        color: f ? TvDS.surfaceFocused : const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: f ? Colors.transparent : const Color(0x1FFFFFFF)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(h / 2),
            child: SizedBox(width: h * 16 / 9, height: h, child: picture),
          ),
          SizedBox(width: height * .2),
          Expanded(
            child: Text(
              item.title,
              style: TvDS.panelRow.copyWith(fontSize: 16, color: f ? TvDS.onLight : TvDS.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The column's clip: cut at the top (6 pt of room for the focus ring) and bottom, never at the
/// sides (the ring sits just outside the cards).
class _ColumnClip extends CustomClipper<Rect> {
  const _ColumnClip();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-48, -6, size.width + 48, size.height);

  @override
  bool shouldReclip(_ColumnClip old) => false;
}

/// Move mode's mark on the moving app: ↕ at its right edge (↑ ↓ move it, OK / Back done).
class _MoveMark extends StatelessWidget {
  const _MoveMark({required this.on, required this.child});
  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) => on
      ? Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              right: -14,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(color: TvDS.ink, shape: BoxShape.circle),
                  child: const Icon(Icons.unfold_more_rounded, size: 20, color: Color(0xFF000000)),
                ),
              ),
            ),
          ],
        )
      : child;
}
