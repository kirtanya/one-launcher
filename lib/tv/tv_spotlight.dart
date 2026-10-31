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

  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> {
  int _col = 0;
  final _at = <String, int>{}; // each column's focused card
  final _nodes = <String, FocusNode>{};
  final _top = <String, FocusNode>{};
  final _scroll = ScrollController();

  static const _cardH = 158.0, _gap = 16.0, _colW = 300.0;

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

  @override
  void didUpdateWidget(_Spotlight old) {
    super.didUpdateWidget(old);
    _landWhenReady();
    // The rows changed under us (an app opened, the catalog refreshed): keep the column in range.
    if (_col >= _rows.length && _rows.isNotEmpty) _col = _rows.length - 1;
  }

  /// The rows load after the first frame: land on the first card as soon as there is one.
  void _landWhenReady() {
    if (_landed || _rows.isEmpty) return;
    _landed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => land());
  }

  @override
  void dispose() {
    for (final n in [..._nodes.values, ..._top.values]) {
      n.dispose();
    }
    _scroll.dispose();
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
    if (_scroll.hasClients) {
      final y = (at * (_cardH + _gap) - _cardH * .4).clamp(0.0, _scroll.position.maxScrollExtent);
      animate ? _scroll.animateTo(y, duration: TvLook.anim(const Duration(milliseconds: 320)), curve: Curves.easeOutCubic) : _scroll.jumpTo(y);
    }
  }

  void _switch(int dir) {
    if (_rows.length < 2) return;
    HapticFeedback.selectionClick();
    setState(() => _col = (_col + dir) % _rows.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _focusCard(_at[_row!.id] ?? 0, animate: false);
    });
  }

  /// Moves inside the column: ↑ ↓ cards, ← → columns, ↑ from the top card to the top bar.
  bool _move(int i, AxisDirection d) {
    final n = _row?.items.length ?? 0;
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
            bottom: TvDS.safe.bottom + DS.s24,
            width: math.min(TvDS.heroW + 60, c.maxWidth - _colW - TvDS.safe.horizontal - DS.s48),
            child: ExcludeFocus(
              child: _HeroInfo(item: TvLook.on('hero') ? widget.hero : null, chip: null, rowTitle: row?.title),
            ),
          ),

          // ---- The column ----
          Positioned(top: TvDS.safe.top + 64, right: TvDS.safe.right, bottom: 0, width: _colW, child: row == null ? const SizedBox.shrink() : _column(row)),

          // ---- Top bar: everything on the right ----
          Positioned(
            top: TvDS.safe.top,
            right: TvDS.safe.right,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, id) in widget.header.indexed) ...[
                  if (i > 0) const SizedBox(width: DS.s8),
                  _TopButton(
                    id: id,
                    text: id == 'perms' ? widget.missingLabel : null,
                    focusNode: _topNode(id),
                    onSelect: () => widget.onHeader(id),
                    onMove: (d) => _moveTop(i, d),
                  ),
                ],
                const SizedBox(width: DS.s20),
                SizedBox(
                  height: 40,
                  child: Center(child: _Clock(prefs: widget.prefs)),
                ),
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
              controller: _scroll,
              clipBehavior: Clip.none,
              physics: const NeverScrollableScrollPhysics(), // the remote steers it (_focusCard)
              padding: EdgeInsets.only(top: 4, bottom: _cardH * 2),
              itemCount: row.items.length,
              itemExtent: _cardH + _gap,
              itemBuilder: (context, i) {
                final item = row.items[i];
                return Align(
                  alignment: Alignment.topCenter,
                  child: _Card(
                    key: ValueKey('${row.id}:${item.key}'),
                    item: item,
                    width: _colW,
                    height: _cardH,
                    focusNode: _node(row.id, i),
                    onSelect: () => widget.onOpen(item),
                    onOptions: () => widget.onOptions(row, i),
                    onMove: (d) => _move(i, d),
                    onFocus: () {
                      _at[row.id] = i;
                      widget.onShow(item);
                    },
                  ),
                );
              },
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
              colors: [Color(0xF2000000), Color(0x99000000), Color(0x00000000)],
              stops: [0, .34, .62],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xFF000000), Color(0xB3000000), Color(0x00000000)],
              stops: [0, .32, .7],
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
