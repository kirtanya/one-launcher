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
/// is no room) with the app's shortcuts, then a row of small round buttons (App info, Widgets,
/// Uninstall, Remove). An [OverlayEntry], not a route, so a drag that started on the icon keeps
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

  static const _width = 268.0;

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final app = widget.app;
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final buttons = <Widget>[
      _RoundButton(icon: Icons.info_outline_rounded, label: 'App info', onTap: () => _run(() => Apps.instance.appInfo(app.package))),
      if (_hasWidgets)
        _RoundButton(
          icon: Icons.widgets_outlined,
          label: 'Widgets',
          onTap: () {
            final host = widget.hostContext;
            _run(() {
              if (host.mounted) showWidgetPicker(host, prefs: widget.prefs);
            });
          },
        ),
      if (!app.system || app.isShortcut)
        _RoundButton(
          icon: Icons.delete_outline_rounded,
          label: app.isShortcut ? 'Remove' : 'Uninstall',
          onTap: () => _run(() => app.isShortcut ? Apps.instance.removeShortcut(app.package) : Apps.instance.uninstall(app.package)),
        ),
      if (widget.onHome && widget.onRemove != null)
        _RoundButton(icon: Icons.remove_circle_outline_rounded, label: 'Remove', onTap: () => _run(widget.onRemove!)),
    ];

    final card = Material(
      color: cs.surfaceContainerHigh,
      elevation: 3,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: _width,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _shortcuts.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _ShortcutRow(
                    sc: _shortcuts[i],
                    first: i == 0,
                    last: i == _shortcuts.length - 1,
                    onTap: () => _run(() => Apps.instance.quickAction(_shortcuts[i].id)),
                  ),
                ),
              if (_shortcuts.isNotEmpty) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.start, children: buttons),
              ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.handle.close, onSecondaryTap: widget.handle.close),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _PopupLayout(widget.anchor, EdgeInsets.fromLTRB(12, pad.top + 8, 12, pad.bottom + 8), screen),
            child: LayoutBuilder(
              builder: (ctx, _) {
                final above = widget.anchor.center.dy > screen.height / 2 || widget.anchor.top > 220;
                return FadeTransition(
                  opacity: _t,
                  child: ScaleTransition(scale: Tween<double>(begin: .8, end: 1).animate(_t), alignment: above ? Alignment.bottomCenter : Alignment.topCenter, child: card),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PopupLayout extends SingleChildLayoutDelegate {
  _PopupLayout(this.anchor, this.margin, this.screen);
  final Rect anchor;
  final EdgeInsets margin;
  final Size screen;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints.loose(Size(c.maxWidth, c.maxHeight));

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = anchor.center.dx - child.width / 2;
    x = x.clamp(margin.left, (size.width - margin.right - child.width).clamp(margin.left, double.infinity));
    const gap = 8.0;
    final above = anchor.top - gap - child.height;
    final y = above >= margin.top ? above : anchor.bottom + gap;
    return Offset(x, y.clamp(margin.top, (size.height - margin.bottom - child.height).clamp(margin.top, double.infinity)));
  }

  @override
  bool shouldRelayout(_PopupLayout old) => old.anchor != anchor || old.margin != margin;
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.sc, required this.first, required this.last, required this.onTap});
  final AppShortcut sc;
  final bool first, last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const big = Radius.circular(18), small = Radius.circular(6);
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.vertical(top: first ? big : small, bottom: last ? big : small),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ShortcutIcon(id: sc.id, size: 24, color: cs.onSurface),
              const SizedBox(width: 14),
              Expanded(
                child: Text(sc.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, color: cs.onSurface, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle),
              child: Icon(icon, size: 22, color: cs.onSurface),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
