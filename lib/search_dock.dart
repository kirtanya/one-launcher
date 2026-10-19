import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/ds.dart';
import 'ui/glass.dart';
import 'ui/perf.dart';
import 'ui/motion.dart';

/// iOS-style search at the bottom of the screen. One white pill that morphs between:
/// - full bar ("Search 124 apps") while the list is at rest or scrolling back down,
/// - a round search button while the list is scrolled up,
/// - a live text field + close button while searching.
/// Sits above the keyboard when it's open.
class SearchDock extends StatelessWidget {
  const SearchDock({
    super.key,
    required this.compact,
    required this.active,
    required this.controller,
    required this.focus,
    required this.hint,
    required this.onActivate,
    required this.onClose,
    required this.onChanged,
    required this.onSubmitted,
    required this.onSettings,
    this.inline = false,
    this.onSwipeClose,
    this.onRemote,
    this.onRemoteLongPress,
  });

  /// TV remote button between the bar and settings (null = hidden, Settings → TV remote).
  final VoidCallback? onRemote;

  /// Long-press on the remote button (offer to hide it).
  final VoidCallback? onRemoteLongPress;

  /// Swiped down on the bar while searching (defaults to [onClose]).
  final VoidCallback? onSwipeClose;

  /// Inside the app drawer (Settings → Search bar: Top) instead of floating at the bottom:
  /// no keyboard lift, no shadow.
  final bool inline;
  final bool compact;
  final bool active;
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final VoidCallback onActivate, onClose, onSettings;
  final ValueChanged<String> onChanged, onSubmitted;

  static const height = 56.0;
  // Small blur: it's redrawn every frame, and big blurs are costly on slower phones.
  static const shadow = [BoxShadow(color: Color(0x3D000000), blurRadius: 10, offset: Offset(0, 4))];
  static const gap = 8.0;
  static const _slot = height + gap;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = inline ? DS.s8 : math.max(mq.viewInsets.bottom, mq.padding.bottom) + DS.s12;
    final small = compact && !active && !inline;
    // Settings sits right of the bar at rest; they slide out while searching
    // or while the list is scrolled (dock shrinks to just the search circle).
    final tools = !active && !small;

    // Searching at the bottom: swipe down on the bar to close search (the results above
    // scroll on their own, so this is the one place that closes it).
    final swipeToClose = active && !inline;
    // Floating at the bottom, the dock's whole strip keeps vertical drags for itself: it sits on
    // the system's home-gesture edge, so a swipe up there must not scroll the app list behind it.
    final claim = !inline;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: swipeToClose ? (d) => _swipe += d.delta.dy : (claim ? (_) {} : null),
      onVerticalDragStart: swipeToClose ? (_) => _swipe = 0 : (claim ? (_) {} : null),
      onVerticalDragEnd: swipeToClose
          ? (d) {
              if (_swipe > 24 || (d.primaryVelocity ?? 0) > 300) {
                HapticFeedback.selectionClick();
                (onSwipeClose ?? onClose)();
              }
            }
          : (claim ? (_) {} : null),
      child: Padding(
        padding: EdgeInsets.fromLTRB(inline ? DS.gutter : DS.s16, 0, inline ? DS.gutter : DS.s16, bottom),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              // Room on the right for settings (and the remote button, when shown).
              final tray = onRemote != null ? _slot * 2 : _slot;
              final pillRight = active ? _slot : (small ? 0.0 : tray);
              final pillWidth = active ? w - _slot : (small ? height : w - tray);
              Widget slide({required double right, required bool shown, required Widget child}) => AnimatedPositioned(
                duration: Motion.snapDuration,
                curve: Motion.snap,
                top: 0,
                bottom: 0,
                right: right,
                width: height,
                child: AnimatedOpacity(
                  duration: Motion.snapDuration,
                  curve: Curves.easeOut,
                  opacity: shown ? 1 : 0,
                  child: IgnorePointer(ignoring: !shown, child: child),
                ),
              );
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // The pill. Anchored to the right so it shrinks into a circle on the right.
                  AnimatedPositioned(
                    duration: Motion.snapDuration,
                    curve: Motion.settle,
                    top: 0,
                    bottom: 0,
                    right: pillRight,
                    width: pillWidth,
                    child: _Pill(
                      small: small,
                      active: active,
                      controller: controller,
                      focus: focus,
                      hint: hint,
                      onActivate: onActivate,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                    ),
                  ),
                  if (onRemote != null)
                    slide(
                      right: tools ? _slot : -_slot,
                      shown: tools,
                      child: _DockCircle(icon: Icons.settings_remote_rounded, tooltip: 'TV remote', onTap: onRemote!, onLongPress: onRemoteLongPress),
                    ),
                  slide(
                    right: tools ? 0 : -_slot,
                    shown: tools,
                    child: _DockCircle(icon: Icons.tune_rounded, tooltip: 'Launcher settings', onTap: onSettings),
                  ),
                  // Close button slides in from the right while searching.
                  slide(
                    right: active ? 0 : -(height + DS.s16),
                    shown: active,
                    child: _DockCircle(icon: Icons.close_rounded, tooltip: 'Close search', onTap: onClose),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Distance of the current swipe on the bar (down = positive).
  static double _swipe = 0;
}

/// White floating circle with a soft shadow, matching the search pill.
class _DockCircle extends StatelessWidget {
  const _DockCircle({required this.icon, required this.tooltip, required this.onTap, this.onLongPress});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: .88,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: Perf.lite.value ? null : SearchDock.shadow),
        child: Tooltip(
          message: tooltip,
          child: glassOr(
            colour: DS.card,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Icon(icon, color: DS.ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.small,
    required this.active,
    required this.controller,
    required this.focus,
    required this.hint,
    required this.onActivate,
    required this.onChanged,
    required this.onSubmitted,
  });

  final bool small, active;
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final VoidCallback onActivate;
  final ValueChanged<String> onChanged, onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      enabled: !active,
      scale: .95,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), boxShadow: Perf.lite.value ? null : SearchDock.shadow),
        child: glassOr(
          colour: DS.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
          child: InkWell(
            onTap: active ? null : onActivate,
            child: Stack(
              children: [
                // The icon never moves: 16 + 24 + 16 = 56, so it sits dead centre when the pill is a circle.
                Positioned(left: 16, top: 16, child: Icon(Icons.search_rounded, color: DS.ink, size: 24)),
                Positioned(
                  left: 48,
                  right: DS.s16,
                  top: 0,
                  bottom: 0,
                  child: active
                      ? Center(
                          child: TextField(
                            controller: controller,
                            focusNode: focus,
                            onChanged: onChanged,
                            onSubmitted: onSubmitted,
                            textInputAction: TextInputAction.go,
                            autocorrect: false,
                            enableSuggestions: false,
                            cursorColor: DS.ink,
                            style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500),
                            decoration: InputDecoration.collapsed(hintText: hint, hintStyle: DS.rowSub),
                          ),
                        )
                      : AnimatedOpacity(
                          duration: Motion.pressIn * 2,
                          opacity: small ? 0 : 1,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(hint, style: DS.rowSub.copyWith(fontSize: 16), maxLines: 1, softWrap: false, overflow: TextOverflow.clip),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
