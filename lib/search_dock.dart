import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
    this.pull,
    this.pullFull = 1,
  });

  /// Pull-to-search: how far the list is pulled down (px), and the pull that opens search. The nav
  /// morphs toward the search bar as far as the finger has pulled.
  final ValueListenable<double>? pull;
  final double pullFull;

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
          // At the bottom the dock is the nav, and searching morphs it into the search bar (one
          // animation: _NavSearch). In the drawer (bar at the top) it's the plain search dock.
          child: onHome != null && !inline
              ? _NavSearch(
                  active: active,
                  selected: tab,
                  tabs: [
                    _NavTab('home', Icons.home_rounded, 'Home', onHome!, tooltip: 'Home screen'),
                    _NavTab('search', Icons.search_rounded, 'Search', onActivate),
                    if (onRemote != null)
                      _NavTab('remote', Icons.settings_remote_rounded, 'Remote', onRemote!, onLongPress: onRemoteLongPress, tooltip: 'TV remote'),
                    _NavTab('settings', Icons.tune_rounded, 'Settings', onSettings, tooltip: 'Launcher settings'),
                  ],
                  controller: controller,
                  focus: focus,
                  hint: hint,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  onClose: onClose,
                  pull: pull,
                  pullFull: pullFull,
                )
              : _searchLayout(),
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
  const _NavBar({required this.tabs, required this.selected, this.bare = false, this.hide});
  final List<_NavTab> tabs;
  final String selected;

  /// Just the tabs, no glass bar of its own ([_NavSearch] draws the shape).
  final bool bare;

  /// A tab whose icon is drawn elsewhere for now (Search, while it glides into the search bar).
  final String? hide;

  static const _inset = 4.0; // bar around the tabs: 4 + 48 + 4 = the dock's 56
  static const _tab = SearchDock.height - _inset * 2; // 48: a full touch target
  static const _gap = 4.0;
  static const _radius = _tab / 2; // round tabs; the bar's corners are this + the inset, so they nest (a pill)

  @override
  Widget build(BuildContext context) {
    final on = tabs.indexWhere((t) => t.id == selected);
    final bar = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius + _inset));
    final content = Padding(
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
                  child: Opacity(
                    opacity: t.id == hide ? 0 : 1,
                    child: _NavButton(tab: t, selected: i == on),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    if (bare) return content;
    return Center(
      child: DecoratedBox(
        decoration: ShapeDecoration(shape: bar, shadows: Perf.lite.value ? null : SearchDock.shadow),
        child: glassOr(colour: DS.card, shape: bar, child: content),
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

/// The nav and the search bar as one shape. Searching ([active]) the pill widens from the centred
/// nav to the full search bar; the Search icon glides from its tab to the bar's start; the other
/// tabs fade out and the field fades in; the close button scales in beside it (0 → 100 %, a slight
/// overshoot). Closing plays it backwards.
class _NavSearch extends StatefulWidget {
  const _NavSearch({
    required this.active,
    required this.selected,
    required this.tabs,
    required this.controller,
    required this.focus,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClose,
    this.pull,
    this.pullFull = 1,
  });
  final bool active;
  final ValueListenable<double>? pull;
  final double pullFull;
  final String selected;
  final List<_NavTab> tabs;
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final ValueChanged<String> onChanged, onSubmitted;
  final VoidCallback onClose;

  @override
  State<_NavSearch> createState() => _NavSearchState();
}

class _NavSearchState extends State<_NavSearch> with SingleTickerProviderStateMixin {
  late final _t = AnimationController(vsync: this, duration: Motion.snapDuration, value: widget.active ? 1 : 0);

  @override
  void initState() {
    super.initState();
    widget.pull?.addListener(_follow);
  }

  /// Pulling the list down: the morph is wherever the finger is (until search opens, when the
  /// animation carries on from there; a pull let go short of it eases back with the pull).
  void _follow() {
    if (widget.active || _t.isAnimating) return;
    _t.value = (widget.pull!.value / widget.pullFull).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(_NavSearch old) {
    super.didUpdateWidget(old);
    if (old.pull != widget.pull) {
      old.pull?.removeListener(_follow);
      widget.pull?.addListener(_follow);
    }
    if (widget.active != old.active) widget.active ? _t.forward() : _t.reverse();
  }

  @override
  void dispose() {
    widget.pull?.removeListener(_follow);
    _t.dispose();
    super.dispose();
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    const h = SearchDock.height, inset = _NavBar._inset, tab = _NavBar._tab, gap = _NavBar._gap;
    final n = widget.tabs.length;
    final navW = inset * 2 + n * tab + (n - 1) * gap;
    final searchAt = widget.tabs.indexWhere((t) => t.id == 'search');
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final barW = w - h - SearchDock.gap; // room for the close circle on the right
        return AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final t = Motion.settle.transform(_t.value); // the shape: springy settle
            final fade = Curves.easeOut.transform((_t.value * 2).clamp(0.0, 1.0)); // tabs go in the first half
            final field = Curves.easeOut.transform(((_t.value - .4) / .6).clamp(0.0, 1.0)); // field in the second
            final close = Curves.easeOutBack.transform(((_t.value - .35) / .65).clamp(0.0, 1.0));
            final pillW = _lerp(navW, barW, t);
            final pillLeft = _lerp((w - navW) / 2, 0, t);
            // The Search icon's centre: on its tab at rest, at the bar's start (16 + 12) when searching.
            final iconX = _lerp((pillW - navW) / 2 + inset + searchAt * (tab + gap) + tab / 2, 28, t);
            final searching = widget.active || _t.value > 0;
            final radius = BorderRadius.circular(99);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: pillLeft,
                  top: 0,
                  width: pillW,
                  height: h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(borderRadius: radius, boxShadow: Perf.lite.value ? null : SearchDock.shadow),
                    child: glassOr(
                      colour: DS.card,
                      shape: const StadiumBorder(),
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          // The nav: tabs fading where they are, centred in the widening pill (Search's own
                          // icon hidden while its copy glides to the bar's start).
                          // Keys keep each layer itself as others come and go: the field must never be
                          // rebuilt mid-search (a new field loses focus and the keyboard drops).
                          if (fade < 1)
                            Positioned(
                              key: const ValueKey('tabs'),
                              left: (pillW - navW) / 2,
                              top: 0,
                              width: navW,
                              height: h,
                              child: IgnorePointer(
                                ignoring: searching,
                                child: Opacity(
                                  opacity: 1 - fade,
                                  child: _NavBar(selected: widget.selected, tabs: widget.tabs, bare: true, hide: searching ? 'search' : null),
                                ),
                              ),
                            ),
                          if (searching) ...[
                            Positioned(
                              key: const ValueKey('icon'),
                              left: iconX - 12,
                              top: (h - 24) / 2,
                              child: Icon(Icons.search_rounded, color: DS.ink, size: 24),
                            ),
                            Positioned(
                              key: const ValueKey('field'),
                              left: 48,
                              right: DS.s16,
                              top: 0,
                              bottom: 0,
                              child: Opacity(
                                opacity: field,
                                child: Center(
                                  child: TextField(
                                    controller: widget.controller,
                                    focusNode: widget.focus,
                                    onChanged: widget.onChanged,
                                    onSubmitted: widget.onSubmitted,
                                    textInputAction: TextInputAction.go,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    cursorColor: DS.ink,
                                    style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500),
                                    decoration: InputDecoration.collapsed(hintText: widget.hint, hintStyle: DS.rowSub),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (close > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    width: h,
                    height: h,
                    child: Transform.scale(
                      scale: close,
                      child: _DockCircle(icon: Icons.close_rounded, tooltip: 'Close search', onTap: widget.onClose),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
