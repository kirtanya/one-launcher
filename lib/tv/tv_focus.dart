import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/ds.dart';
import 'tv_apps.dart';

/// Anything you can land on with the remote: tiles, buttons, menu rows.
///
/// OK fires on key *release*, and only if the press started here — so holding OK on a tile
/// (long press = options) never also triggers whatever the menu then focuses.
/// Arrows go to [onMove] when given (the home screen steers row by row); otherwise Flutter's
/// normal directional focus takes them.
class TvFocusable extends StatefulWidget {
  const TvFocusable({super.key, required this.builder, this.onSelect, this.onLongSelect, this.onMove, this.onFocus, this.focusNode, this.autofocus = false});

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect; // hold OK, or the remote's menu key
  final bool Function(AxisDirection dir)? onMove;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;
  final bool autofocus;

  static bool isSelect(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.gameButtonA;

  static AxisDirection? direction(LogicalKeyboardKey k) => switch (k) {
    LogicalKeyboardKey.arrowUp => AxisDirection.up,
    LogicalKeyboardKey.arrowDown => AxisDirection.down,
    LogicalKeyboardKey.arrowLeft => AxisDirection.left,
    LogicalKeyboardKey.arrowRight => AxisDirection.right,
    _ => null,
  };

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  // A node that already has focus (this widget rebuilt in a new place) shows as focused at once.
  late bool _focused = widget.focusNode?.hasFocus ?? false;
  bool _held = false; // OK went down here
  bool _long = false; // …and was held long enough to open options

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (TvFocusable.isSelect(k)) {
      switch (e) {
        case KeyDownEvent():
          _held = true;
          _long = false;
        case KeyRepeatEvent():
          if (_held && !_long && widget.onLongSelect != null) {
            _long = true;
            HapticFeedback.mediumImpact();
            widget.onLongSelect!();
          }
        case KeyUpEvent():
          if (_held && !_long) {
            if (DS.third) TvApps.instance.sound('clunk'); // Real: the key bottoming out
            widget.onSelect?.call();
          }
          _held = false;
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.contextMenu && e is KeyDownEvent && widget.onLongSelect != null) {
      widget.onLongSelect!();
      return KeyEventResult.handled;
    }
    final dir = TvFocusable.direction(k);
    if (dir != null && widget.onMove != null) {
      if (e is! KeyUpEvent) widget.onMove!(dir);
      return KeyEventResult.handled; // even at an edge: no jumping to some far-off tile
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: (f) {
        if (!f) _held = false;
        setState(() => _focused = f);
        if (f && DS.third) TvApps.instance.sound('tick'); // Real: a detent, like a channel dial
        if (f) widget.onFocus?.call();
      },
      // Touch / mouse still work (TV emulators, phones with a mouse).
      child: GestureDetector(onTap: widget.onSelect, onLongPress: widget.onLongSelect, child: widget.builder(context, _focused)),
    );
  }
}
