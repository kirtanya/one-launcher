import 'package:flutter/material.dart';

import '../third/tactile/parts.dart';
import '../third/tactile/tactile.dart';
import 'ds.dart';
import 'glass.dart';
import 'motion.dart';

/// A stacked card. `tone` picks the surface from the design system.
enum CardTone { hero, white, muted }

class OneCard extends StatelessWidget {
  const OneCard({super.key, required this.child, this.tone = CardTone.white, this.padding = const EdgeInsets.all(DS.pad), this.onTap, this.onLongPress});
  final Widget child;
  final CardTone tone;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  Color get color => switch (tone) {
    CardTone.hero => DS.hero,
    CardTone.white => DS.card,
    CardTone.muted => DS.cardMuted,
  };

  @override
  Widget build(BuildContext context) {
    // Tactile: a moulded plate.
    if (DS.third) return TPlate(radius: DS.rCard, color: color, padding: padding, onTap: onTap, onLongPress: onLongPress, child: child);
    final ink = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(padding: padding, child: child),
    );
    return Pressable(
      enabled: onTap != null,
      scale: 0.98,
      child: Glass.classic
          // Glass: a tinted pane (the frosted drawer behind it does the blur).
          ? GlassPane(
              colour: color,
              frost: false,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rCard)),
              child: ink,
            )
          : Material(color: color, borderRadius: BorderRadius.circular(DS.rCard), clipBehavior: Clip.antiAlias, child: ink),
    );
  }
}

enum CircleTone { ink, soft, outline, onCanvas, glass }

/// 44pt round action with a 48pt tap area.
class CircleButton extends StatelessWidget {
  const CircleButton({super.key, required this.icon, required this.onTap, this.tone = CircleTone.ink, this.tooltip, this.turns = 0, this.size = DS.circle});
  final IconData icon;
  final VoidCallback onTap;
  final CircleTone tone;
  final String? tooltip;
  final double turns; // rotate the icon (e.g. expand chevron)
  final double size; // visual diameter; the tap area stays 48

  @override
  Widget build(BuildContext context) {
    // Tactile: a round key (on the wallpaper too: hardware doesn't go see-through).
    if (DS.third) {
      final key = SizedBox.square(
        dimension: DS.tap,
        child: Center(
          child: TKey(
            width: size,
            height: size,
            radius: size / 2,
            onTap: onTap,
            child: AnimatedRotation(
              turns: turns,
              duration: Motion.snapDuration,
              curve: Motion.snap,
              child: Icon(icon, size: size * .45, color: Tactile.ink),
            ),
          ),
        ),
      );
      return tooltip == null ? key : Tooltip(message: tooltip!, child: key);
    }
    final (bg, fg, border) = switch (tone) {
      CircleTone.ink => (DS.ink, DS.card, null),
      CircleTone.soft => (DS.heroSoft, DS.heroInk, null),
      CircleTone.outline => (Colors.transparent, DS.ink, DS.hairline),
      CircleTone.onCanvas => (Colors.transparent, DS.onCanvas, DS.onCanvasLine),
      CircleTone.glass => (DS.glass, DS.onWallpaper, DS.glassLine),
    };
    final button = SizedBox.square(
      dimension: DS.tap,
      child: Center(
        child: Material(
          color: bg,
          shape: CircleBorder(side: border == null ? BorderSide.none : BorderSide(color: border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: size,
              child: AnimatedRotation(
                turns: turns,
                duration: Motion.snapDuration,
                curve: Motion.snap,
                child: Icon(icon, size: size * 0.45, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
    final pressable = Pressable(scale: 0.88, child: button);
    return tooltip == null ? pressable : Tooltip(message: tooltip!, child: pressable);
  }
}

/// Small white stadium that sits inside a headline ("High ↗").
class InlinePill extends StatelessWidget {
  const InlinePill(this.text, {super.key, this.color = DS.alert, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: DS.card, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: DS.pill.copyWith(color: color)),
          if (icon != null) ...[const SizedBox(width: 3), Icon(icon, size: 13, color: color)],
        ],
      ),
    );
  }
}

/// Black stadium with a big number over a small word ("11 / Fri").
class DatePill extends StatelessWidget {
  const DatePill({super.key, required this.big, required this.small});
  final String big;
  final String small;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DS.datePillW,
      height: DS.datePillH,
      decoration: BoxDecoration(color: DS.ink, borderRadius: BorderRadius.circular(99)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(big, style: DS.rowTitle.copyWith(color: DS.card, fontSize: 18, height: 1.1)),
          Text(
            small,
            style: DS.pill.copyWith(color: DS.card.withValues(alpha: .75), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Icon + muted text, e.g. "📅 10 Thu" or "🌐 by HabitsJournal".
class MetaRow extends StatelessWidget {
  const MetaRow({super.key, required this.icon, required this.text, this.color, this.strong});
  final IconData icon;
  final String text;
  final Color? color; // defaults to DS.inkFaint
  final String? strong; // darker trailing part ("by **HabitsJournal**")

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? DS.inkFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text.rich(
          TextSpan(
            text: text,
            style: DS.meta.copyWith(color: color),
            children: [if (strong != null) TextSpan(text: strong, style: DS.rowTitle.copyWith(fontSize: 14))],
          ),
        ),
      ],
    );
  }
}

/// Hairline divider in the card's tone.
class CardDivider extends StatelessWidget {
  const CardDivider({super.key, this.color});
  final Color? color; // defaults to DS.hairline

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color ?? DS.hairline);
}

/// Ask before a reset, clear or forget: a small dialog with Cancel and [action] (in red).
/// True only when confirmed.
Future<bool> confirmReset(BuildContext context, {required String title, required String body, String action = 'Reset'}) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (d) => AlertDialog(
        backgroundColor: DS.card,
        title: Text(title, style: DS.title.copyWith(fontSize: 20)),
        content: Text(body, style: DS.rowSub),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text('Cancel', style: DS.rowTitle.copyWith(color: DS.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(action, style: DS.rowTitle.copyWith(color: const Color(0xFFE5534B))),
          ),
        ],
      ),
    ) ==
    true;

/// What a surface is, not how it looks — each design language draws the role its own way:
/// Classic / Metro a Material of [SurfaceRole]'s colour; Tactile moulded plastic (a plate that
/// stands off the panel, a key you press, or a recess). Screens ask for a role; the language
/// decides the look (docs/DESIGN_LANGUAGES.md).
enum SurfaceRole { raised, key, recessed }

class RoleSurface extends StatelessWidget {
  const RoleSurface({super.key, this.role = SurfaceRole.raised, required this.color, required this.shape, required this.child, this.selected = false});
  final SurfaceRole role;

  /// Classic / Metro's fill.
  final Color color;
  final ShapeBorder shape;
  final Widget child;

  /// A chosen key / card: Tactile shows it pressed in (latched), with a faint glow of light.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (!DS.third) return Material(color: color, shape: shape, clipBehavior: Clip.antiAlias, child: child);
    final outlined = switch (shape) {
      RoundedRectangleBorder(:final borderRadius) => RoundedRectangleBorder(borderRadius: borderRadius, side: BorderSide(color: Tactile.rim, width: .6)),
      StadiumBorder() => StadiumBorder(side: BorderSide(color: Tactile.rim, width: .6)),
      CircleBorder() => CircleBorder(side: BorderSide(color: Tactile.rim, width: .6)),
      _ => shape,
    };
    final inner = Material(type: MaterialType.transparency, shape: outlined, clipBehavior: Clip.antiAlias, child: child);
    if (role == SurfaceRole.recessed) {
      final r = switch (shape) {
        RoundedRectangleBorder(:final borderRadius) => borderRadius.resolve(TextDirection.ltr).topLeft.x,
        _ => 999.0,
      };
      return LayoutBuilder(
        builder: (context, c) => CustomPaint(
          painter: WellPainter(radius: r == 999.0 ? c.biggest.shortestSide / 2 : r, floor: Tactile.well, depth: 2),
          child: inner,
        ),
      );
    }
    final key = role == SurfaceRole.key;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      transform: Matrix4.translationValues(0, selected ? 1.5 : 0, 0),
      decoration: ShapeDecoration(
        shape: outlined,
        gradient: key
            ? Tactile.capFace()
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(Tactile.plate, Colors.white, Tactile.dark ? .04 : .35)!, Tactile.plate],
                stops: const [0, .1],
              ),
        shadows: selected ? Tactile.raised(pressed: true) : (key ? Tactile.raised() : Tactile.plateShadow),
      ),
      foregroundDecoration: selected
          ? ShapeDecoration(
              shape: outlined,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: Tactile.dark ? .22 : .07), Tactile.light.withValues(alpha: .06)],
              ),
            )
          : null,
      child: inner,
    );
  }
}
