import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'apps.dart';
import 'tokens.dart';

/// App icon from Android, or a letter tile while loading / in the web demo.
class AppIcon extends StatelessWidget {
  const AppIcon(this.app, {super.key, this.size = T.iconApp});
  final AppEntry app;
  final double size;

  static const _tiles = [Color(0xFF5B8DEF), Color(0xFF41B883), Color(0xFFF2994A), Color(0xFFBB6BD9), Color(0xFFEB5757), Color(0xFF2D9CDB), Color(0xFFE0B23A)];

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<Uint8List?>(
        future: Apps.instance.icon(app.package),
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes != null) return Image.memory(bytes, gaplessPlayback: true, filterQuality: FilterQuality.medium);
          return Container(
            decoration: BoxDecoration(color: _tiles[app.label.hashCode.abs() % _tiles.length], borderRadius: BorderRadius.circular(size / 2)),
            alignment: Alignment.center,
            child: Text(app.label.isEmpty ? '?' : app.label[0].toUpperCase(), style: TextStyle(color: T.ink, fontSize: size * .42, fontWeight: FontWeight.w600)),
          );
        },
      ),
    );
  }
}

/// One option in a bottom sheet: icon + label, full-width 56pt row.
class SheetAction {
  const SheetAction(this.icon, this.label, this.onTap, {this.danger = false, this.enabled = true, this.trailing});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool enabled;
  final Widget? trailing;
}

Future<void> showOneSheet(BuildContext context, {Widget? header, required List<SheetAction> actions}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: T.sheet,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(T.rSheet))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: T.s12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) Padding(padding: const EdgeInsets.fromLTRB(T.s24, 0, T.s24, T.s12), child: header),
            for (final a in actions) _SheetRow(a),
          ],
        ),
      ),
    ),
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow(this.a);
  final SheetAction a;

  @override
  Widget build(BuildContext context) {
    final color = !a.enabled ? T.inkFaint : (a.danger ? T.danger : T.ink);
    return InkWell(
      onTap: a.enabled ? a.onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.s24),
          child: Row(children: [
            Icon(a.icon, color: color, size: 22),
            const SizedBox(width: T.s16),
            Expanded(child: Text(a.label, style: T.appName.copyWith(color: color))),
            if (a.trailing != null) a.trailing!,
          ]),
        ),
      ),
    );
  }
}

class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.leading});
  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      if (leading != null) ...[leading!, const SizedBox(width: T.s16)],
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: T.appName.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: T.body, maxLines: 1, overflow: TextOverflow.ellipsis)],
        ]),
      ),
    ]);
  }
}
