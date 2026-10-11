import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../folders.dart';
import '../prefs.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';
import 'tv_parts.dart';

enum TvKind { app, resume, program }

/// Anything on the home screen: an app, the show that's playing/paused, or a streaming
/// app's programme (Watch Next / channels, where the TV allows it).
class TvItem {
  const TvItem({
    required this.key,
    required this.kind,
    required this.title,
    required this.package,
    this.app,
    this.appName,
    this.meta,
    this.description,
    this.image,
    this.art,
    this.progress,
    this.intent,
  });
  final String key;
  final TvKind kind;
  final String title;
  final String package;
  final AppEntry? app;
  final String? appName;
  final String? meta; // "S2 · E5 · Low Tide"
  final String? description;
  final String? image; // artwork uri (programmes)
  final MemoryImage? art; // artwork bytes (what's playing)
  final double? progress; // 0–1 watched
  final String? intent; // deep link into the app
}

/// One row: Continue watching (wide), app rows (banners), streaming apps' rows (wide).
class TvRow {
  const TvRow(this.id, this.title, this.items, {this.wide = false});
  final String id;
  final String title;
  final List<TvItem> items;
  final bool wide;

  double get cardW => wide ? TvDS.wideW : TvDS.tileW;
  double get cardH => wide ? TvDS.wideH : TvDS.tileH;
  double get height => TvDS.cardRowTitleH + TvDS.cardRowPad + cardH + TvDS.cardRowGap;
}

/// The TV home screen, cinematic: the focused item's artwork fills the screen behind a
/// big title block, rows sit along the bottom. The remote steers row by row (each row
/// remembers its tile); the focused row always sits at the same spot, rows above slide away.
class TvHome extends StatefulWidget {
  const TvHome({super.key, required this.prefs});
  final Prefs prefs;

  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  List<AppEntry> _apps = const [];
  List<Map> _watchNext = const [], _channels = const [];
  List<TvRow> _rows = const [];
  bool _loaded = false;

  final _v = ScrollController();
  final _h = <String, ScrollController>{};
  final _nodes = <String, FocusNode>{};
  final _col = <String, int>{};
  int _row = 0; // focused row (-1 = top bar)

  TvItem? _hero; // what the title block describes (instant)
  TvItem? _backdrop; // what the big picture shows (settles after a beat, so fast moves don't flicker)
  Timer? _backdropTimer;

  static const _header = ['search', 'inputs', 'settings', 'customise'];

  Prefs get prefs => widget.prefs;
  TvApps get tv => TvApps.instance;

  @override
  void initState() {
    super.initState();
    tv.onAppsChanged = _load;
    tv.onHomePressed = _home;
    tv.onResumed = _loadContent;
    tv.media.addListener(_regroup);
    prefs.addListener(_regroup);
    _load();
  }

  @override
  void dispose() {
    tv.media.removeListener(_regroup);
    prefs.removeListener(_regroup);
    _backdropTimer?.cancel();
    _v.dispose();
    for (final c in _h.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final apps = await tv.list();
    if (!mounted) return;
    _apps = apps;
    _regroup();
    await _loadContent();
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus(_rows.isEmpty ? -1 : 0, 0));
    }
  }

  Future<void> _loadContent() async {
    final results = await Future.wait([tv.watchNext(), tv.channels()]);
    await tv.refreshMedia();
    if (!mounted) return;
    _watchNext = results[0];
    _channels = results[1];
    _regroup();
  }

  // ---- Rows ----------------------------------------------------------------

  void _regroup() {
    if (!mounted) return;
    final hidden = prefs.hidden.toSet();
    final visible = [
      for (final a in _apps)
        if (!hidden.contains(a.package)) a,
    ];
    final byPkg = {for (final a in visible) a.package: a};
    String appName(String pkg) => byPkg[pkg]?.label ?? '';
    TvItem appItem(AppEntry a) => TvItem(key: a.package, kind: TvKind.app, title: a.label, package: a.package, app: a, appName: a.label);

    // Continue watching: what's playing / paused right now, then the apps' Watch Next.
    final cont = <TvItem>[];
    final m = tv.media.value;
    if (m != null && m['active'] == true && m['title'] != null) {
      final dur = (m['duration'] as num?)?.toDouble() ?? 0;
      final pos = (m['position'] as num?)?.toDouble() ?? 0;
      final art = m['art'];
      cont.add(
        TvItem(
          key: 'now:${m['package']}',
          kind: TvKind.resume,
          title: m['title'] as String,
          package: m['package'] as String? ?? '',
          appName: m['app'] as String?,
          meta: _joinMeta([m['artist'] as String?, if (dur > 0) _left(dur - pos)]),
          art: art is Uint8List ? MemoryImage(art) : null,
          progress: dur > 0 ? (pos / dur).clamp(0, 1) : null,
        ),
      );
    }
    for (final p in _watchNext) {
      final item = _program(p, appName(p['package'] as String? ?? ''));
      if (item != null && !cont.any((c) => c.title == item.title)) cont.add(item);
    }

    var fav = [for (final p in prefs.favourites) ?byPkg[p]];
    final groups = groupApps(visible, prefs.folderOverrides, order: prefs.folderOrder);
    if (fav.isEmpty) {
      fav = [
        for (final (f, list) in groups)
          if (f.id == 'media') ...list,
      ].take(8).toList();
    }
    final recents = [for (final p in prefs.tvRecents) ?byPkg[p]].take(10).toList();

    setState(() {
      _rows = [
        if (cont.isNotEmpty) TvRow('continue', 'Continue watching', cont, wide: true),
        if (fav.isNotEmpty) TvRow('fav', 'Your apps', [for (final a in fav) appItem(a)]),
        if (recents.length > 1) TvRow('recent', 'Jump back in', [for (final a in recents) appItem(a)]),
        for (final c in _channels)
          if ((c['programs'] as List?)?.isNotEmpty ?? false)
            TvRow('ch:${c['id']}', '${c['name'] ?? appName(c['package'] as String? ?? '')}', [
              for (final p in (c['programs'] as List).cast<Map>()) ?_program(p, appName(c['package'] as String? ?? '')),
            ], wide: true),
        for (final (f, list) in groups) TvRow(f.id, prefs.folderNames[f.id] ?? f.name, [for (final a in list) appItem(a)]),
      ];
    });
    // The title block follows focus; keep it pointing at a live item.
    if (_hero == null && _rows.isNotEmpty) _show(_rows.first.items.first, now: true);
  }

  TvItem? _program(Map p, String appName) {
    final title = p['title'] as String?;
    if (title == null) return null;
    final dur = (p['duration'] as num?)?.toDouble() ?? 0;
    final pos = (p['position'] as num?)?.toDouble() ?? 0;
    final se = [if (p['season'] != null) 'S${p['season']}', if (p['episode'] != null) 'E${p['episode']}'].join(' · ');
    return TvItem(
      key: 'p:${p['id']}',
      kind: TvKind.program,
      title: title,
      package: p['package'] as String? ?? '',
      appName: appName,
      meta: _joinMeta([se.isEmpty ? null : se, p['episodeTitle'] as String?, if (dur > 0 && pos > 0) _left(dur - pos)]),
      description: p['description'] as String?,
      image: (p['poster'] ?? p['thumbnail']) as String?,
      progress: dur > 0 && pos > 0 ? (pos / dur).clamp(0, 1) : null,
      intent: p['intent'] as String?,
    );
  }

  static String? _joinMeta(List<String?> parts) {
    final p = parts.whereType<String>().where((s) => s.isNotEmpty).toList();
    return p.isEmpty ? null : p.join(' · ');
  }

  static String _left(double ms) {
    final min = (ms / 60000).round();
    return min >= 60 ? '${min ~/ 60} h ${min % 60} min left' : '$min min left';
  }

  void _home() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _focus(_rows.isEmpty ? -1 : 0, 0);
  }

  // ---- Focus ---------------------------------------------------------------

  String _rowId(int r) => r < 0 ? 'header' : _rows[r].id;
  int _len(int r) => r < 0 ? _header.length : _rows[r].items.length;
  String _key(int r, int i) => r < 0 ? 'h:${_header[i]}' : '${_rows[r].id}:${_rows[r].items[i].key}';
  FocusNode _node(int r, int i) => _nodes.putIfAbsent(_key(r, i), () => FocusNode(debugLabel: _key(r, i)));

  void _focus(int r, int i) {
    if (r >= _rows.length || _len(r) == 0) return;
    _node(r, i.clamp(0, _len(r) - 1)).requestFocus();
  }

  bool _move(int r, int i, AxisDirection d) {
    switch (d) {
      case AxisDirection.left when i > 0:
        _focus(r, i - 1);
      case AxisDirection.right when i < _len(r) - 1:
        _focus(r, i + 1);
      case AxisDirection.up when r > -1:
        _focus(r - 1, _col[_rowId(r - 1)] ?? 0);
      case AxisDirection.down when r < _rows.length - 1:
        _focus(r + 1, _col[_rowId(r + 1)] ?? 0);
      default:
        return false;
    }
    return true;
  }

  void _onFocus(int r, int i) {
    _col[_rowId(r)] = i;
    if (_row != r) setState(() => _row = r);
    if (r >= 0) _show(_rows[r].items[i]);
    const dur = Duration(milliseconds: 420);
    const curve = Curves.easeOutCubic;
    // Vertical: the focused row slides to the top of the rows area; rows above slide out.
    if (_v.hasClients) {
      var y = 0.0;
      for (var k = 0; k < r; k++) {
        y += _rows[k].height;
      }
      _v.animateTo(y.clamp(0.0, _v.position.maxScrollExtent), duration: dur, curve: curve);
    }
    // Horizontal: one card peeks on the left so you can tell there's more.
    final h = r < 0 ? null : _h[_rowId(r)];
    if (h != null && h.hasClients) {
      final row = _rows[r];
      final x = ((i - 1) * (row.cardW + TvDS.gap)).clamp(0.0, h.position.maxScrollExtent);
      h.animateTo(x, duration: dur, curve: curve);
    }
  }

  /// Title block switches at once; the big picture waits until focus rests a moment.
  void _show(TvItem item, {bool now = false}) {
    setState(() => _hero = item);
    _backdropTimer?.cancel();
    if (now) {
      _backdrop = item;
    } else {
      _backdropTimer = Timer(const Duration(milliseconds: 260), () {
        if (mounted) setState(() => _backdrop = item);
      });
    }
  }

  // ---- Actions -------------------------------------------------------------

  void _open(TvItem item) {
    HapticFeedback.selectionClick();
    if (item.package.isNotEmpty) prefs.noteTvLaunch(item.package);
    switch (item.kind) {
      case TvKind.app:
        tv.launch(item.package);
      case TvKind.resume:
        tv.mediaOpen();
      case TvKind.program:
        tv.openProgram(item.intent, item.package);
    }
  }

  void _options(TvRow row, int i) {
    final item = row.items[i];
    final a = item.app;
    if (a == null) {
      showTvPanel(
        context,
        title: item.title,
        actions: [
          TvAction(Icons.play_arrow_rounded, item.kind == TvKind.resume ? 'Resume' : 'Watch', () => _open(item)),
          if (item.package.isNotEmpty) TvAction(Icons.apps_rounded, 'Open ${item.appName ?? 'app'}', () => tv.launch(item.package)),
          if (item.package.isNotEmpty) TvAction(Icons.info_outline_rounded, 'App info', () => tv.appInfo(item.package)),
        ],
      );
      return;
    }
    final fav = prefs.favourites.contains(a.package);
    void move(int by) {
      final list = [...prefs.favourites];
      final from = list.indexOf(a.package);
      final to = (from + by).clamp(0, list.length - 1);
      if (from < 0 || to == from) return;
      list.insert(to, list.removeAt(from));
      prefs.setFavourites(list);
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus(_rows.indexWhere((r) => r.id == 'fav'), to));
    }

    final favRow = _rows.where((r) => r.id == 'fav').firstOrNull;
    showTvPanel(
      context,
      title: a.label,
      leading: TvAppArt(app: a, width: 128),
      actions: [
        TvAction(Icons.open_in_new_rounded, 'Open', () => _open(item)),
        if (fav) ...[
          if (row.id == 'fav' && i > 0) TvAction(Icons.arrow_back_rounded, 'Move left', () => move(-1)),
          if (row.id == 'fav' && i < row.items.length - 1) TvAction(Icons.arrow_forward_rounded, 'Move right', () => move(1)),
          TvAction(Icons.star_outline_rounded, 'Remove from Your apps', () => prefs.toggleFavourite(a.package)),
        ] else if (!prefs.favouritesFull)
          TvAction(Icons.star_rounded, 'Add to Your apps', () async {
            // The starter row (Watch & Listen) becomes real picks the first time you edit it.
            if (prefs.favourites.isEmpty && favRow != null) {
              await prefs.setFavourites([for (final x in favRow.items) x.package]);
            }
            await prefs.toggleFavourite(a.package);
          }),
        TvAction(Icons.visibility_off_outlined, 'Hide', () => prefs.toggleHidden(a.package)),
        TvAction(Icons.info_outline_rounded, 'App info', () => tv.appInfo(a.package)),
        if (!a.system) TvAction(Icons.delete_outline_rounded, 'Uninstall', () => tv.uninstall(a.package), danger: true),
      ],
    );
  }

  void _headerAction(String id) => switch (id) {
    'search' => Navigator.of(context).push(
      tvFade(
        TvSearch(
          apps: [
            for (final a in _apps)
              if (!prefs.hidden.contains(a.package)) a,
          ],
          onLaunch: (a) => _open(TvItem(key: a.package, kind: TvKind.app, title: a.label, package: a.package, app: a)),
        ),
      ),
    ),
    'inputs' => tv.openInputs(),
    'settings' => tv.openSettings(),
    _ => _customise(),
  };

  void _customise() {
    final hidden = [
      for (final a in _apps)
        if (prefs.hidden.contains(a.package)) a,
    ];
    final mediaOff = tv.media.value?['granted'] == false;
    showTvPanel(
      context,
      title: 'One Launcher TV',
      actions: [
        if (mediaOff) TvAction(Icons.play_circle_outline_rounded, 'Show what’s playing', tv.openNotificationAccess),
        for (final a in hidden) TvAction(Icons.visibility_outlined, 'Show ${a.label}', () => prefs.toggleHidden(a.package)),
        TvAction(Icons.home_outlined, 'Make this the home screen', tv.openHomeSettings),
      ],
    );
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // it's the home screen: Back jumps to the first card instead
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _focus(_rows.isEmpty ? -1 : 0, 0);
      },
      child: Scaffold(
        backgroundColor: TvDS.canvas,
        body: LayoutBuilder(
          builder: (context, c) {
            final rowsTop = c.maxHeight * TvDS.rowsTop;
            return Stack(
              fit: StackFit.expand,
              children: [
                // ---- The big picture, fading into the canvas on the left and bottom ----
                Positioned(
                  top: 0,
                  right: 0,
                  width: c.maxWidth * .74,
                  height: c.maxHeight * .8,
                  child: _Backdrop(item: _backdrop),
                ),
                const _Scrims(),

                // ---- Title block: what's focused ----
                Positioned(
                  left: TvDS.safe.left,
                  top: TvDS.heroTop,
                  width: TvDS.heroW,
                  height: rowsTop - TvDS.heroTop - DS.s12,
                  child: _HeroInfo(item: _hero, rowTitle: _row >= 0 && _row < _rows.length ? _rows[_row].title : null),
                ),

                // ---- Rows ----
                Positioned(
                  top: rowsTop,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRect(
                    child: SingleChildScrollView(
                      controller: _v,
                      physics: const ClampingScrollPhysics(),
                      clipBehavior: Clip.none,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (r, row) in _rows.indexed) _buildRow(r, row),
                          // Room for the last row to reach the top of this area.
                          SizedBox(height: math.max(0, c.maxHeight - rowsTop - (_rows.lastOrNull?.height ?? 0))),
                        ],
                      ),
                    ),
                  ),
                ),

                // ---- Top bar ----
                Positioned(
                  top: TvDS.safe.top,
                  left: TvDS.safe.left,
                  right: TvDS.safe.right,
                  child: _TopBar(
                    prefs: prefs,
                    buttons: [
                      for (final (i, id) in _header.indexed)
                        _TopButton(
                          id: id,
                          focusNode: _node(-1, i),
                          onSelect: () => _headerAction(id),
                          onMove: (d) => _move(-1, i, d),
                          onFocus: () => _onFocus(-1, i),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRow(int r, TvRow row) {
    final h = _h.putIfAbsent(row.id, ScrollController.new);
    final focusedRow = _row == r;
    return SizedBox(
      height: row.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(left: TvDS.safe.left),
            child: SizedBox(
              height: TvDS.cardRowTitleH,
              child: AnimatedDefaultTextStyle(
                duration: Motion.snapDuration,
                curve: Motion.settle,
                style: focusedRow ? TvDS.rowTitleFocused : TvDS.rowTitle,
                child: Text(row.title),
              ),
            ),
          ),
          const SizedBox(height: TvDS.cardRowPad),
          SizedBox(
            height: row.cardH,
            child: SingleChildScrollView(
              controller: h,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none, // a focused card grows past the row's box
              padding: EdgeInsets.symmetric(horizontal: TvDS.safe.left),
              child: Row(
                children: [
                  for (final (i, item) in row.items.indexed) ...[
                    if (i > 0) const SizedBox(width: TvDS.gap),
                    _Card(
                      key: ValueKey(_key(r, i)),
                      item: item,
                      width: row.cardW,
                      height: row.cardH,
                      focusNode: _node(r, i),
                      onSelect: () => _open(item),
                      onOptions: () => _options(row, i),
                      onMove: (d) => _move(r, i, d),
                      onFocus: () => _onFocus(r, i),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Backdrop ------------------------------------------------------------------

/// Full-bleed artwork for the focused item. Programmes show their poster; apps show their
/// banner as a soft, out-of-focus wash (drawn tiny and stretched — a free blur).
/// Each new picture fades in while settling from a slight zoom.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.item});
  final TvItem? item;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 650),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey(it?.key), child: it == null ? const SizedBox.expand() : _picture(it)),
    );
  }

  Widget _picture(TvItem it) {
    Widget settle(Widget child) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.06, end: 1),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeOutCubic,
      builder: (context, s, child) => Transform.scale(scale: s, alignment: Alignment.topRight, child: child),
      child: child,
    );
    if (it.art != null) return settle(Image(image: it.art!, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true));
    if (it.image != null) {
      final ready = TvApps.instance.imageNow(it.image!);
      return FutureBuilder<MemoryImage?>(
        future: ready != null ? Future.value(ready) : TvApps.instance.image(it.image!, width: 960),
        builder: (context, s) =>
            s.data == null ? _wash(it) : settle(Image(image: s.data!, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true)),
      );
    }
    // Apps: their banner, pre-blurred on the TV into a soft wash.
    if (it.kind == TvKind.app) {
      Widget wash(MemoryImage img) => settle(
        Opacity(
          opacity: .75,
          child: Image(image: img, fit: BoxFit.cover, filterQuality: FilterQuality.medium, gaplessPlayback: true),
        ),
      );
      final ready = TvApps.instance.backdropNow(it.package);
      if (ready != null) return wash(ready);
      return FutureBuilder<MemoryImage?>(future: TvApps.instance.backdrop(it.package), builder: (context, s) => s.data == null ? _wash(it) : wash(s.data!));
    }
    return _wash(it);
  }

  /// No artwork: a soft glow in a colour picked from the title, so each item still feels distinct.
  Widget _wash(TvItem it) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(center: const Alignment(.4, -.3), radius: 1.1, colors: [tvTint(it.title).withValues(alpha: .55), Colors.transparent]),
    ),
  );
}

/// A calm colour from a name (same name → same colour): used where there's no artwork.
Color tvTint(String name) => HSLColor.fromAHSL(1, (name.hashCode % 360).abs().toDouble(), .38, .42).toColor();

/// Darkens the picture into the canvas: from the left (behind the title) and the bottom
/// (behind the rows), plus a light veil at the top for the top bar.
class _Scrims extends StatelessWidget {
  const _Scrims();

  @override
  Widget build(BuildContext context) {
    final c = TvDS.canvas;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c, c.withValues(alpha: .92), c.withValues(alpha: .35), c.withValues(alpha: 0)], stops: const [0, .3, .55, .75]),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [TvDS.scrim.withValues(alpha: .35), c.withValues(alpha: 0), c.withValues(alpha: .85), c],
                stops: const [0, .2, .58, .74],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Title block ---------------------------------------------------------------

class _HeroInfo extends StatelessWidget {
  const _HeroInfo({required this.item, required this.rowTitle});
  final TvItem? item;
  final String? rowTitle;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: it == null ? const SizedBox.shrink() : KeyedSubtree(key: ValueKey(it.key), child: _content(it)),
    );
  }

  Widget _content(TvItem it) {
    final eyebrow = switch (it.kind) {
      TvKind.resume => 'CONTINUE WATCHING${it.appName != null ? ' · ${it.appName!.toUpperCase()}' : ''}',
      TvKind.program => (it.appName ?? '').toUpperCase(),
      TvKind.app => (rowTitle ?? 'App').toUpperCase(),
    };
    final action = switch (it.kind) {
      TvKind.resume => 'Resume',
      TvKind.program => (it.progress ?? 0) > 0 ? 'Resume' : 'Watch',
      TvKind.app => 'Open',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow.isNotEmpty) ...[Text(eyebrow, style: TvDS.heroEyebrow, maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: DS.s8)],
        Text(it.title, style: TvDS.heroTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (it.meta != null) ...[const SizedBox(height: DS.s8), Text(it.meta!, style: TvDS.heroMeta, maxLines: 1, overflow: TextOverflow.ellipsis)],
        if (it.progress != null) ...[const SizedBox(height: DS.s12), SizedBox(width: 220, child: _Progress(value: it.progress!))],
        if (it.description != null) ...[
          const SizedBox(height: DS.s12),
          Text(it.description!, style: TvDS.heroBody, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: DS.s16),
        Row(
          children: [
            _Keycap('OK'),
            const SizedBox(width: DS.s8),
            Text(action, style: TvDS.heroMeta.copyWith(fontSize: 13)),
            const SizedBox(width: DS.s20),
            _Keycap('Hold OK'),
            const SizedBox(width: DS.s8),
            Text('More', style: TvDS.heroMeta.copyWith(fontSize: 13)),
          ],
        ),
      ],
    );
  }
}

/// A remote button drawn as a little key, for the hints under the title.
class _Keycap extends StatelessWidget {
  const _Keycap(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: TvDS.inkMuted),
    ),
    child: Text(label, style: TvDS.keycap),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: TvDS.progressH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: TvDS.line),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: ColoredBox(color: DS.hero),
          ),
        ],
      ),
    ),
  );
}

// ---- Top bar -------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.prefs, required this.buttons});
  final Prefs prefs;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, b) in buttons.indexed) ...[if (i > 0) const SizedBox(width: DS.s8), b],
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(top: DS.s8),
          child: _Clock(prefs: prefs),
        ),
      ],
    );
  }
}

/// Search is a pill with a label (the thing people use most); the rest are icons that say
/// what they are when focused.
class _TopButton extends StatelessWidget {
  const _TopButton({required this.id, required this.focusNode, required this.onSelect, this.onMove, this.onFocus});
  final String id;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (id) {
      'search' => (Icons.search_rounded, 'Search'),
      'inputs' => (Icons.input_rounded, 'Inputs'),
      'settings' => (Icons.settings_outlined, 'Settings'),
      _ => (Icons.tune_rounded, 'Customise'),
    };
    final pill = id == 'search';
    return Semantics(
      button: true,
      label: label,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: f ? TvDS.focusScale : 1,
              duration: Motion.popDuration,
              curve: Motion.pop,
              child: AnimatedContainer(
                duration: Motion.pressIn * 2,
                height: 40,
                width: pill ? null : 40,
                padding: pill ? const EdgeInsets.symmetric(horizontal: DS.s16) : EdgeInsets.zero,
                decoration: BoxDecoration(color: f ? TvDS.surfaceFocused : TvDS.surface, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 22, color: f ? DS.ink : TvDS.ink),
                    if (pill) ...[const SizedBox(width: DS.s8), Text(label, style: TvDS.hint.copyWith(fontSize: 15, color: f ? DS.ink : TvDS.ink))],
                  ],
                ),
              ),
            ),
            // Label hangs under the icon without widening it (keeps the icons evenly spaced).
            if (!pill)
              SizedBox(
                width: 40,
                height: 26,
                child: OverflowBox(
                  maxWidth: 120,
                  alignment: Alignment.bottomCenter,
                  child: AnimatedOpacity(
                    opacity: f ? 1 : 0,
                    duration: Motion.pressIn * 2,
                    child: Text(label, style: TvDS.hint, maxLines: 1, softWrap: false),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small time + date, top right (the big picture is the star now).
class _Clock extends StatefulWidget {
  const _Clock({required this.prefs});
  final Prefs prefs;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _t;
  DateTime _now = DateTime.now();
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
    _tick();
  }

  // Wake on the next minute (no per-second rebuilds).
  void _tick() {
    final now = DateTime.now();
    _t = Timer(Duration(seconds: 60 - now.second, milliseconds: -now.millisecond + 20), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _tick();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.alwaysUse24HourFormatOf(context) ? _now.hour : (_now.hour % 12 == 0 ? 12 : _now.hour % 12);
    final time = '${h.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return ListenableBuilder(
      listenable: widget.prefs,
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('${_days[_now.weekday - 1]} ${_now.day} ${_months[_now.month - 1]}', style: TvDS.date.copyWith(fontSize: 15)),
          const SizedBox(width: DS.s12),
          Text(time, style: TvDS.topClock.copyWith(fontSize: 22)),
        ],
      ),
    );
  }
}

// ---- Cards ---------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({
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
    return Semantics(
      button: true,
      label: item.title,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onLongSelect: onOptions,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => AnimatedScale(
          scale: f ? TvDS.focusScaleCard : 1,
          duration: Motion.popDuration,
          curve: Motion.pop,
          child: AnimatedContainer(
            duration: Motion.pressIn * 2,
            width: width,
            height: height,
            // Ring + glow only on the focused card (one blur on screen at a time).
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
              child: item.app != null ? TvAppArt(app: item.app!, width: width) : _ProgramArt(item: item, width: width, height: height),
            ),
          ),
        ),
      ),
    );
  }
}

/// A show / film card: its still (or a tinted title card), app name, progress along the bottom.
class _ProgramArt extends StatelessWidget {
  const _ProgramArt({required this.item, required this.width, required this.height});
  final TvItem item;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    Widget picture;
    if (item.art != null) {
      picture = Image(image: item.art!, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (item.image != null) {
      final ready = TvApps.instance.imageNow(item.image!);
      picture = FutureBuilder<MemoryImage?>(
        future: ready != null ? Future.value(ready) : TvApps.instance.image(item.image!),
        builder: (context, s) => s.data == null ? _titleCard() : Image(image: s.data!, fit: BoxFit.cover, gaplessPlayback: true),
      );
    } else {
      picture = _titleCard();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        picture,
        // Bottom shade so the name and progress read on any picture.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB3000000)], stops: [.45, 1]),
          ),
        ),
        Positioned(
          left: DS.s12,
          right: DS.s12,
          bottom: item.progress != null ? DS.s16 : DS.s12,
          child: Text(
            item.appName ?? '',
            style: TvDS.tileName.copyWith(color: TvDS.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (item.progress != null)
          Positioned(
            left: DS.s12,
            right: DS.s12,
            bottom: DS.s8,
            child: _Progress(value: item.progress!),
          ),
      ],
    );
  }

  /// No still: the title set large on a tint from its name — still looks intentional.
  Widget _titleCard() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tvTint(item.title), TvDS.canvas]),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(DS.s12, DS.s12, DS.s12, 34),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(item.title, style: TvDS.panelTitle.copyWith(fontSize: 20, height: 1.1), maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    ),
  );
}
