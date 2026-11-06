part of 'tv_home.dart';

/// Google TV (Customise → Home view → Google TV), TV only: the stock Google TV home, with our
/// pages and data (docs/GOOGLE_TV_VIEW.md). Three places, top to bottom:
/// - the top bar: our pages as pill tabs (Home · Apps · One Stream), Search and Settings (the
///   Quick settings panel), the clock on the right;
/// - the hero: a full-screen picture of what to watch (Continue watching, then the catalog's
///   trending titles), ← → steps through them; focused, it grows (description + "Watch on …")
///   and the apps slide down until only their top peeks out;
/// - Your apps: a 5-column grid of 16:9 banners; focused, the page scrolls so "Your apps" is a
///   big title at the top, then row by row.
/// Focus is a white outline + soft glow, never a scale (user, 2026-11-06). Everything moves with
/// one short slide (~200 ms) and then holds still: nothing animates while idle.
class _GoogleTv extends StatefulWidget {
  const _GoogleTv({
    super.key,
    required this.prefs,
    required this.hero,
    required this.apps,
    required this.missingLabel,
    required this.oneStream,
    required this.onOpen,
    required this.onOptions,
    required this.onTab,
    required this.onHeader,
  });
  final Prefs prefs;
  final List<TvItem> hero; // what the hero shows, one at a time (≤ 5)
  final List<TvItem> apps; // Your apps, then the rest; All apps last
  final String? missingLabel; // "2 permissions needed" (a warning icon in the top bar)
  final bool oneStream; // its tab
  final void Function(TvItem item) onOpen;
  final void Function(List<TvItem> items, int i) onOptions;
  final void Function(String tab) onTab; // 'apps' | 'stream'
  final void Function(String id) onHeader; // 'search' | 'settings' | 'perms'

  @override
  State<_GoogleTv> createState() => _GoogleTvState();
}

enum _GZone { top, hero, grid }

class _GoogleTvState extends State<_GoogleTv> with WidgetsBindingObserver {
  // 1920×1080 px from the scan, halved (the TV draws 960×540 logical).
  static const _inset = 58.0; // left / right
  static const _cols = 5;
  static const _cardW = 150.0, _cardH = 84.0; // 16:9 banner
  static const _labelH = 24.0; // the focused tile's name, under it
  static const _rowGap = 11.0;
  static const _rowExt = _cardH + _labelH + _rowGap;
  static const _titleH = 40.0; // "Your apps" above the grid
  static const _r = 12.0;
  static const _slide = Duration(milliseconds: 200);
  static const _advance = Duration(seconds: 12); // the hero moves on by itself (not while in the grid)

  _GZone _zone = _GZone.top;
  int _hero = 0;
  int _gridAt = 0; // the grid's focused tile
  final _tabNodes = <String, FocusNode>{};
  final _iconNodes = <String, FocusNode>{};
  final _gridNodes = <int, FocusNode>{};
  final _heroNode = FocusNode(debugLabel: 'gtv hero');
  Timer? _auto;

  List<String> get _tabs => ['home', 'apps', if (widget.oneStream) 'stream'];
  List<String> get _icons => ['search', 'settings', if (widget.missingLabel != null) 'perms'];
  List<String> get _top => [..._tabs, ..._icons];
  FocusNode _topNode(String id) => (_tabs.contains(id) ? _tabNodes : _iconNodes)[id] ??= FocusNode(debugLabel: 'gtv top $id');
  FocusNode _gridNode(int i) => _gridNodes[i] ??= FocusNode(debugLabel: 'gtv app $i');

  TvItem? get _heroItem => widget.hero.isEmpty ? null : widget.hero[_hero.clamp(0, widget.hero.length - 1)];
  Duration get _anim => TvLook.anim(_slide);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restartAuto();
    WidgetsBinding.instance.addPostFrameCallback((_) => land());
  }

  @override
  void didUpdateWidget(_GoogleTv old) {
    super.didUpdateWidget(old);
    if (_hero >= widget.hero.length) _hero = 0;
    if (_gridAt >= widget.apps.length) _gridAt = math.max(0, widget.apps.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The focused thing went away with the change (an app hidden…): focus its place again.
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final f = FocusManager.instance.primaryFocus;
      final ours = f == _heroNode || _tabNodes.containsValue(f) || _iconNodes.containsValue(f) || _gridNodes.containsValue(f);
      if (!ours) land();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The hero only advances while the launcher is in front.
    if (state == AppLifecycleState.resumed) {
      if (_auto == null) _restartAuto();
    } else {
      _auto?.cancel();
      _auto = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auto?.cancel();
    _auto = null;
    for (final n in [..._tabNodes.values, ..._iconNodes.values, ..._gridNodes.values, _heroNode]) {
      n.dispose();
    }
    super.dispose();
  }

  /// First open, Home, Back: the Home tab, everything at rest (the hero and the first apps row).
  void land() {
    if (!mounted) return;
    setState(() {
      _zone = _GZone.top;
      _gridAt = 0;
    });
    _topNode('home').requestFocus();
  }

  /// The hero moves on by itself every few seconds — one crossfade, then still — but only while
  /// the hero is on screen, and not with reduced motion.
  void _restartAuto() {
    _auto?.cancel();
    _auto = null;
    if (widget.hero.length < 2 || TvLook.str('motion') == 'reduced') return;
    _auto = Timer.periodic(_advance, (_) {
      if (!mounted || _zone == _GZone.grid || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      setState(() => _hero = (_hero + 1) % widget.hero.length);
    });
  }

  void _stepHero(int by) {
    if (widget.hero.length < 2) return;
    HapticFeedback.selectionClick();
    setState(() => _hero = (_hero + by) % widget.hero.length);
    _restartAuto();
  }

  void _toGrid(int i) {
    if (widget.apps.isEmpty) return;
    _gridNode(i.clamp(0, widget.apps.length - 1)).requestFocus();
  }

  bool _moveTop(String id, AxisDirection d) {
    final ids = _top, i = ids.indexOf(id);
    switch (d) {
      case AxisDirection.left when i > 0:
        _topNode(ids[i - 1]).requestFocus();
      case AxisDirection.right when i < ids.length - 1:
        _topNode(ids[i + 1]).requestFocus();
      case AxisDirection.down:
        widget.hero.isEmpty ? _toGrid(_gridAt) : _heroNode.requestFocus();
      default:
        break;
    }
    return true;
  }

  bool _moveHero(AxisDirection d) {
    switch (d) {
      case AxisDirection.left:
        _stepHero(-1);
      case AxisDirection.right:
        _stepHero(1);
      case AxisDirection.up:
        _topNode('home').requestFocus();
      case AxisDirection.down:
        _toGrid(_gridAt);
    }
    return true;
  }

  bool _moveGrid(int i, AxisDirection d) {
    final n = widget.apps.length;
    switch (d) {
      case AxisDirection.left when i % _cols > 0:
        _toGrid(i - 1);
      case AxisDirection.right when i % _cols < _cols - 1 && i < n - 1:
        _toGrid(i + 1);
      case AxisDirection.up when i >= _cols:
        _toGrid(i - _cols);
      case AxisDirection.up:
        widget.hero.isEmpty ? _topNode('home').requestFocus() : _heroNode.requestFocus();
      // ↓ from a short last row's neighbour: its last tile.
      case AxisDirection.down when i ~/ _cols < (n - 1) ~/ _cols:
        _toGrid(math.min(i + _cols, n - 1));
      default:
        break;
    }
    return true;
  }

  void _focused(_GZone z, [int i = 0]) {
    if (z == _GZone.grid) _gridAt = i;
    if (z != _zone || z == _GZone.grid) setState(() => _zone = z);
  }

  /// Where "Your apps" (its title) starts: under the hero at rest, pushed down to a peek while the
  /// hero is focused, at the top (scrolled row by row) inside the grid.
  double _gridTop(double h) {
    if (_zone == _GZone.grid) return 26 - (_gridAt ~/ _cols) * _rowExt;
    if (widget.hero.isEmpty) return 110;
    return _zone == _GZone.hero ? h - 46 : h * .555;
  }

  @override
  Widget build(BuildContext context) {
    final item = _heroItem;
    final inGrid = _zone == _GZone.grid;
    return LayoutBuilder(
      builder: (context, c) {
        final gridTop = _gridTop(c.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF000000)),
            // ---- The hero's picture: dims away in the grid ----
            // Full-opacity picture + a fading black overlay (no full-screen opacity layer): same look.
            if (TvLook.str('backdrop') != 'off') _Backdrop(item: item, glowOnly: TvLook.str('backdrop') == 'glow'),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: inGrid ? .82 : 0,
                duration: _anim,
                child: const ColoredBox(color: Color(0xFF000000), child: SizedBox.expand()),
              ),
            ),
            TvScrims(strength: TvLook.number('dim'), colour: const Color(0xFF000000), cinema: true),

            // ---- Hero text: sits on the apps' title, grows when focused ----
            if (item != null && TvLook.on('hero'))
              AnimatedPositioned(
                duration: _anim,
                curve: Curves.easeOutCubic,
                left: _inset,
                width: math.min(470, c.maxWidth * .5),
                bottom: inGrid ? c.maxHeight + 40 : c.maxHeight - gridTop + 22,
                child: ExcludeFocus(child: _GoogleHeroText(item: item, open: _zone == _GZone.hero, anim: _anim)),
              ),
            // Its page dots, right.
            if (widget.hero.length > 1)
              AnimatedPositioned(
                duration: _anim,
                curve: Curves.easeOutCubic,
                right: _inset,
                bottom: inGrid ? c.maxHeight + 40 : c.maxHeight - gridTop + 30,
                child: _HeroDots(count: widget.hero.length, at: _hero),
              ),
            // The hero's focus: an invisible stop (the text above grows instead of a ring).
            if (item != null)
              Positioned(
                left: 0,
                top: 0,
                width: 1,
                height: 1,
                child: TvFocusable(
                  focusNode: _heroNode,
                  onFocus: () => _focused(_GZone.hero),
                  onSelect: () => widget.onOpen(item),
                  onLongSelect: () => widget.onOptions(widget.hero, _hero),
                  onMove: _moveHero,
                  builder: (context, f) => const SizedBox.shrink(),
                ),
              ),

            // ---- Your apps ----
            AnimatedPositioned(
              duration: _anim,
              curve: Curves.easeOutCubic,
              left: _inset,
              right: _inset,
              top: gridTop,
              height: _titleH + ((widget.apps.length + _cols - 1) ~/ _cols) * _rowExt + 20,
              child: _grid(inGrid),
            ),

            // ---- Top bar: tabs · search · settings · clock (slides away in the grid) ----
            AnimatedPositioned(
              duration: _anim,
              curve: Curves.easeOutCubic,
              left: _inset,
              right: _inset,
              top: inGrid ? -70 : 34,
              height: 40,
              child: AnimatedOpacity(opacity: inGrid ? 0 : 1, duration: _anim, child: _topBar()),
            ),
            // Scrolled down: a small chevron says there's more above.
            if (inGrid)
              const Positioned(
                top: 4,
                left: 0,
                right: 0,
                child: Icon(Icons.keyboard_arrow_up_rounded, size: 22, color: TvDS.inkMuted),
              ),
          ],
        );
      },
    );
  }

  Widget _topBar() {
    final focusTop = _zone == _GZone.top;
    return Row(
      children: [
        // Our pages: a pill group; the selected tab (Home) is a light pill when focused, brighter text when not.
        _Group(
          children: [
            for (final id in _tabs)
              _GoogleTab(
                label: switch (id) {
                  'home' => 'Home',
                  'apps' => 'Apps',
                  _ => 'One Stream',
                },
                selected: id == 'home',
                barFocused: focusTop,
                focusNode: _topNode(id),
                onFocus: () => _focused(_GZone.top),
                onSelect: () => id == 'home' ? (widget.hero.isEmpty ? _toGrid(0) : _heroNode.requestFocus()) : widget.onTab(id),
                onMove: (d) => _moveTop(id, d),
              ),
          ],
        ),
        const SizedBox(width: 12),
        _Group(
          children: [
            for (final id in _icons)
              _GoogleIcon(
                id: id,
                label: switch (id) {
                  'search' => 'Search',
                  'settings' => 'Settings',
                  _ => widget.missingLabel ?? 'Permissions needed',
                },
                focusNode: _topNode(id),
                onFocus: () => _focused(_GZone.top),
                onSelect: () => widget.onHeader(id),
                onMove: (d) => _moveTop(id, d),
              ),
          ],
        ),
        const Spacer(),
        _Clock(prefs: widget.prefs),
      ],
    );
  }

  Widget _grid(bool inGrid) {
    final apps = widget.apps;
    // Taller than the screen: the rows below scroll in as the grid moves up.
    return OverflowBox(
      alignment: Alignment.topLeft,
      maxHeight: double.infinity,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _titleH,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AnimatedDefaultTextStyle(
                duration: _anim,
                curve: Curves.easeOutCubic,
                style: inGrid ? TvDS.rowTitleFocused.copyWith(fontSize: 28, fontWeight: FontWeight.w500) : TvDS.rowTitleFocused,
                child: const Text('Your apps'),
              ),
            ),
          ),
        ),
        for (var r = 0; r * _cols < apps.length; r++)
          SizedBox(
            height: _rowExt,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = r * _cols; i < r * _cols + _cols; i++)
                  i < apps.length
                      ? _GoogleTile(
                          key: ValueKey('gtv:$i'),
                          item: apps[i],
                          focusNode: _gridNode(i),
                          onFocus: () => _focused(_GZone.grid, i),
                          onSelect: () => widget.onOpen(apps[i]),
                          onOptions: () => widget.onOptions(apps, i),
                          onMove: (d) => _moveGrid(i, d),
                        )
                      : const SizedBox(width: _cardW),
              ],
            ),
          ),
      ],
      ),
    );
  }
}

/// The hero's words: where it's from, the title, a line about it; focused, also the description
/// and a white "Watch on …" pill (the size change slides, then holds).
class _GoogleHeroText extends StatelessWidget {
  const _GoogleHeroText({required this.item, required this.open, required this.anim});
  final TvItem item;
  final bool open;
  final Duration anim;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final eyebrow = switch (it.kind) {
      TvKind.resume => 'Continue watching${it.appName != null ? ' · ${it.appName}' : ''}',
      _ when it.key.startsWith('cat:') => 'Trending${it.appName != null ? ' · ${it.appName}' : ''}',
      _ => it.appName ?? '',
    };
    final action = switch (it.kind) {
      TvKind.resume => 'Resume${it.appName != null ? ' on ${it.appName}' : ''}',
      _ when it.appName != null => 'Watch on ${it.appName}',
      _ => 'Where to watch',
    };
    return AnimatedSwitcher(
      duration: TvLook.anim(const Duration(milliseconds: 260)),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
      child: Column(
        key: ValueKey(it.key),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow.isNotEmpty) ...[
            Text(eyebrow, style: TvDS.heroMeta.copyWith(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
          ],
          Text(it.title, style: TvDS.heroTitle.copyWith(fontSize: 36, fontWeight: FontWeight.w400, height: 1.1), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (it.meta != null) ...[const SizedBox(height: DS.s8), Text(it.meta!, style: TvDS.heroMeta, maxLines: 1, overflow: TextOverflow.ellipsis)],
          if (it.progress != null) ...[const SizedBox(height: DS.s8), SizedBox(width: 200, child: _Progress(value: it.progress!))],
          AnimatedSize(
            duration: anim,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (it.description != null) ...[
                        const SizedBox(height: DS.s12),
                        Text(it.description!, style: TvDS.heroBody, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: DS.s16),
                      Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: DS.s20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [BoxShadow(color: TvDS.glow, blurRadius: 16, spreadRadius: 1)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(it.kind == TvKind.resume ? Icons.play_arrow_rounded : Icons.open_in_new_rounded, size: 18, color: const Color(0xFF161616)),
                            const SizedBox(width: DS.s8),
                            Text(action, style: TvDS.hint.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF161616))),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeroDots extends StatelessWidget {
  const _HeroDots({required this.count, required this.at});
  final int count, at;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++)
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(color: i == at ? const Color(0xFFFFFFFF) : const Color(0x66FFFFFF), shape: BoxShape.circle),
        ),
    ],
  );
}

/// A see-through pill holding the top bar's tabs or icons.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

class _GoogleTab extends StatelessWidget {
  const _GoogleTab({
    required this.label,
    required this.selected,
    required this.barFocused,
    required this.focusNode,
    required this.onFocus,
    required this.onSelect,
    required this.onMove,
  });
  final String label;
  final bool selected, barFocused;
  final FocusNode focusNode;
  final VoidCallback onFocus, onSelect;
  final bool Function(AxisDirection) onMove;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: TvFocusable(
      focusNode: focusNode,
      onFocus: onFocus,
      onSelect: onSelect,
      onMove: onMove,
      builder: (context, f) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: DS.s16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Focused: white; the selected tab while the bar has focus elsewhere: a soft light pill.
          color: f ? const Color(0xFFFFFFFF) : (selected && barFocused ? const Color(0x33FFFFFF) : const Color(0x00FFFFFF)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TvDS.hint.copyWith(
            fontSize: 15,
            color: f ? const Color(0xFF161616) : (selected ? TvDS.ink : TvDS.inkMuted),
          ),
        ),
      ),
    ),
  );
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon({required this.id, required this.label, required this.focusNode, required this.onFocus, required this.onSelect, required this.onMove});
  final String id, label;
  final FocusNode focusNode;
  final VoidCallback onFocus, onSelect;
  final bool Function(AxisDirection) onMove;

  @override
  Widget build(BuildContext context) {
    final icon = switch (id) {
      'search' => Icons.search_rounded,
      'settings' => Icons.settings_outlined,
      _ => Icons.warning_amber_rounded,
    };
    return Semantics(
      button: true,
      label: label,
      child: TvFocusable(
        focusNode: focusNode,
        onFocus: onFocus,
        onSelect: onSelect,
        onMove: onMove,
        builder: (context, f) => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: f ? const Color(0xFFFFFFFF) : const Color(0x00FFFFFF), shape: BoxShape.circle),
          child: Icon(icon, size: 19, color: f ? const Color(0xFF161616) : (id == 'perms' ? DS.alert : TvDS.ink)),
        ),
      ),
    );
  }
}

/// One app in the grid: its 16:9 banner, or — with none — its icon and name on a card tinted
/// from the name. Focused: white outline + soft glow (no scale) and its name underneath.
class _GoogleTile extends StatelessWidget {
  const _GoogleTile({super.key, required this.item, required this.focusNode, required this.onFocus, required this.onSelect, required this.onOptions, required this.onMove});
  final TvItem item;
  final FocusNode focusNode;
  final VoidCallback onFocus, onSelect, onOptions;
  final bool Function(AxisDirection) onMove;

  static const _w = _GoogleTvState._cardW, _h = _GoogleTvState._cardH, _r = _GoogleTvState._r;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: item.title,
    child: TvFocusable(
      focusNode: focusNode,
      onFocus: onFocus,
      onSelect: onSelect,
      onLongSelect: onOptions,
      onMove: onMove,
      builder: (context, f) => SizedBox(
        width: _w,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: _w,
              height: _h,
              foregroundDecoration: TvRing(on: f, radius: _r),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_r),
                boxShadow: f ? const [BoxShadow(color: TvDS.glow, blurRadius: 22, spreadRadius: 2)] : null,
              ),
              child: _art(context),
            ),
            SizedBox(
              height: _GoogleTvState._labelH,
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: AnimatedOpacity(
                  opacity: f ? 1 : 0,
                  duration: TvLook.anim(Motion.pressIn * 2),
                  child: Text(item.title, style: TvDS.tileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _art(BuildContext context) {
    final a = item.app;
    if (a == null) return _card(const Icon(Icons.apps_rounded, size: 30, color: TvDS.ink), tint: const Color(0xFF2B2F36));
    final ready = TvApps.instance.artNow(a.package);
    Widget view(TvArt? art) => art != null && art.banner
        ? TvRoundImage(image: tvSized(art.image, _w, context), radius: _r, fit: BoxFit.cover)
        : _card(
            art != null
                ? Image(image: tvSized(art.image, 34, context), width: 34, height: 34, gaplessPlayback: true, filterQuality: FilterQuality.low)
                : Text(a.label.isEmpty ? '?' : a.label[0].toUpperCase(), style: TvDS.tileName.copyWith(fontSize: 22)),
          );
    return ready != null ? view(ready) : FutureBuilder<TvArt?>(future: TvApps.instance.art(a.package), builder: (context, s) => view(s.data));
  }

  /// No banner: the icon (or a letter) and the name, on a calm colour from the name.
  Widget _card(Widget icon, {Color? tint}) => DecoratedBox(
    decoration: BoxDecoration(color: tint ?? Color.lerp(tvTint(item.title), const Color(0xFF000000), .35)!, borderRadius: BorderRadius.circular(_r)),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 34, child: Center(child: icon)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s8),
          child: Text(item.title, style: TvDS.tileName.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}
