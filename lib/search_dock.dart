import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'third/tactile/parts.dart';
import 'third/tactile/tactile.dart';
import 'ui/ds.dart';
import 'ui/glass.dart';
import 'ui/perf.dart';
import 'ui/motion.dart';
import 'play_build.dart';

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
    this.onNow,
    this.onHome,
    this.pull,
    this.pullFull = 1,
  });

  /// Pull-to-search: how far the list is pulled down (px), and the pull that opens search. The nav
  /// morphs toward the search bar as far as the finger has pulled.
  final ValueListenable<double>? pull;
  final double pullFull;

  /// The bottom nav's selected tab at rest: 'now', 'home', 'smart', 'remote', 'search' or 'settings'.
  final String tab;

  /// The nav's Home tab (back to the clock); null = the plain search dock (inside the drawer).
  final VoidCallback? onNow;
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

  static const height = 64.0; // nav tabs are 56 (4 + 56 + 4); icons keep their size
  // Small blur: it's redrawn every frame, and big blurs are costly on slower phones.
  static const shadow = [BoxShadow(color: Color(0x3D000000), blurRadius: 10, offset: Offset(0, 4))];
  static const gap = 8.0;

  /// A page under the nav has scrolled away from its top: the nav's tabs shrink from 56 to 48
  /// (icons stay their size) and grow back at the top. Home sets it from the pages' scrolling.
  static final shrunk = ValueNotifier<bool>(false);

  /// The bar's outline: it's the lowest surface, so this keeps it from merging into what's
  /// behind (glass draws its own bright edge instead).
  static BorderSide get border => BorderSide(color: DS.hairline);
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
                  selected: tab == 'remote' ? 'smart' : (tab == 'settings' ? 'home' : tab), // the remote lives in Smart home; Settings under Home
                  tabs: [
                    // Settings has no tab: long-press Home.
                    if (onNow != null) _NavTab('now', Icons.graphic_eq_rounded, 'Now', onNow!, tooltip: 'Now: what\'s playing'),
                    _NavTab('home', Icons.home_rounded, 'Home', onHome!, onLongPress: onSettings, tooltip: 'Home screen · hold for Settings'),
                    if (onRemote != null)
                      playBuild
                          ? _NavTab('smart', Icons.settings_remote_rounded, 'Remote', onRemote!, onLongPress: onRemoteLongPress, tooltip: 'TV remote')
                          : _NavTab('smart', Icons.lightbulb_rounded, 'Smart home', onRemote!, onLongPress: onRemoteLongPress, tooltip: 'Smart home and TV remote'),
                    _NavTab('search', Icons.search_rounded, 'Search', onActivate),
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
                child: _DockCircle(icon: Icons.lightbulb_rounded, tooltip: 'Smart home and TV remote', onTap: onRemote!, onLongPress: onRemoteLongPress),
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
    // Tactile: a round key.
    if (DS.third) {
      return TKey(
        width: SearchDock.height,
        height: SearchDock.height,
        radius: SearchDock.height / 2,
        tooltip: tooltip,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Icon(icon, color: Tactile.ink),
      );
    }
    return Pressable(
      scale: .88,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: Perf.lite.value ? null : SearchDock.shadow),
        child: Tooltip(
          message: tooltip,
          child: glassOr(
            colour: DS.base,
            shape: CircleBorder(side: SearchDock.border),
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
                // The icon never moves: 20 + 24 + 20 = 64, so it sits dead centre when the pill is a circle.
                Positioned(left: 20, top: 20, child: Icon(Icons.search_rounded, color: DS.ink, size: 24)),
                Positioned(
                  left: 52,
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
  const _NavBar({required this.tabs, required this.selected, this.bare = false, this.hide, this.shift, this.tab = big});
  final List<_NavTab> tabs;
  final String selected;

  /// Just the tabs, no glass bar of its own ([_NavSearch] draws the shape).
  final bool bare;

  /// A tab whose icon is drawn elsewhere for now (Search, while it glides into the search bar).
  final String? hide;

  /// How far each tab is pushed sideways (the morph slides them out of the bar); the accent goes
  /// with its tab.
  final List<double>? shift;

  /// Each tab's size: [big] at rest, [small] once the page under it scrolls (SearchDock.small).
  final double tab;

  static const _inset = 4.0; // bar around the tabs: 4 + 56 + 4 = the dock's 64
  static const big = SearchDock.height - _inset * 2; // 56: a roomy touch target
  static const small = 48.0;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final on = tabs.indexWhere((t) => t.id == selected);
    final radius = tab / 2; // round tabs; the bar's corners are this + the inset, so they nest (a pill)
    final bar = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius + _inset), side: SearchDock.border);
    final content = Padding(
      padding: const EdgeInsets.all(_inset),
      child: Stack(
        children: [
          if (on >= 0 && !DS.third) // Tactile: the chosen tab is a latched key instead
            // Slides by tab index (not pixels), so it keeps up while the tabs grow or shrink.
            TweenAnimationBuilder<double>(
              tween: Tween(end: on.toDouble()),
              duration: Motion.snapDuration,
              curve: Motion.settle,
              builder: (context, at, child) => Positioned(left: at * (tab + _gap), top: 0, width: tab, height: tab, child: child!),
              child: Transform.translate(
                offset: Offset(shift?[on] ?? 0, 0),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: DS.hero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tab / 2)),
                  ),
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, t) in tabs.indexed) ...[
                if (i > 0) const SizedBox(width: _gap),
                SizedBox.square(
                  dimension: tab,
                  child: Transform.translate(
                    offset: Offset(shift?[i] ?? 0, 0),
                    child: Opacity(
                      opacity: t.id == hide ? 0 : 1,
                      child: _NavButton(tab: t, selected: i == on, size: tab),
                    ),
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
        child: glassOr(colour: DS.base, shape: bar, child: content),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.tab, required this.selected, required this.size});
  final _NavTab tab;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Tactile: each tab is a key in the tray; the current one stays down with its LED lit.
    if (DS.third) {
      return Semantics(
        button: true,
        selected: selected,
        label: tab.label,
        child: TKey(
          latched: selected,
          led: selected,
          onTap: tab.onTap,
          onLongPress: tab.onLongPress,
          child: Icon(_hairline[tab.icon] ?? tab.icon, color: Tactile.ink, size: 22),
        ),
      );
    }
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
            dimension: size,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(size / 2)),
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
/// nav to the full search bar; the tabs left of Search slide out past its left edge and the ones
/// right of it out past the right (clipped by the pill); the Search icon glides to the bar's start;
/// the field slides in after them and the close button scales in beside it (0 → 100 %, a slight
/// overshoot). Each part has its own stretch of the timeline, so they follow one another. Closing
/// plays it backwards; pulling the list down plays it under the finger.
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

class _NavSearchState extends State<_NavSearch> with TickerProviderStateMixin {
  // Slower than the app's usual snap so every step of the morph can be seen.
  late final _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 384), // opening (search motion 1.5× quicker: was 576)
    reverseDuration: const Duration(milliseconds: 207), // closing: quicker, out of the way (was 311)
    value: widget.active ? 1 : 0,
  );

  /// 0 big tabs … 1 small (SearchDock.shrunk).
  late final _size = AnimationController(vsync: this, duration: Motion.snapDuration, value: SearchDock.shrunk.value ? 1 : 0);

  void _onShrunk() => SearchDock.shrunk.value ? _size.forward() : _size.reverse();

  @override
  void initState() {
    super.initState();
    SearchDock.shrunk.addListener(_onShrunk);
  }

  /// How far the pull has got towards opening search (0–1).
  double get _pulled => widget.pull == null ? 0 : (widget.pull!.value / widget.pullFull).clamp(0.0, 1.0);

  @override
  void didUpdateWidget(_NavSearch old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _t.value = math.max(_t.value, _pulled); // opened by a pull: carry on from where the finger left it
      _t.forward();
    } else {
      _t.reverse();
    }
  }

  @override
  void dispose() {
    SearchDock.shrunk.removeListener(_onShrunk);
    _size.dispose();
    _t.dispose();
    super.dispose();
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// [p]'s progress through its stretch [from]–[to] of the timeline, eased.
  static double _span(double p, double from, double to, [Curve curve = Curves.easeInOutCubic]) => curve.transform(((p - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    const full = SearchDock.height, inset = _NavBar._inset, gap = _NavBar._gap;
    final n = widget.tabs.length;
    final searchAt = widget.tabs.indexWhere((t) => t.id == 'search');
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final barW = w - full - SearchDock.gap; // room for the close circle on the right
        return AnimatedBuilder(
          animation: Listenable.merge([_t, _size, if (widget.pull != null) widget.pull!]),
          builder: (context, _) {
            // Pulling the list down scrubs the morph like a seek bar: it's wherever the finger is,
            // forwards and back. Opening / closing search plays it on its own.
            final p = widget.active || _t.isAnimating ? _t.value : _pulled;
            final t = _span(p, 0, .8); // the pill widens
            final slide = _span(p, 0, .65, Curves.easeInCubic); // tabs slide out, picking up speed
            final fade = _span(p, .3, .65, Curves.easeIn); // …and fade once they're on their way
            final glide = _span(p, .1, .8); // the Search icon to the bar's start
            final field = _span(p, .5, 1, Curves.easeOutCubic); // the field slides in after them
            final close = _span(p, .6, 1, Curves.easeOutBack);
            // Scrolled: smaller tabs (the search bar is always full height, so the morph grows it back).
            final tab = _lerp(_NavBar.big, _NavBar.small, Curves.easeInOut.transform(_size.value) * (1 - t));
            final navH = tab + inset * 2;
            final h = _lerp(navH, full, t); // the pill's height, kept on the dock's bottom edge
            final navW = inset * 2 + n * tab + (n - 1) * gap;
            final pillW = _lerp(navW, barW, t);
            final pillLeft = _lerp((w - navW) / 2, 0, t);
            final navLeft = (pillW - navW) / 2; // the tabs' row, centred in the pill
            // Each tab's way out: left of Search past the pill's left edge, right of it past the
            // right edge, keeping their spacing (in the row's own coordinates).
            final shift = [
              for (var i = 0; i < n; i++)
                slide *
                    (i < searchAt
                        ? -navLeft - (i + 1) * (tab + gap)
                        : i > searchAt
                        ? pillW - navLeft - inset - (searchAt + 1) * (tab + gap) + gap
                        : 0.0),
            ];
            // The Search icon's centre: on its tab at rest, at the bar's start (16 + 12) when searching.
            final iconX = _lerp(navLeft + inset + searchAt * (tab + gap) + tab / 2, 32, glide);
            final searching = widget.active || p > 0;
            final radius = BorderRadius.circular(DS.third ? _trayRadius : 99); // Tactile: a squared-off tray, like the keys
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: pillLeft,
                  top: full - h,
                  width: pillW,
                  height: h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(borderRadius: radius, boxShadow: Perf.lite.value ? null : (DS.third ? Tactile.proud : SearchDock.shadow)),
                    child: _surface(
                      h,
                      lcd: searching,
                      ClipRRect(
                        borderRadius: radius, // tabs leaving are cut by the pill's round ends
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
                                left: navLeft,
                                top: (h - navH) / 2,
                                width: navW,
                                height: navH,
                                child: IgnorePointer(
                                  ignoring: searching,
                                  child: Opacity(
                                    opacity: 1 - fade,
                                    child: _NavBar(selected: widget.selected, tabs: widget.tabs, bare: true, hide: searching ? 'search' : null, shift: shift, tab: tab),
                                  ),
                                ),
                              ),
                            if (searching) ...[
                              Positioned(
                                key: const ValueKey('icon'),
                                left: iconX - 12,
                                top: (h - 24) / 2,
                                child: Icon(Icons.search_rounded, color: DS.third ? TLcd.text : DS.ink, size: 24),
                              ),
                              Positioned(
                                key: const ValueKey('field'),
                                left: 52,
                                right: DS.s16,
                                top: 0,
                                bottom: 0,
                                child: Opacity(
                                  opacity: field,
                                  child: Transform.translate(
                                    offset: Offset(_lerp(32, 0, field), 0),
                                    child: Center(
                                      child: TextField(
                                        controller: widget.controller,
                                        focusNode: widget.focus,
                                        onChanged: widget.onChanged,
                                        onSubmitted: widget.onSubmitted,
                                        textInputAction: TextInputAction.go,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        cursorColor: DS.third ? TLcd.text : DS.ink,
                                        cursorWidth: DS.third ? 9 : 2, // Tactile: a block cursor, like the display's
                                        style: DS.third ? _lcdText : DS.rowTitle.copyWith(fontWeight: FontWeight.w500),
                                        decoration: InputDecoration.collapsed(
                                          hintText: DS.third ? widget.hint.toUpperCase() : widget.hint,
                                          hintStyle: DS.third ? _lcdText.copyWith(color: TLcd.text.withValues(alpha: .5)) : DS.rowSub,
                                        ),
                                      ),
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
                ),
                if (close > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    width: full,
                    height: full,
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

/// The bar's body: glass / the lowest surface with an outline, or in Tactile a recessed tray.
/// [lcd]: searching — the tray lights up as a display strip.
Widget _surface(double height, Widget child, {bool lcd = false}) => DS.third
    ? TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: lcd ? TLcd.glass : Tactile.well),
        duration: Motion.snapDuration,
        builder: (context, c, child) => CustomPaint(painter: WellPainter(radius: _trayRadius, floor: c!, depth: 2.5), child: child),
        child: child,
      )
    : glassOr(colour: DS.base, shape: StadiumBorder(side: SearchDock.border), child: child);

/// Tactile's search text: the display's readout (mono, tracked, upper case as typed).
TextStyle get _lcdText => TextStyle(fontFamily: 'monospace', fontSize: 16, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: TLcd.text);

/// Tactile prints its glyphs in hairline (outlined) form, like the legends on hardware.
final _hairline = <IconData, IconData>{
  Icons.home_rounded: Icons.home_outlined,
  Icons.search_rounded: Icons.search_outlined,
  Icons.lightbulb_rounded: Icons.lightbulb_outline_rounded,
  Icons.tune_rounded: Icons.tune_outlined,
};

/// Tactile's tray corners: the keys' (12) plus the 4 dp gutter, so the two nest.
const _trayRadius = 16.0;
