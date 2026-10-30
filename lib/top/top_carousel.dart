import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../prefs.dart';
import '../third/tactile/parts.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import '../ui/perf.dart';
import 'header_fonts.dart';
import 'now_page.dart';
import 'pages.dart';

/// The swipeable top half: Clock, Screen time, Battery, Up next — whichever the user
/// switched on, in their order. Pages snap; neighbours fade and shrink a little as you swipe.
/// Page 0 is always the Now page (now_page.dart); home opens on page 1.
class TopCarousel extends StatefulWidget {
  const TopCarousel({super.key, required this.prefs, required this.refresh, required this.onTapClock, required this.onTapDate, this.onBlank});
  final Prefs prefs;
  final Listenable refresh;
  final VoidCallback onTapClock, onTapDate;
  final ValueChanged<bool>? onBlank; // true while the "Just wallpaper" page is showing

  @override
  State<TopCarousel> createState() => _TopCarouselState();
}

class _TopCarouselState extends State<TopCarousel> {
  final _pages = PageController(initialPage: 1);
  int _index = 1;

  @override
  void initState() {
    super.initState();
    _pages.addListener(_track);
  }

  void _track() {
    if (_pages.position.haveDimensions) nowAway.value = (_pages.page ?? 1).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    nowAway.value = 1;
    _pages.dispose();
    super.dispose();
  }

  Widget _page(String id) => id == 'now' || id == 'blank' || id.startsWith('widget:') ? _content(id) : _FitMin(child: _content(id));

  Widget _content(String id) => switch (id) {
    'screen_time' => ScreenTimePage(refresh: widget.refresh),
    'battery' => BatteryPage(refresh: widget.refresh),
    'up_next' => UpNextPage(refresh: widget.refresh),
    'now_playing' => const NowPlayingPage(),
    'now' => const NowPage(),
    'tv_remote' => TvRemotePage(prefs: widget.prefs),
    'blank' => const SizedBox.expand(), // only the wallpaper
    _ when id.startsWith('widget:') => AppWidgetPage(widgetId: int.parse(id.substring(7)), label: widget.prefs.widgetLabels[id] ?? 'Widget'),
    _ => ClockPage(onTap: widget.onTapClock, onTapDate: widget.onTapDate),
  };

  @override
  Widget build(BuildContext context) {
    final ids = ['now', ...widget.prefs.topPages];
    final index = _index.clamp(0, ids.length - 1);
    // A tight top area (small split, big padding, tall quick chips row) gives the pages all of it.
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          Expanded(
            child: HeaderFontScope(
              style: clockStyleOf(widget.prefs),
              child: PageView.builder(
                controller: _pages,
                itemCount: ids.length,
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => _index = i);
                  widget.onBlank?.call(ids[i] == 'blank');
                },
                itemBuilder: (context, i) => AnimatedBuilder(
                  animation: _pages,
                  child: KeyedSubtree(key: ValueKey(ids[i]), child: _page(ids[i])),
                  builder: (context, child) {
                    final page = _pages.hasClients && _pages.position.haveDimensions ? (_pages.page ?? 0) : index.toDouble();
                    final d = Perf.lite.value ? 0.0 : (page - i).abs().clamp(0.0, 1.0); // lighter effects: no page fade
                    return Opacity(
                      opacity: 1 - d * .6,
                      child: Transform.scale(scale: 1 - d * .08, alignment: Alignment.centerLeft, child: child),
                    );
                  },
                ),
              ),
            ),
          ),
          // Page dots (only when there's more than one page); hidden on the wallpaper-only page.
          if (ids.length > 1 && box.maxHeight >= 48)
            AnimatedOpacity(
              duration: Motion.snapDuration,
              opacity: ids[index] == 'blank' ? 0 : 1,
              child: Padding(
                padding: const EdgeInsets.only(top: DS.s4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < ids.length; i++)
                      if (DS.third) // Tactile: a row of LEDs, the current page lit
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: TLed(on: i == index, size: 6))
                      else
                      AnimatedContainer(
                        duration: Motion.snapDuration,
                        curve: Motion.settle,
                        width: i == index ? 18 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(color: i == index ? DS.onWallpaper : DS.glassLine, borderRadius: BorderRadius.circular(3)),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Gives a page at least [min] points of height: if the top area is shorter (tiny split,
/// big padding, status bar), the whole page scales down instead of overflowing.
class _FitMin extends StatelessWidget {
  const _FitMin({required this.child});
  final Widget child;
  static const min = 96.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxHeight >= min || !c.hasBoundedHeight) return child;
      return FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topLeft,
        child: SizedBox(width: c.maxWidth * min / c.maxHeight.clamp(1, min), height: min, child: child),
      );
    },
  );
}
