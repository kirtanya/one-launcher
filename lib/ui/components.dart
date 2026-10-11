import 'package:flutter/material.dart';

import 'ds.dart';
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
    return Pressable(
      enabled: onTap != null,
      scale: 0.98,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(DS.rCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
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
  const MetaRow({super.key, required this.icon, required this.text, this.color = DS.inkFaint, this.strong});
  final IconData icon;
  final String text;
  final Color color;
  final String? strong; // darker trailing part ("by **HabitsJournal**")

  @override
  Widget build(BuildContext context) {
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
  const CardDivider({super.key, this.color = DS.hairline});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color);
}
