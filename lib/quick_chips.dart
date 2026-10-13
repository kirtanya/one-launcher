import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'prefs.dart';
import 'remote_sheet.dart';
import 'quick_actions.dart';
import 'sheets.dart';
import 'ui/ds.dart';
import 'ui/glass.dart';
import 'ui/motion.dart';

/// The user's look for the quick-action chips (Quick actions → Chip look). Defaults are the
/// original dark frosted pill.
class ChipLook {
  const ChipLook({this.tone = 'dark', this.opacity = .4, this.shape = 'pill', this.size = 'regular', this.content = 'both', this.outline = true});

  factory ChipLook.of(Prefs prefs) {
    final m = prefs.chipLook;
    const d = ChipLook();
    return ChipLook(
      tone: m['tone'] as String? ?? d.tone,
      opacity: (m['opacity'] as num?)?.toDouble().clamp(.1, 1.0) ?? d.opacity,
      shape: m['shape'] as String? ?? d.shape,
      size: m['size'] as String? ?? d.size,
      content: m['content'] as String? ?? d.content,
      outline: m['outline'] as bool? ?? d.outline,
    );
  }

  final String tone, shape, size, content;
  final double opacity;
  final bool outline;

  static const tones = {'dark': 'Dark', 'light': 'Light', 'accent': 'Accent', 'card': 'Card'};
  static const shapes = {'pill': 'Pill', 'rounded': 'Rounded', 'square': 'Square'};
  static const sizes = {'small': 'Small', 'regular': 'Regular', 'large': 'Large'};
  static const contents = {'both': 'Icon + label', 'icon': 'Icon only', 'text': 'Label only'};

  /// Opacity a colour starts at when picked (glass tones see-through, solid ones full).
  static double defaultOpacity(String tone) => switch (tone) {
    'light' => .3,
    'dark' => .4,
    _ => 1,
  };

  Map<String, Object> toJson() => {'tone': tone, 'opacity': opacity, 'shape': shape, 'size': size, 'content': content, 'outline': outline};
  ChipLook copyWith({String? tone, double? opacity, String? shape, String? size, String? content, bool? outline}) => ChipLook(
    tone: tone ?? this.tone,
    opacity: opacity ?? this.opacity,
    shape: shape ?? this.shape,
    size: size ?? this.size,
    content: content ?? this.content,
    outline: outline ?? this.outline,
  );

  Color get fill => switch (tone) {
    'light' => const Color(0xFFFFFFFF),
    'accent' => DS.hero,
    'card' => DS.card,
    _ => const Color(0xFF141414),
  }.withValues(alpha: opacity);

  /// Text and icon colour: dark on light glass at higher opacity, light on see-through ones.
  Color get ink => switch (tone) {
    'light' => opacity >= .5 ? const Color(0xFF141414) : DS.onWallpaper,
    'accent' => opacity >= .5 ? DS.heroInk : DS.onWallpaper,
    'card' => opacity >= .5 ? DS.ink : DS.onWallpaper,
    _ => DS.onWallpaper,
  };

  Color get line => tone == 'light' && opacity >= .5 ? const Color(0x1F000000) : DS.glassLine;
  double get height => switch (size) {
    'small' => 32,
    'large' => 48,
    _ => 40,
  };
  double get iconSize => switch (size) {
    'small' => 16,
    'large' => 22,
    _ => 18,
  };
  double get fontSize => switch (size) {
    'small' => 13,
    'large' => 15,
    _ => 14,
  };
  double get radius => switch (shape) {
    'rounded' => 12,
    'square' => 6,
    _ => height / 2,
  };
  ShapeBorder border({Color? lineColor}) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: outline || lineColor != null ? BorderSide(color: lineColor ?? line) : BorderSide.none,
  );

  String get summary => '${tones[tone]} · ${(opacity * 100).round()}% · ${shapes[shape]}';
}

/// Row of quick-action pills floating on the wallpaper just above the app sheet; scrolls
/// sideways and ends with ＋ to customise. Dark frosted pills so they read on any wallpaper.
class QuickChipsRow extends StatelessWidget {
  const QuickChipsRow({super.key, required this.prefs, this.padding = const EdgeInsets.symmetric(horizontal: DS.s12), this.chipLongPress = true});

  /// Space at the row's ends (none on Tiles: Start's own margins line it up).
  final EdgeInsets padding;

  /// Long-press a chip to customise. Off on Tiles, where long-press picks the whole row up.
  final bool chipLongPress;

  /// Height of the row, and the gap it keeps from the sheet's top edge.
  static const height = 48.0, gap = DS.s8;
  final Prefs prefs;

  Future<void> _run(BuildContext context, String id, String label) async {
    HapticFeedback.selectionClick();
    if (id == 'b:remote') return showTvRemote(context, prefs: prefs); // ours, not the phone's
    final ok = await Apps.instance.quickAction(id);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn’t open “$label” on this phone'), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = ChipLook.of(prefs);
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
        padding: padding,
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
                              look: look,
                              label: builtInActions[id]!.$1,
                              icon: Icon(on ? Icons.flashlight_on_rounded : builtInActions[id]!.$2, size: look.iconSize, color: on ? DS.heroInk : look.ink),
                              active: on,
                              onTap: () => _run(context, id, builtInActions[id]!.$1),
                              onLongPress: chipLongPress ? customise : null,
                            ),
                          )
                        : QuickChip(
                            look: look,
                            label: builtInActions[id]!.$1,
                            icon: Icon(builtInActions[id]!.$2, size: look.iconSize, color: look.ink),
                            onTap: () => _run(context, id, builtInActions[id]!.$1),
                            onLongPress: chipLongPress ? customise : null,
                          ))
                  : QuickChip(
                      look: look,
                      label: labels[id]!.split('|').first,
                      icon: ShortcutIcon(id: id, size: look.iconSize + 2, color: look.ink),
                      onTap: () => _run(context, id, labels[id]!.split('|').first),
                      onLongPress: chipLongPress ? customise : null,
                    ),
            ),
          // ＋ to customise.
          Pressable(
            scale: .9,
            child: Tooltip(
              message: 'Customise quick actions',
              child: Center(
                child: Material(
                  color: look.fill,
                  shape: look.border(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: customise,
                    child: SizedBox(
                      width: math.max(look.height, 40),
                      height: look.height,
                      child: Icon(Icons.add_rounded, color: look.ink, size: look.iconSize + 2),
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

/// One quick-action chip, drawn in the user's [look]; the hero colour while active.
class QuickChip extends StatelessWidget {
  const QuickChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.active = false,
    this.look = const ChipLook(),
  });
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool active;
  final ChipLook look;

  @override
  Widget build(BuildContext context) {
    final iconOnly = look.content == 'icon', textOnly = look.content == 'text';
    final h = look.height;
    return Center(
      child: Pressable(
        scale: .94,
        child: Tooltip(
          message: iconOnly ? label : '',
          child: glassOr(
            colour: active ? DS.hero : look.fill,
            shape: look.border(lineColor: active ? DS.hero : null),
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: SizedBox(
                height: h,
                width: iconOnly ? math.max(h, 40) : null,
                child: iconOnly
                    ? Center(child: icon)
                    : Padding(
                        padding: EdgeInsets.fromLTRB(textOnly ? h * .4 : h * .3, 0, h * .4, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!textOnly) ...[icon, SizedBox(width: h * .2)],
                            Text(
                              label,
                              style: DS.rowTitle.copyWith(fontSize: look.fontSize, fontWeight: FontWeight.w500, color: active ? DS.heroInk : look.ink),
                            ),
                          ],
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
