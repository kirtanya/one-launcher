import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../apps.dart';
import '../ui/motion.dart';
import '../ui/perf.dart';
import '../widgets.dart';
import 'pixel_icon.dart';
import 'pixel_model.dart';

/// A folder closed on the home screen: an icon-shaped translucent back with a 2x2 preview of its
/// first apps (like Pixel Launcher), its name under it.
class PixelFolderIcon extends StatelessWidget {
  const PixelFolderIcon({
    super.key,
    required this.folder,
    required this.apps,
    required this.size,
    this.shape = 'circle',
    this.label = true,
    this.dot = false,
    this.labelColor = Colors.white,
    this.shadow = true,
  });
  final PixelFolder folder;

  /// Every installed app by package.
  final Map<String, AppEntry> apps;
  final double size;
  final String shape;
  final bool label, dot;
  final Color labelColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inside = [
      for (final p in folder.apps)
        if (apps[p] != null) apps[p]!,
    ].take(4).toList();
    final pad = size * .14;
    final mini = (size - pad * 2 - size * .06) / 2;
    final back = SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipPath(
            clipper: PixelShape(shape),
            child: ColoredBox(
              color: Color.alphaBlend(
                cs.surfaceContainerHighest.withValues(alpha: .35),
                Colors.white.withValues(alpha: .22),
              ),
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: Wrap(
                  spacing: size * .06,
                  runSpacing: size * .06,
                  children: [
                    for (final a in inside)
                      SizedBox.square(
                        dimension: mini,
                        child: ClipPath(
                          clipper: PixelShape(shape),
                          child: AppIcon(a, size: mini),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (dot)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: size * .22,
                height: size * .22,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
    if (!label) return back;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        back,
        const SizedBox(height: 6),
        SizedBox(
          width: size * 1.45,
          child: Text(
            folder.name.isEmpty ? 'Folder' : folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.2,
              color: labelColor,
              shadows: shadow
                  ? const [Shadow(blurRadius: 4, color: Color(0x99000000))]
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// An opened folder: a rounded card that grows from the closed icon's place (scale + fade,
/// ~250 ms), the name on top (tap to rename), the apps in a grid (pages when many). Tap outside
/// to close. [bigFolders]: the card fills the screen, with a bigger grid.
class PixelFolderOpen extends StatefulWidget {
  const PixelFolderOpen({
    super.key,
    required this.folder,
    required this.apps,
    required this.from,
    required this.onClosed,
    required this.onLaunch,
    required this.onRename,
    this.onDragOut,
    this.shape = 'circle',
    this.big = false,
    this.labels = true,
    this.iconScale = 1,
    this.locked = false,
    this.preview = false,
  });
  final PixelFolder folder;
  final Map<String, AppEntry> apps;

  /// The closed icon, in this widget's coordinates (the card grows from it).
  final Rect from;

  /// The close animation finished: remove this widget.
  final VoidCallback onClosed;
  final ValueChanged<String> onLaunch;
  final ValueChanged<String> onRename;

  /// An app was long-pressed and picked up: the host takes the drag on (this closes).
  final ValueChanged<String>? onDragOut;
  final String shape;
  final bool big, labels, locked, preview;
  final double iconScale;

  @override
  State<PixelFolderOpen> createState() => PixelFolderOpenState();
}

class PixelFolderOpenState extends State<PixelFolderOpen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final _name = TextEditingController(text: widget.folder.name);
  final _nameFocus = FocusNode();
  bool _renaming = false;
  bool _closing = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && _renaming) _commit();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Shrinks back into the icon, then tells the host.
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    if (_renaming) _commit();
    await _c.reverse();
    if (mounted) widget.onClosed();
  }

  void _commit() {
    setState(() => _renaming = false);
    final v = _name.text.trim();
    if (v != widget.folder.name) widget.onRename(v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final pkgs = [
          for (final p in widget.folder.apps)
            if (widget.apps[p] != null) p,
        ];
        final cols = widget.big ? 5 : 4;
        final icon =
            (widget.big ? 58.0 : 52.0) * widget.iconScale.clamp(.8, 1.2);
        final cellH = icon + (widget.labels ? 30 : 18);
        const titleH = 68.0;
        final inset = mq.padding;
        // The card.
        double cardW, cardH;
        int rowsShown;
        if (widget.big) {
          cardW = w - 24;
          cardH = h - inset.top - inset.bottom - 48;
          rowsShown = math.max(2, ((cardH - titleH - 56) / cellH).floor());
        } else {
          cardW = math.min(w - 40, 420.0);
          rowsShown = math.min(3, math.max(1, (pkgs.length / cols).ceil()));
          cardH = titleH + rowsShown * cellH + 28;
        }
        final perPage = cols * rowsShown;
        final pages = math.max(1, (pkgs.length / perPage).ceil());
        if (pages > 1 && !widget.big) cardH += 18;
        var top = (widget.from.center.dy - cardH / 2).clamp(
          inset.top + 16,
          math.max(inset.top + 16, h - inset.bottom - cardH - 16),
        );
        if (widget.big) top = inset.top + 24;
        final to = Rect.fromLTWH((w - cardW) / 2, top.toDouble(), cardW, cardH);
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Motion.settle.transform(_c.value).clamp(0.0, 1.05);
            final fade = Curves.easeOut.transform(_c.value);
            final rect = Rect.lerp(widget.from, to, t)!;
            final radius = BorderRadius.circular(
              lerpDouble2(widget.from.width * .3, 28, t.clamp(0.0, 1.0)),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                // Scrim: the wallpaper dims (and blurs unless lighter effects are on).
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.preview ? null : close,
                    child: !Perf.lite.value && !widget.preview
                        ? BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: 10 * fade,
                              sigmaY: 10 * fade,
                            ),
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: .32 * fade),
                            ),
                          )
                        : ColoredBox(
                            color: Colors.black.withValues(alpha: .4 * fade),
                          ),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: ColoredBox(
                      color: Color.alphaBlend(
                        cs.primary.withValues(alpha: .06),
                        cs.surfaceContainerHigh,
                      ),
                      child: OverflowBox(
                        minWidth: cardW,
                        maxWidth: cardW,
                        minHeight: cardH,
                        maxHeight: cardH,
                        child: Opacity(
                          opacity: fade,
                          child: _content(
                            cs,
                            pkgs,
                            cols,
                            rowsShown,
                            pages,
                            icon,
                            cellH,
                            titleH,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static double lerpDouble2(double a, double b, double t) => a + (b - a) * t;

  Widget _content(
    ColorScheme cs,
    List<String> pkgs,
    int cols,
    int rows,
    int pages,
    double icon,
    double cellH,
    double titleH,
  ) {
    final perPage = cols * rows;
    return Column(
      children: [
        SizedBox(
          height: titleH,
          child: Center(
            child: _renaming
                ? SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(fontSize: 20, color: cs.onSurface),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Folder name',
                      ),
                      onSubmitted: (_) => _commit(),
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.locked || widget.preview
                        ? null
                        : () => setState(() => _renaming = true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: Text(
                        widget.folder.name.isEmpty
                            ? 'Edit name'
                            : widget.folder.name,
                        style: TextStyle(
                          fontSize: 20,
                          color: widget.folder.name.isEmpty
                              ? cs.onSurfaceVariant
                              : cs.onSurface,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            itemCount: pages,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, p) {
              final slice = pkgs.skip(p * perPage).take(perPage).toList();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: cols,
                  mainAxisExtent: cellH,
                  padding: EdgeInsets.zero,
                  children: [for (final pkg in slice) _cell(cs, pkg, icon)],
                ),
              );
            },
          ),
        ),
        if (pages > 1)
          SizedBox(
            height: 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.onSurface.withValues(
                        alpha: i == _page ? .9 : .3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _cell(ColorScheme cs, String pkg, double icon) {
    final app = widget.apps[pkg]!;
    PixelIcon mk({bool label = true}) => PixelIcon(
      app: app,
      size: icon,
      shape: widget.shape,
      label: label && widget.labels,
      labelColor: cs.onSurface,
      shadow: false,
    );
    final child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.preview ? null : () => widget.onLaunch(pkg),
      child: Center(child: mk()),
    );
    if (widget.locked || widget.preview || widget.onDragOut == null) {
      return child;
    }
    return LongPressDraggable<String>(
      data: 'app:$pkg',
      delay: const Duration(milliseconds: 350),
      hapticFeedbackOnStart: true,
      dragAnchorStrategy: (d, ctx, pos) => Offset(icon / 2, icon / 2),
      feedback: Transform.scale(
        scale: 1.1,
        child: PixelIcon(
          app: app,
          size: icon,
          shape: widget.shape,
          label: false,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0, child: child),
      onDragStarted: () => widget.onDragOut!(pkg),
      child: child,
    );
  }
}
