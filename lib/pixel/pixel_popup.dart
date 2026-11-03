import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../prefs.dart';
import '../quick_actions.dart';
import '../quick_chips.dart';
import '../sheets.dart';
import '../ui/motion.dart';

/// Handle of an open Pixel app popup.
class PixelPopupHandle {
  PixelPopupHandle._(this._close);
  final VoidCallback _close;
  bool _open = true;

  void close() {
    if (!_open) return;
    _open = false;
    _close();
  }

  bool get isOpen => _open;
}

/// Pixel Launcher's long-press popup: a rounded card anchored above [anchor] (below when there
/// is no room, with a small arrow at the icon): a vertical list of the app's shortcuts, App info,
/// Widgets, then Remove (home) or Uninstall (drawer). An [OverlayEntry], not a route, so a drag that started on the icon keeps
/// going underneath it.
PixelPopupHandle showPixelAppPopup(
  BuildContext context, {
  required Prefs prefs,
  required AppEntry app,
  required Rect anchor,
  bool onHome = false,
  VoidCallback? onRemove,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  late final PixelPopupHandle handle;
  final key = GlobalKey<_PopupState>();
  handle = PixelPopupHandle._(() {
    final s = key.currentState;
    if (s == null || !s.mounted) {
      if (entry.mounted) entry.remove();
      return;
    }
    s.dismiss(() {
      if (entry.mounted) entry.remove();
    });
  });
  entry = OverlayEntry(
    builder: (ctx) => _Popup(
      key: key,
      app: app,
      anchor: anchor,
      onHome: onHome,
      onRemove: onRemove,
      hostContext: context,
      prefs: prefs,
      handle: handle,
    ),
  );
  overlay.insert(entry);
  HapticFeedback.mediumImpact();
  return handle;
}

class _Popup extends StatefulWidget {
  const _Popup({
    super.key,
    required this.app,
    required this.anchor,
    required this.onHome,
    required this.onRemove,
    required this.hostContext,
    required this.prefs,
    required this.handle,
  });
  final AppEntry app;
  final Rect anchor;
  final bool onHome;
  final VoidCallback? onRemove;
  final BuildContext hostContext;
  final Prefs prefs;
  final PixelPopupHandle handle;

  @override
  State<_Popup> createState() => _PopupState();
}

class _PopupState extends State<_Popup> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 150), reverseDuration: const Duration(milliseconds: 100))
    ..forward();
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Motion.settle, reverseCurve: Curves.easeIn);
  List<AppShortcut> _shortcuts = const [];
  bool _hasWidgets = false;

  static const _width = 180.0;

  String get _pkg => widget.app.package.split('@').first;

  @override
  void initState() {
    super.initState();
    if (!widget.app.isShortcut) {
      Apps.instance.shortcuts().then((all) {
        if (!mounted || all == null) return;
        setState(() => _shortcuts = [
          for (final sc in all)
            if (sc.package == _pkg && sc.work == widget.app.work) sc,
        ].take(4).toList());
      });
      Apps.instance.widgetProviders().then((all) {
        if (!mounted) return;
        setState(() => _hasWidgets = all.any((w) => w.package == _pkg));
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void dismiss(VoidCallback done) {
    _c.reverse().whenComplete(done);
  }

  void _run(VoidCallback action) {
    widget.handle.close();
    action();
  }

  static const _row = 43.0, _arrowH = 8.0, _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF1F1F1F) : cs.surfaceContainer;
    final fg = cs.onSurface;
    final app = widget.app;
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final items = <Widget>[
      for (var i = 0; i < _shortcuts.length; i++)
        _Row(
          leading: ShortcutIcon(id: _shortcuts[i].id, size: 22, color: fg),
          label: _shortcuts[i].label,
          onTap: () => _run(() => Apps.instance.quickAction(_shortcuts[i].id)),
        ),
      _Row(leading: Icon(Icons.info_rounded, size: 22, color: fg), label: 'App info', onTap: () => _run(() => Apps.instance.appInfo(app.package))),
      if (_hasWidgets)
        _Row(
          leading: Icon(Icons.widgets_rounded, size: 22, color: fg),
          label: 'Widgets',
          onTap: () {
            final host = widget.hostContext;
            _run(() {
              if (host.mounted) showWidgetPicker(host, prefs: widget.prefs);
            });
          },
        ),
      if (widget.onHome && widget.onRemove != null)
        _Row(leading: Icon(Icons.close_rounded, size: 22, color: fg), label: 'Remove', onTap: () => _run(widget.onRemove!))
      else if (!widget.onHome && (!app.system || app.isShortcut))
        _Row(
          leading: Icon(Icons.delete_rounded, size: 22, color: fg),
          label: app.isShortcut ? 'Remove' : 'Uninstall',
          onTap: () => _run(() => app.isShortcut ? Apps.instance.removeShortcut(app.package) : Apps.instance.uninstall(app.package)),
        ),
    ];

    final margin = EdgeInsets.fromLTRB(12, pad.top + 8, 12, pad.bottom + 8);
    final height = items.length * _row + 16 + _arrowH;
    final x = widget.anchor.left.clamp(margin.left, math.max(margin.left, screen.width - margin.right - _width)).toDouble();
    final above = widget.anchor.top - _gap - height >= margin.top;
    final arrowX = (widget.anchor.center.dx - x).clamp(26.0, _width - 26);

    final card = Material(
      color: bg,
      elevation: 3,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: _width,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(mainAxisSize: MainAxisSize.min, children: items)),
      ),
    );
    final arrow = CustomPaint(size: const Size(_width, _arrowH), painter: _ArrowPainter(bg, arrowX, above));
    final body = Column(mainAxisSize: MainAxisSize.min, children: above ? [card, arrow] : [arrow, card]);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.handle.close, onSecondaryTap: widget.handle.close),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _PopupLayout(widget.anchor, margin, x, above),
            child: FadeTransition(
              opacity: _t,
              child: ScaleTransition(
                scale: Tween<double>(begin: .7, end: 1).animate(_t),
                alignment: Alignment(arrowX / _width * 2 - 1, above ? 1 : -1),
                child: body,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PopupLayout extends SingleChildLayoutDelegate {
  _PopupLayout(this.anchor, this.margin, this.x, this.above);
  final Rect anchor;
  final EdgeInsets margin;
  final double x;
  final bool above;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints.loose(Size(c.maxWidth, c.maxHeight));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final y = above ? anchor.top - _PopupState._gap - child.height : anchor.bottom + _PopupState._gap;
    return Offset(x, y.clamp(margin.top, math.max(margin.top, size.height - margin.bottom - child.height)));
  }

  @override
  bool shouldRelayout(_PopupLayout old) => old.anchor != anchor || old.margin != margin || old.x != x || old.above != above;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color, this.x, this.up);
  final Color color;
  final double x;
  final bool up; // card above the arrow, so the arrow points down

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final path = up
        ? (Path()..moveTo(x - 9, 0)..lineTo(x, h)..lineTo(x + 9, 0)..close())
        : (Path()..moveTo(x - 9, h)..lineTo(x, 0)..lineTo(x + 9, h)..close());
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color || old.x != x || old.up != up;
}

class _Row extends StatelessWidget {
  const _Row({required this.leading, required this.label, required this.onTap});
  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _PopupState._row,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox.square(dimension: 22, child: Center(child: leading)),
              const SizedBox(width: 15),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: cs.onSurface))),
            ],
          ),
        ),
      ),
    );
  }
}
