import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'apps.dart';
import 'ui/ds.dart';

/// App icon from Android, or a letter tile while loading / in the web demo.
class AppIcon extends StatelessWidget {
  const AppIcon(this.app, {super.key, this.size = DS.appIcon});
  final AppEntry app;
  final double size;

  static const _tiles = [Color(0xFF5B8DEF), Color(0xFF41B883), Color(0xFFF2994A), Color(0xFFBB6BD9), Color(0xFFEB5757), Color(0xFF2D9CDB), Color(0xFFE0B23A)];

  @override
  Widget build(BuildContext context) {
    final icon = _icon();
    // Paused work apps look switched off, like on the system launcher.
    if (!app.paused) return icon;
    return Opacity(
      opacity: .5,
      child: ColorFiltered(colorFilter: const ColorFilter.matrix([.33, .33, .33, 0, 0, .33, .33, .33, 0, 0, .33, .33, .33, 0, 0, 0, 0, 0, 1, 0]), child: icon),
    );
  }

  Widget _icon() {
    final ready = Apps.instance.iconNow(app.package);
    if (ready != null) {
      return SizedBox.square(
        dimension: size,
        child: Image(image: ready, gaplessPlayback: true, filterQuality: FilterQuality.medium),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<Uint8List?>(
        future: Apps.instance.icon(app.package),
        builder: (context, snap) {
          final bytes = snap.data;
          final img = Apps.instance.iconNow(app.package);
          if (bytes != null && img != null) return Image(image: img, gaplessPlayback: true, filterQuality: FilterQuality.medium);
          return Container(
            decoration: BoxDecoration(color: _tiles[app.label.hashCode.abs() % _tiles.length], borderRadius: BorderRadius.circular(size / 2)),
            alignment: Alignment.center,
            child: Text(
              app.label.isEmpty ? '?' : app.label[0].toUpperCase(),
              style: TextStyle(fontFamily: DS.font, color: DS.card, fontSize: size * .42, fontWeight: FontWeight.w600),
            ),
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

/// White rounded sheet in the One design style (see docs/DESIGN_STYLE.md).
Future<void> showOneSheet(BuildContext context, {Widget? header, required List<SheetAction> actions}) {
  return showOneSheetWith(
    context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) Padding(padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s12), child: header),
        for (final a in actions) _SheetRow(a),
      ],
    ),
  );
}

Future<void> showOneSheetWith(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: DS.card,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(DS.rCard))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: DS.s12),
        child: builder(ctx),
      ),
    ),
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow(this.a);
  final SheetAction a;

  @override
  Widget build(BuildContext context) {
    final color = !a.enabled ? DS.inkFaint : (a.danger ? DS.alert : DS.ink);
    return InkWell(
      onTap: a.enabled ? a.onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s24),
          child: Row(
            children: [
              Icon(a.icon, color: color, size: 22),
              const SizedBox(width: DS.s16),
              Expanded(
                child: Text(
                  a.label,
                  style: DS.rowTitle.copyWith(color: color, fontWeight: FontWeight.w500),
                ),
              ),
              if (a.trailing != null) a.trailing!,
            ],
          ),
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
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: DS.s16)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DS.title.copyWith(fontSize: 20)),
              if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: DS.rowSub, maxLines: 1, overflow: TextOverflow.ellipsis)],
            ],
          ),
        ),
      ],
    );
  }
}
