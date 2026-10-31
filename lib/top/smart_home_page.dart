import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../smart_home.dart';
import '../smart_home_sheet.dart';
import '../ui/components.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'pages.dart';

/// Top page "Smart home" (off until switched on in the top pages): the first few devices as
/// big toggle pills, and "All devices" to open the full sheet.
class SmartHomePage extends StatefulWidget {
  const SmartHomePage({super.key, required this.refresh});
  final Listenable refresh;

  @override
  State<SmartHomePage> createState() => _SmartHomePageState();
}

class _SmartHomePageState extends State<SmartHomePage> {
  @override
  void initState() {
    super.initState();
    SmartHome.instance.refresh();
    widget.refresh.addListener(SmartHome.instance.refresh);
  }

  @override
  void dispose() {
    widget.refresh.removeListener(SmartHome.instance.refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = DS.wallpaperDate;
    return ValueListenableBuilder<SmartHomeState>(
      valueListenable: SmartHome.instance.state,
      builder: (context, s, _) {
        final ready = s.status == SmartHomeStatus.ready;
        // Online devices first, lights before the rest; up to 4.
        final shown =
            ([...s.devices]..sort(
                  (a, b) =>
                      (a.online ? 0 : 2) +
                      (a.type == SmartType.light ? 0 : 1) -
                      ((b.online ? 0 : 2) +
                          (b.type == SmartType.light ? 0 : 1)),
                ))
                .take(4)
                .toList();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Smart home',
                        style: label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ready)
                      GlassPill(
                        onTap: () => showSmartHome(context),
                        child: Text(
                          'All devices',
                          style: DS.wallpaperDate.copyWith(
                            fontSize: 14,
                            shadows: const [],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ready && shown.isNotEmpty
                    ? LayoutBuilder(
                        builder: (context, c) {
                          const h = 44.0;
                          final rows = ((c.maxHeight + DS.s8) ~/ (h + DS.s8))
                              .clamp(1, 2);
                          final w = (c.maxWidth - DS.s8) / 2;
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Wrap(
                              spacing: DS.s8,
                              runSpacing: DS.s8,
                              children: [
                                for (final d in shown.take(rows * 2))
                                  SizedBox(
                                    width: w,
                                    height: h,
                                    child: _Pill(device: d),
                                  ),
                              ],
                            ),
                          );
                        },
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                ready
                                    ? 'No devices yet'
                                    : 'Control your lights, plugs and AC',
                                style: DS.wallpaperDate.copyWith(
                                  fontSize: 14,
                                  color: DS.clockInk,
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: DS.s12),
                            GlassPill(
                              onTap: () => showSmartHome(context),
                              child: Text(
                                'Set up',
                                style: DS.wallpaperDate.copyWith(
                                  fontSize: 14,
                                  shadows: const [],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.device});
  final SmartDevice device;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final lit = d.on && d.online;
    return Opacity(
      opacity: d.online ? 1 : .5,
      child: Pressable(
        scale: .96,
        enabled: d.online,
        child: RoleSurface(
          role: SurfaceRole.key,
          selected: lit,
          color: lit ? DS.hero : DS.glass,
          shape: StadiumBorder(
            side: BorderSide(color: lit ? DS.hero : DS.glassLine),
          ),
          child: Semantics(
            button: true,
            label: '${d.name}, ${smartSub(d)}',
            child: InkWell(
              onTap: d.online
                  ? () {
                      HapticFeedback.selectionClick();
                      SmartHome.instance.toggle(d);
                    }
                  : null,
              onLongPress: () => showSmartHome(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s12),
                child: Row(
                  children: [
                    Icon(
                      smartIcon(d.type),
                      size: 20,
                      color: lit ? DS.heroInk : DS.onWallpaper,
                    ),
                    const SizedBox(width: DS.s8),
                    Expanded(
                      child: Text(
                        d.name,
                        style: DS.wallpaperDate.copyWith(
                          fontSize: 14,
                          shadows: const [],
                          color: lit ? DS.heroInk : DS.onWallpaper,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
