import 'package:flutter/material.dart';

import '../apps.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';

/// Shared TV pieces: app tiles + artwork, the options side panel, search.

PageRoute<void> tvFade(Widget page) => PageRouteBuilder(
  pageBuilder: (_, _, _) => page,
  transitionDuration: const Duration(milliseconds: 220),
  reverseTransitionDuration: const Duration(milliseconds: 160),
  transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
);

// ---- Tiles -------------------------------------------------------------------

class TvAppTile extends StatelessWidget {
  const TvAppTile({super.key, required this.app, required this.focusNode, required this.onSelect, required this.onOptions, this.onMove, this.onFocus});
  final AppEntry app;
  final FocusNode? focusNode;
  final VoidCallback onSelect, onOptions;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: app.label,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onLongSelect: onOptions,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => SizedBox(
          width: TvDS.tileW,
          child: Column(
            children: [
              const SizedBox(height: TvDS.rowPadTop),
              AnimatedScale(
                scale: f ? TvDS.focusScale : 1,
                duration: Motion.popDuration,
                curve: Motion.pop,
                child: AnimatedContainer(
                  duration: Motion.pressIn * 2,
                  width: TvDS.tileW,
                  height: TvDS.tileH,
                  // Ring + glow only on the focused tile (one blur on screen at a time).
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    border: Border.all(color: f ? TvDS.surfaceFocused : Colors.transparent, width: TvDS.focusRing),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    boxShadow: f ? const [BoxShadow(color: TvDS.glow, blurRadius: 18)] : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(TvDS.rTile),
                    child: TvAppArt(app: app, width: TvDS.tileW),
                  ),
                ),
              ),
              const SizedBox(height: DS.s12),
              // Name under the focused tile — banners are just artwork; icon tiles already show it.
              AnimatedOpacity(
                opacity: f && (TvApps.instance.artNow(app.package)?.banner ?? false) ? 1 : 0,
                duration: Motion.pressIn * 2,
                child: Text(app.label, style: TvDS.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app's banner, or (no banner) its icon + name on a soft tile.
class TvAppArt extends StatelessWidget {
  const TvAppArt({super.key, required this.app, required this.width});
  final AppEntry app;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ready = TvApps.instance.artNow(app.package);
    return SizedBox(
      width: width,
      height: width * 9 / 16,
      child: ready != null
          ? _view(ready)
          : FutureBuilder<TvArt?>(future: TvApps.instance.art(app.package), builder: (context, s) => s.data != null ? _view(s.data!) : _fallback(null)),
    );
  }

  Widget _view(TvArt art) =>
      art.banner ? Image(image: art.image, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium) : _fallback(art.image);

  Widget _fallback(ImageProvider? icon) {
    final s = width / TvDS.tileW;
    return ColoredBox(
      color: TvDS.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 44 * s,
            child: icon != null
                ? Image(image: icon, gaplessPlayback: true, filterQuality: FilterQuality.medium)
                : DecoratedBox(
                    decoration: BoxDecoration(color: DS.hero, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        app.label.isEmpty ? '?' : app.label[0].toUpperCase(),
                        style: TvDS.tileName.copyWith(color: DS.heroInk, fontSize: 20 * s),
                      ),
                    ),
                  ),
          ),
          SizedBox(height: DS.s8 * s),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: DS.s8 * s),
            child: Text(
              app.label,
              style: TvDS.tileName.copyWith(fontSize: 13 * s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Side panel (options) ------------------------------------------------------

class TvAction {
  const TvAction(this.icon, this.label, this.onSelect, {this.danger = false, this.keepOpen = false});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool danger;
  final bool keepOpen; // e.g. clock presets: try several without reopening
}

/// Options slide in from the right, like the TV's own menus. Back closes.
Future<void> showTvPanel(BuildContext context, {required String title, Widget? leading, required List<TvAction> actions}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: const Color(0xFF1C1C1C),
        child: SizedBox(
          width: 380,
          height: double.infinity,
          child: FocusTraversalGroup(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(DS.s32, 40, DS.s32, 40),
              children: [
                if (leading != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(borderRadius: BorderRadius.circular(TvDS.rTile), child: leading),
                  ),
                  const SizedBox(height: DS.s16),
                ],
                Text(title, style: TvDS.panelTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: DS.s24),
                for (final (i, a) in actions.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DS.s8),
                    child: TvFocusable(
                      autofocus: i == 0,
                      onSelect: () {
                        if (!a.keepOpen) Navigator.pop(ctx);
                        a.onSelect();
                      },
                      builder: (context, f) => AnimatedContainer(
                        duration: Motion.pressIn * 2,
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                        decoration: BoxDecoration(color: f ? TvDS.surfaceFocused : Colors.transparent, borderRadius: BorderRadius.circular(26)),
                        child: Row(
                          children: [
                            Icon(a.icon, size: 22, color: f ? (a.danger ? DS.alert : DS.ink) : (a.danger ? DS.alert : TvDS.inkMuted)),
                            const SizedBox(width: DS.s16),
                            Expanded(
                              child: Text(
                                a.label,
                                style: TvDS.panelRow.copyWith(color: f ? DS.ink : TvDS.ink),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(.3, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: a, child: child),
    ),
  );
}

/// A calm colour from a name (same name → same colour): used where there's no artwork.
Color tvTint(String name) => HSLColor.fromAHSL(1, (name.hashCode % 360).abs().toDouble(), .38, .42).toColor();

/// Darkens a full-bleed picture into the canvas: from the left (behind text) and the bottom,
/// plus a light veil at the top.
class TvScrims extends StatelessWidget {
  const TvScrims({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TvDS.canvas;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c, c.withValues(alpha: .92), c.withValues(alpha: .35), c.withValues(alpha: 0)], stops: const [0, .3, .55, .75]),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [TvDS.scrim.withValues(alpha: .35), c.withValues(alpha: 0), c.withValues(alpha: .85), c],
                stops: const [0, .2, .58, .74],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill button: icon (or a small picture) + label (+ quiet detail); white when focused.
class TvActionPill extends StatelessWidget {
  const TvActionPill({super.key, required this.label, required this.onSelect, this.icon, this.leading, this.detail, this.focusNode, this.autofocus = false});
  final String label;
  final String? detail; // e.g. "Stream", "Rent"
  final VoidCallback onSelect;
  final IconData? icon;
  final Widget? leading;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        onSelect: onSelect,
        builder: (context, f) => AnimatedScale(
          scale: f ? 1.06 : 1,
          duration: Motion.popDuration,
          curve: Motion.pop,
          child: AnimatedContainer(
            duration: Motion.pressIn * 2,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: DS.s16),
            decoration: BoxDecoration(color: f ? TvDS.surfaceFocused : TvDS.surface, borderRadius: BorderRadius.circular(24)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null)
                  ClipRRect(borderRadius: BorderRadius.circular(6), child: leading)
                else if (icon != null)
                  Icon(icon, size: 22, color: f ? DS.ink : TvDS.ink),
                const SizedBox(width: DS.s12),
                Text(label, style: TvDS.panelRow.copyWith(fontSize: 15, color: f ? DS.ink : TvDS.ink)),
                if (detail != null) ...[
                  const SizedBox(width: DS.s8),
                  Text(
                    detail!,
                    style: TvDS.panelRow.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: f ? DS.inkMuted : TvDS.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
