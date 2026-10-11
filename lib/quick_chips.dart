import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'prefs.dart';
import 'quick_actions.dart';
import 'sheets.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';

/// Row of quick-action pills floating on the wallpaper just above the app sheet; scrolls
/// sideways and ends with ＋ to customise. Dark frosted pills so they read on any wallpaper.
class QuickChipsRow extends StatelessWidget {
  const QuickChipsRow({super.key, required this.prefs});

  /// Height of the row, and the gap it keeps from the sheet's top edge.
  static const height = 48.0, gap = DS.s8;
  final Prefs prefs;

  Future<void> _run(BuildContext context, String id, String label) async {
    HapticFeedback.selectionClick();
    final ok = await Apps.instance.quickAction(id);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn’t open “$label” on this phone'), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = prefs.quickLabels;
    final ids = prefs.quickChips.where((id) => builtInActions.containsKey(id) || labels.containsKey(id)).toList();
    void customise() {
      HapticFeedback.mediumImpact();
      showCustomiseChips(context, prefs: prefs);
    }

    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DS.s12),
        children: [
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(right: DS.s8),
              child: builtInActions.containsKey(id)
                  ? (id == 'b:torch'
                        // Flashlight lights up while it's on (even if switched on elsewhere).
                        ? ValueListenableBuilder<bool>(
                            valueListenable: Apps.instance.torchOn,
                            builder: (context, on, _) => QuickChip(
                              label: builtInActions[id]!.$1,
                              icon: Icon(on ? Icons.flashlight_on_rounded : builtInActions[id]!.$2, size: 18, color: on ? DS.heroInk : DS.onWallpaper),
                              active: on,
                              onTap: () => _run(context, id, builtInActions[id]!.$1),
                              onLongPress: customise,
                            ),
                          )
                        : QuickChip(
                            label: builtInActions[id]!.$1,
                            icon: Icon(builtInActions[id]!.$2, size: 18, color: DS.onWallpaper),
                            onTap: () => _run(context, id, builtInActions[id]!.$1),
                            onLongPress: customise,
                          ))
                  : QuickChip(
                      label: labels[id]!.split('|').first,
                      icon: ShortcutIcon(id: id, size: 20, color: DS.onWallpaper),
                      onTap: () => _run(context, id, labels[id]!.split('|').first),
                      onLongPress: customise,
                    ),
            ),
          // ＋ to customise.
          Pressable(
            scale: .9,
            child: Tooltip(
              message: 'Customise quick actions',
              child: Material(
                color: DS.chipOnWallpaper,
                shape: StadiumBorder(side: BorderSide(color: DS.glassLine)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: customise,
                  child: const SizedBox(
                    width: DS.tap,
                    height: 40,
                    child: Icon(Icons.add_rounded, color: DS.onCanvas, size: 20),
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

/// One quick-action pill: icon + label on the card colour (hero colour while active).
class QuickChip extends StatelessWidget {
  const QuickChip({super.key, required this.label, required this.icon, required this.onTap, this.onLongPress, this.active = false});
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Pressable(
        scale: .94,
        child: Material(
          color: active ? DS.hero : DS.chipOnWallpaper,
          shape: StadiumBorder(side: BorderSide(color: active ? DS.hero : DS.glassLine)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: DS.rowTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: active ? DS.heroInk : DS.ink),
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

/// An app shortcut's own icon (falls back to a generic one).
class ShortcutIcon extends StatelessWidget {
  const ShortcutIcon({super.key, required this.id, this.size = 20, this.color});
  final String id;
  final double size;
  final Color? color; // fallback icon colour

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<Uint8List?>(
        future: Apps.instance.shortcutIcon(id),
        builder: (context, snap) => snap.data == null
            ? Icon(Icons.bolt_rounded, size: size * .9, color: color ?? DS.ink)
            : ClipRRect(borderRadius: BorderRadius.circular(size / 4), child: Image.memory(snap.data!, gaplessPlayback: true)),
      ),
    );
  }
}
