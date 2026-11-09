import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_lock.dart';
import '../apps.dart';
import '../prefs.dart';
import '../search.dart';
import '../ui/perf.dart';
import 'pixel_icon.dart';
import 'pixel_model.dart';
import 'pixel_popup.dart';

/// Pixel Launcher's all-apps sheet: search pill on top, a row of suggested apps, then the
/// grid of all apps (A–Z with a letter scroller, or by recent / most used), Personal / Work
/// tabs when there are work apps. The home owns the slide-up; this fills the screen.
class PixelDrawer extends StatefulWidget {
  const PixelDrawer({super.key, required this.prefs, required this.apps, required this.onClose, this.onDragStart, this.searchFocus, this.morph});
  final Prefs prefs;

  /// All launchable apps; hidden ones are filtered here.
  final List<AppEntry> apps;

  /// Swipe down at the top of the list, or back.
  final VoidCallback onClose;

  /// An icon's long-press drag began: the home slides the drawer away and the drag goes on there.
  final VoidCallback? onDragStart;

  /// Home focuses this to open with the keyboard.
  final FocusNode? searchFocus;

  /// The drawer's 0…1 opening while home's Google pill flies into the search field: the field
  /// shows only once it's fully open (the flying pill stands in until then).
  final Animation<double>? morph;

  @override
  State<PixelDrawer> createState() => PixelDrawerState();
}

class PixelDrawerState extends State<PixelDrawer> {
  final _scroll = ScrollController();
  final _query = TextEditingController();
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.searchFocus ?? (_ownFocus ??= FocusNode());
  int _tab = 0; // 0 personal, 1 work
  double _pull = 0;
  bool _pulled = false;
  String? _bubble; // letter shown while dragging the scroller
  double _bubbleY = 0;

  PixelSettings get _s => PixelSettings.of(widget.prefs);

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _query.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  /// The drawer just became visible: back to the top, and the keyboard if the setting is on.
  void opened() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _pulled = false;
    if (_s.keyboardOnOpen) _focus.requestFocus();
  }

  /// Back to rest: search cleared, list at the top.
  void reset() {
    _query.clear();
    _focus.unfocus();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (_tab != 0) setState(() => _tab = 0);
  }

  // ---- data ----

  List<AppEntry> get _visible {
    final hidden = widget.prefs.hidden.toSet();
    return [for (final a in widget.apps) if (!hidden.contains(a.package)) a];
  }

  bool get _hasWork => _visible.any((a) => a.work);

  static String _letter(AppEntry a) {
    final c = a.label.trim().isEmpty ? '#' : a.label.trim()[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
  }

  List<AppEntry> _sorted(List<AppEntry> apps) {
    final list = [...apps];
    int az(AppEntry a, AppEntry b) => a.label.toLowerCase().compareTo(b.label.toLowerCase());
    switch (_s.drawerSort) {
      case 'recent':
        final last = widget.prefs.lastLaunch;
        list.sort((a, b) {
          final c = (last[b.package] ?? 0).compareTo(last[a.package] ?? 0);
          return c != 0 ? c : az(a, b);
        });
      case 'most':
        final n = widget.prefs.launchCounts;
        list.sort((a, b) {
          final c = (n[b.package] ?? 0).compareTo(n[a.package] ?? 0);
          return c != 0 ? c : az(a, b);
        });
      default:
        list.sort(az);
    }
    return list;
  }

  /// Five suggestions: latest launches, then pinned favourites.
  List<AppEntry> _suggested(List<AppEntry> pool) {
    final by = {for (final a in pool) a.package: a};
    final last = widget.prefs.lastLaunch;
    final recent = last.entries.where((e) => by.containsKey(e.key)).toList()..sort((a, b) => b.value.compareTo(a.value));
    final out = <AppEntry>[for (final e in recent) by[e.key]!];
    for (final p in widget.prefs.favourites) {
      final a = by[p];
      if (a != null && !out.contains(a)) out.add(a);
    }
    return out.take(5).toList();
  }

  // ---- actions ----

  Future<void> _launch(AppEntry app, [BuildContext? from]) async {
    if (!await AppLock.of(widget.prefs).gate(app.package)) return;
    if (from != null && from.mounted) Apps.instance.markLaunchFrom(from);
    widget.prefs.recordLaunch(app.package);
    await Apps.instance.launch(app.package);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) reset();
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      _pull = 0;
    } else if (n is OverscrollNotification && n.metrics.pixels <= n.metrics.minScrollExtent && n.overscroll < 0 && n.dragDetails != null) {
      _pull += -n.overscroll;
      if (_pull > 60 && !_pulled) {
        _pulled = true;
        widget.onClose();
      }
    } else if (n is ScrollEndNotification) {
      _pull = 0;
      _pulled = false;
    }
    return false;
  }

  // ---- layout ----

  double _icon(double cellW) => math.min(52 * _s.iconScale, cellW * .8);
  double _rowExtent(double icon) => icon + (_s.drawerLabels ? 6 + 16 : 0) + 27;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final searching = _query.text.trim().isNotEmpty;
    return PopScope(
      canPop: !(searching || _focus.hasFocus),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) reset();
      },
      child: Padding(
        padding: EdgeInsets.only(top: math.max(40.0, pad.top + 12)),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: _Frost(
            child: Column(
              children: [
                const SizedBox(height: 14),
                Container(width: 32, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: _morphed(_SearchPill(controller: _query, focus: _focus, onSubmit: _submit)),
                ),
                Expanded(child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: searching ? _results(pad) : _grid(pad))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _morphed(Widget field) {
    final m = widget.morph;
    if (m == null) return field;
    return AnimatedBuilder(animation: m, builder: (context, child) => Opacity(opacity: m.value >= 1 ? 1 : 0, child: child), child: field);
  }

  void _submit(String q) {
    final r = searchApps(widget.apps, q);
    if (r.isNotEmpty) _launch(r.first);
  }

  Widget _results(EdgeInsets pad) {
    final cs = Theme.of(context).colorScheme;
    final q = _query.text.trim();
    final apps = searchApps(widget.apps, q);
    Widget row(Widget lead, String text, VoidCallback onTap, {Key? key}) => InkWell(
      key: key,
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              SizedBox.square(dimension: 40, child: Center(child: lead)),
              const SizedBox(width: 16),
              Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: cs.onSurface))),
            ],
          ),
        ),
      ),
    );
    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: pad.bottom + 24),
      children: [
        for (final a in apps)
          Builder(
            builder: (ctx) => row(
              PixelIcon(app: a, size: 40, label: false, shape: _s.iconShape),
              a.label,
              () => _launch(a, ctx),
              key: ValueKey('result:${a.package}'),
            ),
          ),
        if (apps.isNotEmpty) Divider(height: 16, indent: 24, endIndent: 24, color: cs.outlineVariant),
        row(Icon(Icons.search_rounded, color: cs.onSurfaceVariant), 'Search the web for “$q”', () => Apps.instance.webSearch(q), key: const ValueKey('web')),
        row(Icon(Icons.play_arrow_rounded, color: cs.onSurfaceVariant, size: 28), 'Search Google Play for “$q”', () => Apps.instance.playSearch(q), key: const ValueKey('play')),
      ],
    );
  }

  Widget _grid(EdgeInsets pad) {
    final cs = Theme.of(context).colorScheme;
    final s = _s;
    final all = _visible;
    final pool = _hasWork ? [for (final a in all) if (a.work == (_tab == 1)) a] : all;
    final apps = _sorted(pool);
    final suggested = s.suggestions && _tab == 0 ? _suggested(pool) : const <AppEntry>[];
    final scroller = s.letterScroller && s.drawerSort == 'az';

    return LayoutBuilder(
      builder: (context, box) {
        const gutter = 8.0;
        final cols = s.drawerCols;
        final cellW = (box.maxWidth - 2 * gutter) / cols;
        final icon = _icon(cellW);
        final extent = _rowExtent(icon);
        final showTabs = _hasWork;
        const tabsH = 30.0 + 14 + 10;
        final sugH = (suggested.isEmpty ? 0.0 : extent + 8) + (showTabs ? tabsH : 0);

        // First row of every letter, for the scroller.
        final firstRow = <String, int>{};
        for (var i = 0; i < apps.length; i++) {
          firstRow.putIfAbsent(_letter(apps[i]), () => i ~/ cols);
        }
        final letters = firstRow.keys.toList();

        void jump(double dy) {
          if (letters.isEmpty || !_scroll.hasClients) return;
          final f = (dy / box.maxHeight).clamp(0.0, .9999);
          final l = letters[(f * letters.length).floor()];
          final target = sugH + firstRow[l]! * extent;
          _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
          setState(() {
            _bubble = l;
            _bubbleY = dy;
          });
          HapticFeedback.selectionClick();
        }

        return Stack(
          children: [
            RawScrollbar(
              controller: _scroll,
              thickness: 4,
              radius: const Radius.circular(2),
              crossAxisMargin: 2,
              minThumbLength: 48,
              thumbColor: Colors.white.withValues(alpha: .35),
              child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                if (suggested.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
                      child: SizedBox(
                        height: extent,
                        child: Row(
                          key: const ValueKey('suggestions'),
                          children: [
                            for (final a in suggested)
                              SizedBox(width: (box.maxWidth - 2 * gutter) / 5, child: _Cell(key: ValueKey('sug:${a.package}'), app: a, icon: icon, drawer: this)),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (showTabs) SliverToBoxAdapter(child: _Tabs(tab: _tab, onTab: (t) => setState(() => _tab = t))),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, pad.bottom + 24),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate((c, i) => _Cell(key: ValueKey('app:${apps[i].package}'), app: apps[i], icon: icon, drawer: this), childCount: apps.length),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: extent),
                  ),
                ),
              ],
            ),
            ),
            if (scroller && letters.length > 1)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 32,
                child: GestureDetector(
                  key: const ValueKey('scroller'),
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (d) => jump(d.localPosition.dy),
                  onVerticalDragUpdate: (d) => jump(d.localPosition.dy),
                  onVerticalDragEnd: (_) => setState(() => _bubble = null),
                  onVerticalDragCancel: () => setState(() => _bubble = null),
                  onTapDown: (d) => jump(d.localPosition.dy),
                  onTapUp: (_) => setState(() => _bubble = null),
                ),
              ),
            if (_bubble != null)
              Positioned(
                right: 44,
                top: (_bubbleY - 40).clamp(0.0, math.max(0.0, box.maxHeight - 80)),
                child: IgnorePointer(
                  child: Container(
                    width: 80,
                    height: 80,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                    child: Text(_bubble!, style: TextStyle(fontSize: 40, color: cs.onPrimaryContainer, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The sheet's frosted background: translucent grey over a blurred wallpaper (no blur in lite).
class _Frost extends StatelessWidget {
  const _Frost({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    return ValueListenableBuilder<bool>(
      valueListenable: Perf.lite,
      builder: (context, lite, _) {
        final base = dark ? const Color(0xFF1E1E1E) : cs.surfaceContainer;
        final box = ColoredBox(color: base.withValues(alpha: lite ? .96 : .82), child: child);
        if (lite) return box;
        return BackdropFilter(filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), child: box);
      },
    );
  }
}

/// No box and no icon: just a big hint ("Search your phone and more").
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.controller, required this.focus, required this.onSubmit});
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('drawerSearch'),
              controller: controller,
              focusNode: focus,
              onSubmitted: onSubmit,
              textInputAction: TextInputAction.go,
              style: TextStyle(fontSize: 22, color: cs.onSurface),
              cursorColor: cs.onSurface,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search your phone and more',
                hintStyle: TextStyle(fontSize: 22, color: cs.onSurface.withValues(alpha: .7)),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(onTap: controller.clear, child: Icon(Icons.close_rounded, color: cs.onSurfaceVariant, size: 22)),
        ],
      ),
    );
  }
}

/// Personal / Work: two equal pills, selected = solid, other = 12% tint. No icons.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onTab});
  final int tab;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final onBg = dark ? Colors.white : const Color(0xFF1B1B1B);
    final onFg = dark ? Colors.black : Colors.white;
    Widget t(int i, String label) {
      final on = tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => onTab(i),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 30,
            decoration: BoxDecoration(color: on ? onBg : onBg.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: on ? onFg : onBg)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(children: [t(0, 'Personal'), const SizedBox(width: 14), t(1, 'Work')]),
    );
  }
}

/// One app: tap launches, long-press shows the popup and starts a drag onto the home.
class _Cell extends StatefulWidget {
  const _Cell({super.key, required this.app, required this.icon, required this.drawer});
  final AppEntry app;
  final double icon;
  final PixelDrawerState drawer;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  PixelPopupHandle? _popup;
  Offset? _origin;
  final _iconKey = GlobalKey();

  void _closePopup() {
    _popup?.close();
    _popup = null;
    _origin = null;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.drawer;
    final s = d._s;
    final cs = Theme.of(context).colorScheme;
    final app = widget.app;
    final size = widget.icon;
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: Apps.instance.notifCounts,
      builder: (context, counts, _) {
        final icon = PixelIcon(
          key: _iconKey,
          app: app,
          size: size,
          shape: s.iconShape,
          label: s.drawerLabels,
          dot: s.notifDots && (counts[app.package] ?? 0) > 0,
          labelColor: cs.onSurface,
          shadow: false,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => d._launch(app, context),
          child: LongPressDraggable<String>(
            data: 'app:${app.package}',
            delay: const Duration(milliseconds: 350),
            hapticFeedbackOnStart: false,
            dragAnchorStrategy: (draggable, ctx, position) => Offset(size / 2, size / 2),
            feedback: Transform.scale(scale: 1.1, child: PixelIcon(app: app, size: size, shape: s.iconShape, label: false)),
            onDragStarted: () {
              final box = _iconKey.currentContext?.findRenderObject() as RenderBox?;
              if (box != null && box.hasSize) {
                final o = box.localToGlobal(Offset.zero);
                final iconRect = Rect.fromLTWH(o.dx + (box.size.width - size) / 2, o.dy, size, size);
                _popup = showPixelAppPopup(context, prefs: d.widget.prefs, app: app, anchor: iconRect);
              }
              FocusManager.instance.primaryFocus?.unfocus();
              d.widget.onDragStart?.call();
            },
            onDragUpdate: (u) {
              _origin ??= u.globalPosition - u.delta;
              if ((u.globalPosition - _origin!).distance > 10) _closePopup();
            },
            child: Center(child: icon),
          ),
        );
      },
    );
  }
}
