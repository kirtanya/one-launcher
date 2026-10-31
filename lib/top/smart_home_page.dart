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
            child: LayoutBuilder(
              // Brightness and colour too when the page is tall enough.
              builder: (context, c) => Align(
                alignment: Alignment.topLeft,
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(DS.s12, DS.s4, DS.s4, DS.s8),
                    decoration: ShapeDecoration(
                      color: DS.glass,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: DS.glassLine),
                      ),
                    ),
                    child: QuickLights(
                      ink: DS.onWallpaper,
                      soft: DS.clockInk,
                      full: c.maxHeight >= 200,
                      onOpen: () => showSmartHome(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
