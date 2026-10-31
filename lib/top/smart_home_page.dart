import 'package:flutter/material.dart';

import '../quick_lights.dart';
import '../smart_home.dart';
import '../smart_home_sheet.dart';
import '../ui/ds.dart';

/// Top page "Smart home" (off until switched on in the top pages): quick light control (all,
/// a room or one light: on/off, brightness, colour); its title opens the full sheet.
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: DS.s8),
                decoration: ShapeDecoration(
                  color: const Color(0x59000000), // black ~35%: darker glass
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: DS.glassLine),
                  ),
                ),
                // QuickLights picks full / compact / header-only from the space left.
                child: QuickLights(
                  ink: DS.onWallpaper,
                  soft: DS.clockInk,
                  onOpen: () => showSmartHome(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
