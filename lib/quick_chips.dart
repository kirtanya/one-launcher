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
  const ChipLook({
    this.tone = 'dark',
    this.opacity = .4,
    this.shape = 'pill',
    this.height = 40,
    this.content = 'both',
    this.outline = true,
    this.gap = 8,
    this.padding,
    this.iconPadding = 0,
    this.space,
  });

  factory ChipLook.of(Prefs prefs) {
    final m = prefs.chipLook;
    const d = ChipLook();
    double? num_(String k, double lo, double hi) => (m[k] as num?)?.toDouble().clamp(lo, hi);
    return ChipLook(
      tone: m['tone'] as String? ?? d.tone,
      opacity: num_('opacity', .1, 1) ?? d.opacity,
      shape: m['shape'] as String? ?? d.shape,
      // Older looks saved a size name (Small / Regular / Large) instead of a height.
      height: num_('height', minHeight, maxHeight) ?? heights[m['size']] ?? d.height,
      content: m['content'] as String? ?? d.content,
      outline: m['outline'] as bool? ?? d.outline,
      gap: num_('gap', 0, maxGap) ?? d.gap,
      padding: num_('padding', 0, maxPadding),
      iconPadding: num_('iconPadding', 0, maxIconPadding) ?? d.iconPadding,
      space: num_('space', 0, maxSpace),
    );
  }

  final String tone, shape, content;
  final double opacity;
  final bool outline;

  /// Chip height (Size slider).
  final double height;

  /// Space between two chips.
  final double gap;

  /// Space inside a chip, at the label's end (its start is ¾ of it); null = follows the size.
  final double? padding;

  /// Icon only: space between the chip's edge and its icon (0 = the icon fills the chip).
  final double iconPadding;

  /// Space above and below the row; null = follows the size.
  final double? space;

  static const minHeight = 28.0, maxHeight = 60.0, maxGap = 24.0, maxPadding = 32.0, maxIconPadding = 16.0, maxSpace = 32.0;

  static const tones = {'dark': 'Dark', 'light': 'Light', 'accent': 'Accent', 'card': 'Card'};
  static const shapes = {'pill': 'Pill', 'rounded': 'Rounded', 'square': 'Square'};
  static const sizes = {'small': 'Small', 'regular': 'Regular', 'large': 'Large'};
  static const heights = {'small': 32.0, 'regular': 40.0, 'large': 48.0};
  static const contents = {'both': 'Icon + label', 'icon': 'Icon only', 'text': 'Label only'};

  /// The nearest size name (Tiles still picks from Small / Regular / Large).
  String get size => height < 36 ? 'small' : (height > 44 ? 'large' : 'regular');

  /// Opacity a colour starts at when picked (glass tones see-through, solid ones full).
  static double defaultOpacity(String tone) => switch (tone) {
    'light' => .3,
    'dark' => .4,
    _ => 1,
  };

  Map<String, Object> toJson() => {
    'tone': tone,
    'opacity': opacity,
    'shape': shape,
    'height': height,
    'content': content,
    'outline': outline,
    'gap': gap,
    'padding': ?padding,
    'iconPadding': iconPadding,
    'space': ?space,
  };

  /// [size] picks a preset height (Tiles' Small / Regular / Large).
  ChipLook copyWith({
    String? tone,
    double? opacity,
    String? shape,
    String? size,
    double? height,
    String? content,
    bool? outline,
    double? gap,
    double? padding,
    double? iconPadding,
    double? space,
  }) => ChipLook(
    tone: tone ?? this.tone,
    opacity: opacity ?? this.opacity,
    shape: shape ?? this.shape,
    height: height ?? heights[size] ?? this.height,
    content: content ?? this.content,
    outline: outline ?? this.outline,
    gap: gap ?? this.gap,
    padding: padding ?? this.padding,
    iconPadding: iconPadding ?? this.iconPadding,
    space: space ?? this.space,
  );

  /// Values that follow the height pass through the old Small / Regular / Large ones (32 / 40 / 48).
  double _bySize(double small, double regular, double large) =>
      height <= 40 ? regular + (height - 40) / 8 * (regular - small) : regular + (height - 40) / 8 * (large - regular);

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

  /// Space above and below the chips in the Classic row; unless set, grows with the chip so
  /// bigger chips don't feel cramped against the sheet and the page above.
  double get rowPad => space ?? _bySize(4, 8, 12).clamp(0, maxSpace);
  double get rowHeight => height + rowPad * 2;

  /// Space inside a label chip at its end.
  double get padEnd => padding ?? height * .4;

  double get iconSize => _bySize(16, 18, 22);

  /// Icon only: the box an app shortcut's icon fills (the chip less its icon padding); the
  /// glyph of a built-in action grows with it.
  double get iconOnlyBox => (height - iconPadding * 2).clamp(12, height);
  double get iconOnlyGlyph => iconOnlyBox * .62;

  /// Icon only: an app icon's corners follow the chip's, inset by the padding.
  double get iconOnlyRadius => (radius - iconPadding).clamp(2, iconOnlyBox / 2);

  double get fontSize => _bySize(13, 14, 15);
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

  /// Height of the row (the chips plus their breathing room), and the gap it keeps from the sheet's top edge.
  static double heightOf(Prefs prefs) => ChipLook.of(prefs).rowHeight;
  static const gap = DS.s8;
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
    final iconOnly = look.content == 'icon';
    final glyph = iconOnly ? look.iconOnlyGlyph : look.iconSize;
    void customise() {
      HapticFeedback.mediumImpact();
      showCustomiseChips(context, prefs: prefs);
    }

    return SizedBox(
      height: look.rowHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        children: [
          for (final id in ids)
            Padding(
              padding: EdgeInsets.only(right: look.gap),
              child: builtInActions.containsKey(id)
                  ? (id == 'b:torch'
                        // Flashlight lights up while it's on (even if switched on elsewhere).
                        ? ValueListenableBuilder<bool>(
                            valueListenable: Apps.instance.torchOn,
                            builder: (context, on, _) => QuickChip(
                              look: look,
                              label: builtInActions[id]!.$1,
                              icon: Icon(on ? Icons.flashlight_on_rounded : builtInActions[id]!.$2, size: glyph, color: on ? DS.heroInk : look.ink),
                              active: on,
                              onTap: () => _run(context, id, builtInActions[id]!.$1),
                              onLongPress: chipLongPress ? customise : null,
                            ),
                          )
                        : QuickChip(
                            look: look,
                            label: builtInActions[id]!.$1,
                            icon: Icon(builtInActions[id]!.$2, size: glyph, color: look.ink),
                            onTap: () => _run(context, id, builtInActions[id]!.$1),
                            onLongPress: chipLongPress ? customise : null,
                          ))
                  : QuickChip(
                      look: look,
                      label: labels[id]!.split('|').first,
                      icon: iconOnly
                          ? ShortcutIcon(id: id, size: look.iconOnlyBox, radius: look.iconOnlyRadius, fallbackSize: glyph, color: look.ink)
                          : ShortcutIcon(id: id, size: look.iconSize + 2, color: look.ink),
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
                      width: iconOnly ? look.height : math.max(look.height, 40),
                      height: look.height,
                      child: Icon(Icons.add_rounded, color: look.ink, size: iconOnly ? glyph : look.iconSize + 2),
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
                width: iconOnly ? h : null, // icon only: a circle/square around the icon
                child: iconOnly
                    ? Center(child: icon)
                    : Padding(
                        padding: EdgeInsets.fromLTRB(textOnly ? look.padEnd : look.padEnd * .75, 0, look.padEnd, 0),
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
  const ShortcutIcon({super.key, required this.id, this.size = 20, this.radius, this.fallbackSize, this.color});
  final String id;
  final double size;
  final double? radius; // corner of the icon (default a quarter of its size)
  final double? fallbackSize; // the generic icon's size (default almost the full size)
  final Color? color; // fallback icon colour

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<Uint8List?>(
        future: Apps.instance.shortcutIcon(id),
        builder: (context, snap) => snap.data == null
            ? Icon(Icons.bolt_rounded, size: fallbackSize ?? size * .9, color: color ?? DS.ink)
            : ClipRRect(borderRadius: BorderRadius.circular(radius ?? size / 4), child: Image.memory(snap.data!, gaplessPlayback: true)),
      ),
    );
  }
}
