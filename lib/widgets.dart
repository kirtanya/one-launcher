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

/// Result of a 2nd-level sheet closed with its back arrow (or system back): the caller
/// reopens the sheet it came from.
const sheetBack = 'back';

/// [scrollable]: the content scrolls when taller than ~90% of the screen. Pass false for
/// sheets that already scroll a list of their own (Flexible + ListView inside).
/// [back]: a 2nd-level sheet — shows a back arrow, and back / tapping outside return
/// [sheetBack] so the caller can reopen the level above. Swiping it down closes everything.
Future<Object?> showOneSheetWith(BuildContext context, {required WidgetBuilder builder, bool scrollable = true, bool back = false}) {
  return showModalBottomSheet<Object?>(
    context: context,
    // The sheet paints its own background and handle (below) so they follow live theme
    // changes — the route's own colour is fixed when it opens.
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    builder: (ctx) => PopScope(
      canPop: !back,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(ctx, sheetBack);
      },
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(DS.rCard)),
        // A Material (not a plain box) so rows keep their tap ripples.
        child: Material(
          color: DS.card,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: DS.s12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle (+ back arrow on a 2nd-level sheet).
                  SizedBox(
                    height: back ? 52 : 36,
                    child: Stack(
                      children: [
                        Center(
                          child: Container(
                            width: 32,
                            height: 4,
                            decoration: BoxDecoration(color: DS.hairline, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        if (back)
                          Positioned(
                            left: DS.s12,
                            top: DS.s4,
                            child: IconButton(
                              tooltip: 'Back',
                              icon: Icon(Icons.arrow_back_rounded, color: DS.ink),
                              onPressed: () => Navigator.pop(ctx, sheetBack),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: scrollable
                        ? ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .9),
                            child: SingleChildScrollView(child: builder(ctx)),
                          )
                        : builder(ctx),
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
