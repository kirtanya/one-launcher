import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../prefs.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'header_fonts.dart';
import 'pages.dart';

/// The swipeable top half: Clock, Screen time, Battery, Up next — whichever the user
/// switched on, in their order. Pages snap; neighbours fade and shrink a little as you swipe.
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
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _page(String id) => switch (id) {
    'screen_time' => ScreenTimePage(refresh: widget.refresh),
    'battery' => BatteryPage(refresh: widget.refresh),
    'up_next' => UpNextPage(refresh: widget.refresh),
    'now_playing' => const NowPlayingPage(),
    'blank' => const SizedBox.expand(), // only the wallpaper
    _ when id.startsWith('widget:') => AppWidgetPage(widgetId: int.parse(id.substring(7)), label: widget.prefs.widgetLabels[id] ?? 'Widget'),
    _ => ClockPage(onTap: widget.onTapClock, onTapDate: widget.onTapDate),
  };

  @override
  Widget build(BuildContext context) {
    final ids = widget.prefs.topPages;
    final index = _index.clamp(0, ids.length - 1);
    return Column(
      children: [
        Expanded(
          child: HeaderFontScope(
            style: headerFontById(widget.prefs.headerFont).style,
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
                  final d = (page - i).abs().clamp(0.0, 1.0);
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
        if (ids.length > 1)
          AnimatedOpacity(
            duration: Motion.snapDuration,
            opacity: ids[index] == 'blank' ? 0 : 1,
            child: Padding(
              padding: const EdgeInsets.only(top: DS.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < ids.length; i++)
                    AnimatedContainer(
                      duration: Motion.snapDuration,
                      curve: Motion.settle,
                      width: i == index ? 18 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == index ? DS.onWallpaper : DS.glassLine,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
