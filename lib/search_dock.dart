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
    this.tab = 'home',
    this.onHome,
  });

  /// The bottom nav's selected tab at rest: 'home', 'search', 'remote' or 'settings'.
  final String tab;

  /// The nav's Home tab (back to the clock); null = the plain search dock (inside the drawer).
  final VoidCallback? onHome;

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
          // At rest at the bottom: the floating nav. Searching: the nav turns into the search field
          // (+ close), crossfading in place with a slight settle.
          child: AnimatedSwitcher(
            duration: Motion.snapDuration,
            switchInCurve: Motion.settle,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(a), child: child),
            ),
            child: onHome != null && !active && !inline
                ? _NavBar(
                    key: const ValueKey('nav'),
                    selected: tab,
                    tabs: [
                      _NavTab('home', Icons.home_rounded, 'Home', onHome!, tooltip: 'Home screen'),
                      _NavTab('search', Icons.search_rounded, 'Search', onActivate),
                      if (onRemote != null)
                        _NavTab('remote', Icons.settings_remote_rounded, 'Remote', onRemote!, onLongPress: onRemoteLongPress, tooltip: 'TV remote'),
                      _NavTab('settings', Icons.tune_rounded, 'Settings', onSettings, tooltip: 'Launcher settings'),
                    ],
                  )
                : KeyedSubtree(key: const ValueKey('search'), child: _searchLayout()),
          ),
        ),
      ),
    );
  }

  /// The search dock (no nav): the pill, the remote and settings circles right of it at rest; while
  /// searching or scrolled they slide out (scrolled: the dock shrinks to just the search circle).
  Widget _searchLayout() {
    final small = compact && !active && !inline;
    final tools = !active && !small;
    return LayoutBuilder(
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

class _NavTab {
  const _NavTab(this.id, this.icon, this.label, this.onTap, {this.onLongPress, this.tooltip});
  final String id, label;
  final String? tooltip; // long-press hint (defaults to the label)
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
}

/// The floating bottom nav: a glass pill that hugs its icon tabs, centred. Each tab is a circle; an
/// accent circle sits behind the selected one and slides to the tab tapped, and the icons crossfade
/// between ink and accent ink.
class _NavBar extends StatelessWidget {
  const _NavBar({super.key, required this.tabs, required this.selected});
  final List<_NavTab> tabs;
  final String selected;

  static const _inset = 4.0; // bar around the tabs: 4 + 48 + 4 = the dock's 56
  static const _tab = SearchDock.height - _inset * 2; // 48: a full touch target
  static const _gap = 4.0;
  static const _radius = _tab / 2; // round tabs; the bar's corners are this + the inset, so they nest (a pill)

  @override
  Widget build(BuildContext context) {
    final on = tabs.indexWhere((t) => t.id == selected);
    final bar = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius + _inset));
    return Center(
      child: DecoratedBox(
        decoration: ShapeDecoration(shape: bar, shadows: Perf.lite.value ? null : SearchDock.shadow),
        child: glassOr(
          colour: DS.card,
          shape: bar,
          child: Padding(
            padding: const EdgeInsets.all(_inset),
            child: Stack(
              children: [
                if (on >= 0)
                  AnimatedPositioned(
                    duration: Motion.snapDuration,
                    curve: Motion.settle,
                    left: on * (_tab + _gap),
                    top: 0,
                    width: _tab,
                    height: _tab,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: DS.hero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
                      ),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, t) in tabs.indexed) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      SizedBox.square(
                        dimension: _tab,
                        child: _NavButton(tab: t, selected: i == on),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.tab, required this.selected});
  final _NavTab tab;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: Tooltip(
        message: tab.tooltip ?? tab.label,
        // Remote's long-press offers to hide it; the hint would cover that sheet.
        triggerMode: tab.onLongPress != null ? TooltipTriggerMode.manual : TooltipTriggerMode.longPress,
        child: Pressable(
          scale: .9,
          child: SizedBox.square(
            dimension: _NavBar._tab,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_NavBar._radius)),
                onTap: () {
                  HapticFeedback.selectionClick();
                  tab.onTap();
                },
                onLongPress: tab.onLongPress,
                child: Center(
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: selected ? DS.heroInk : DS.ink),
                    duration: Motion.snapDuration,
                    builder: (context, colour, _) => Icon(tab.icon, color: colour, size: 24),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
