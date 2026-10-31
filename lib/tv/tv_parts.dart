import 'package:flutter/material.dart';

import 'tv_real.dart';
import '../third/tactile/tactile.dart';
import '../third/tactile/parts.dart';

import '../apps.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';
import 'tv_metro.dart';

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
              AnimatedContainer(
                duration: Motion.pressIn * 2,
                width: TvDS.tileW,
                height: TvDS.tileH,
                // Ring + glow only on the focused tile (one blur on screen at a time). Tiles: the
                // Metro frame and corners.
                foregroundDecoration: TvMetro.on ? TvMetro.frame(f, width: TvDS.focusRing) : TvRing(on: f, radius: TvDS.rTile),
                decoration: BoxDecoration(
                  borderRadius: TvMetro.corners(TvDS.rTile),
                  boxShadow: TvMetro.on ? TvMetro.glow(f) : (f ? const [BoxShadow(color: TvDS.glow, blurRadius: 18)] : null),
                ),
                child: ClipRRect(
                  borderRadius: TvMetro.corners(TvDS.rTile),
                  child: TvAppArt(app: app, width: TvDS.tileW),
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
/// An app as a circle (Customise → App cards → Circle): its own icon filling it, or its initial
/// on a quiet disc until the icon arrives. The round clip comes from the card.
class TvAppIcon extends StatelessWidget {
  const TvAppIcon({super.key, required this.app, required this.size});
  final AppEntry app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ready = TvApps.instance.iconNow(app.package);
    Widget view(ImageProvider? icon) => ColoredBox(
      color: TvDS.surface,
      child: Center(
        child: icon != null
            // TV app icons are squares with their own background: they fill the circle, which crops them.
            ? Image(image: icon, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium)
            : Text(app.label.isEmpty ? '?' : app.label[0].toUpperCase(), style: TvDS.tileName.copyWith(fontSize: size * .36)),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: ready != null ? view(ready) : FutureBuilder<MemoryImage?>(future: TvApps.instance.icon(app.package), builder: (context, s) => view(s.data)),
    );
  }
}

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
      color: TvMetro.on ? TvMetro.tileFill : TvDS.surface, // Tiles: an accent tile
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 44 * s,
            child: icon != null
                ? Image(image: icon, gaplessPlayback: true, filterQuality: FilterQuality.medium)
                : DecoratedBox(
                    decoration: TvMetro.on
                        ? BoxDecoration(color: Colors.white24, borderRadius: TvMetro.corners(0))
                        : BoxDecoration(color: DS.hero, shape: BoxShape.circle),
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
  const TvAction(this.icon, this.label, this.onSelect, {this.danger = false, this.keepOpen = false, this.swatch, this.selected = false, this.value});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool danger;
  final bool keepOpen; // e.g. clock presets: try several without reopening
  final Color? swatch; // a colour dot instead of the icon (colour picker)
  final bool selected; // a tick at the end
  final String? value; // current setting, shown on the right ("Artwork")
}

/// Options slide in from the right, like the TV's own menus. The remote's Back goes where the
/// panel's own ← row goes (Back / Cancel: the page it came from), else [onBack], else closes.
/// [refresh] + [build]: a panel that updates in place (e.g. ticking quick actions on and off).
Future<void> showTvPanel(
  BuildContext context, {
  required String title,
  Widget? leading,
  List<TvAction> actions = const [],
  Listenable? refresh,
  List<TvAction> Function()? build,
  VoidCallback? onBack,
}) {
  VoidCallback? back() => onBack ?? (build?.call() ?? actions).where((a) => a.icon == Icons.arrow_back_rounded).firstOrNull?.onSelect;
  return showGeneralDialog(
    context: context,
    barrierDismissible: false, // a tap beside the panel closes it (below); Back goes up a level
    barrierLabel: 'Close',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) => PopScope(
      // A row picked or a tap beside the panel closes with `true`; Back on the remote (no result)
      // goes up a level.
      onPopInvokedWithResult: (didPop, picked) {
        if (!didPop || picked != null) return;
        final up = back();
        if (up != null) Future.microtask(up); // once this pop is done (the navigator is busy now)
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => Navigator.pop(ctx, true)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: DS.third ? Colors.transparent : (TvMetro.on ? DS.card : const Color(0xFF1C1C1C)), // Tiles: Metro's near-black, flat
              child: Container(
                decoration: DS.third ? TvReal.panel : null, // Real: a moulded plate
                child: SizedBox(
                  width: 440,
                  height: double.infinity,
                  child: FocusTraversalGroup(
                    child: ListenableBuilder(
                      listenable: refresh ?? const AlwaysStoppedAnimation(0),
                      builder: (ctx, _) {
                        final actions2 = build?.call() ?? actions;
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(DS.s32, 40, DS.s32, 40),
                          children: [
                            if (leading != null) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ClipRRect(borderRadius: TvMetro.corners(TvDS.rTile), child: leading),
                              ),
                              const SizedBox(height: DS.s16),
                            ],
                            TvMetro.on
                                ? Text(TvMetro.cased(title), style: TvMetro.title(size: 34), maxLines: 2, overflow: TextOverflow.ellipsis)
                                : DS.third
                                ? Text(title.toUpperCase(), style: TvReal.legend(24), maxLines: 2, overflow: TextOverflow.ellipsis)
                                : Text(title, style: TvDS.panelTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: DS.s24),
                            for (final (i, a) in actions2.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: DS.s8),
                                child: TvFocusable(
                                  autofocus: i == 0,
                                  onSelect: () {
                                    if (!a.keepOpen) Navigator.pop(ctx, true);
                                    a.onSelect();
                                  },
                                  builder: (context, f) => TvMetro.on
                                      ? _MetroRow(action: a, focused: f)
                                      : AnimatedContainer(
                                          duration: Motion.pressIn * 2,
                                          height: 52,
                                          padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                                          decoration: DS.third
                                              ? TvReal.key(focused: f) // Real: the focused row is a key, lit by its indicator
                                              : BoxDecoration(color: f ? TvDS.surfaceFocused : Colors.transparent, borderRadius: BorderRadius.circular(26)),
                                          child: Row(
                                            children: [
                                              if (a.swatch != null)
                                                Container(
                                                  width: 22,
                                                  height: 22,
                                                  decoration: BoxDecoration(
                                                    color: a.swatch,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: TvDS.line),
                                                  ),
                                                )
                                              else
                                                Icon(
                                                  a.icon,
                                                  size: 22,
                                                  color: a.danger ? DS.alert : (f ? (DS.third ? Tactile.light : TvDS.onLight) : TvDS.inkMuted),
                                                ),
                                              const SizedBox(width: DS.s16),
                                              Expanded(
                                                child: Text(
                                                  a.label,
                                                  style: TvDS.panelRow.copyWith(color: f && !DS.third ? TvDS.onLight : TvDS.ink),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (a.value != null)
                                                Text(
                                                  a.value!,
                                                  style: TvDS.panelRow.copyWith(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w400,
                                                    color: f && !DS.third ? TvDS.onLightMuted : TvDS.inkMuted,
                                                  ),
                                                ),
                                              if (a.selected)
                                                DS.third
                                                    ? Padding(
                                                        padding: const EdgeInsets.only(left: 8),
                                                        child: TLed(on: true, size: 8),
                                                      ) // Real: the chosen one's lamp
                                                    : Icon(Icons.check_rounded, size: 22, color: f ? TvDS.onLight : TvDS.ink),
                                            ],
                                          ),
                                        ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    transitionBuilder: (ctx, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(.3, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: a, child: child),
    ),
  );
}

/// The focus ring, drawn just outside the card with a small gap of background between them, so
/// it stays visible on a white picture or a white app logo.
class TvRing extends Decoration {
  const TvRing({required this.on, required this.radius, this.width = TvDS.focusRing, this.gap = TvDS.focusGap});
  final bool on;
  final double radius, width, gap;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _TvRingPainter(this);
}

class _TvRingPainter extends BoxPainter {
  _TvRingPainter(this.ring);
  final TvRing ring;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    if (!ring.on || configuration.size == null) return;
    final out = ring.gap + ring.width / 2; // centre of the stroke, beyond the gap
    final rect = (offset & configuration.size!).inflate(out);
    if (DS.third) return TvReal.paintRing(canvas, RRect.fromRectAndRadius(rect, Radius.circular(ring.radius + out)), ring.width); // Real: phosphor light
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(ring.radius + out)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.width
        ..color = TvDS.surfaceFocused
        ..isAntiAlias = true,
    );
  }
}

/// A calm colour from a name (same name → same colour): used where there's no artwork.
Color tvTint(String name) => HSLColor.fromAHSL(1, (name.hashCode % 360).abs().toDouble(), .38, .42).toColor();

/// Darkens a full-bleed picture into the canvas: from the left (behind text) and the bottom,
/// plus a light veil at the top.
class TvScrims extends StatelessWidget {
  const TvScrims({super.key, this.strength = 1, this.colour, this.cinema = false});
  final double strength; // Customise → Background darkness (×, clamped)
  final Color? colour; // what the picture fades into (default the canvas)

  /// The home's full-screen picture: a dark fade behind the title on the left, a deep one under
  /// the rows, a light veil for the top bar and a soft vignette at the edges, like a cinema screen.
  final bool cinema;

  @override
  Widget build(BuildContext context) {
    final c = colour ?? TvDS.canvas;
    double a(double x) => (x * strength).clamp(0, 1).toDouble();
    if (cinema) {
      return IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    c.withValues(alpha: a(.88)),
                    c.withValues(alpha: a(.66)),
                    c.withValues(alpha: a(.24)),
                    c.withValues(alpha: 0),
                  ],
                  stops: const [0, .26, .5, .7],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.withValues(alpha: a(.5)),
                    c.withValues(alpha: 0),
                    c.withValues(alpha: 0),
                    c.withValues(alpha: a(.72)),
                    c.withValues(alpha: a(.94)),
                  ],
                  stops: const [0, .22, .36, .6, .82],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(.3, -.3),
                  radius: 1.25,
                  colors: [
                    c.withValues(alpha: 0),
                    c.withValues(alpha: 0),
                    c.withValues(alpha: a(.45)),
                  ],
                  stops: const [0, .55, 1],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  c,
                  c.withValues(alpha: (.92 * strength).clamp(0, 1)),
                  c.withValues(alpha: (.35 * strength).clamp(0, 1)),
                  c.withValues(alpha: 0),
                ],
                stops: const [0, .3, .55, .75],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  TvDS.scrim.withValues(alpha: (.35 * strength).clamp(0, 1)),
                  c.withValues(alpha: 0),
                  c.withValues(alpha: (.85 * strength).clamp(0, 1)),
                  c,
                ],
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
        builder: (context, f) => TvMetro.on
            ? _metro(f)
            : AnimatedContainer(
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
                      Icon(icon, size: 22, color: f ? TvDS.onLight : TvDS.ink),
                    const SizedBox(width: DS.s12),
                    Text(label, style: TvDS.panelRow.copyWith(fontSize: 15, color: f ? TvDS.onLight : TvDS.ink)),
                    if (detail != null) ...[
                      const SizedBox(width: DS.s8),
                      Text(
                        detail!,
                        style: TvDS.panelRow.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: f ? TvDS.onLightMuted : TvDS.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  /// Tiles: an accent tile button — flat, the tile corners, lowercase; focus is the Metro frame.
  Widget _metro(bool f) => AnimatedContainer(
    duration: Motion.pressIn * 2,
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: DS.s16),
    decoration: BoxDecoration(color: TvMetro.tileFill, borderRadius: TvMetro.corners(0), boxShadow: TvMetro.glow(f)),
    foregroundDecoration: TvMetro.frame(f, width: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ClipRRect(borderRadius: TvMetro.corners(0), child: leading) else if (icon != null) Icon(icon, size: 22, color: Colors.white),
        const SizedBox(width: DS.s12),
        Text(TvMetro.cased(label), style: TvDS.panelRow.copyWith(fontSize: 15, color: Colors.white)),
        if (detail != null) ...[
          const SizedBox(width: DS.s8),
          Text(
            TvMetro.cased(detail!),
            style: TvDS.panelRow.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white70),
          ),
        ],
      ],
    ),
  );
}

/// A side-panel row in Tiles (Metro): the icon on a small accent tile (or a square colour
/// swatch), the label in Metro's case, the value muted; focus is the Metro frame — no white pill.
class _MetroRow extends StatelessWidget {
  const _MetroRow({required this.action, required this.focused});
  final TvAction action;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final a = action, f = focused;
    final r = TvMetro.corners(0);
    return AnimatedContainer(
      duration: Motion.pressIn * 2,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: DS.s12),
      decoration: BoxDecoration(color: f ? const Color(0x14FFFFFF) : Colors.transparent, borderRadius: r, boxShadow: TvMetro.glow(f)),
      foregroundDecoration: TvMetro.frame(f, width: 2),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: a.swatch ?? (a.danger ? DS.alert : TvMetro.accent),
              borderRadius: BorderRadius.circular(TvMetro.radius(0) * .6),
              border: a.swatch != null ? Border.all(color: TvDS.line) : null,
            ),
            child: a.swatch != null ? null : Icon(a.icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: DS.s16),
          Expanded(
            child: Text(
              TvMetro.cased(a.label),
              style: TvDS.panelRow.copyWith(fontWeight: FontWeight.w400, color: a.danger ? DS.alert : Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (a.value != null)
            Text(
              TvMetro.cased(a.value!),
              style: TvDS.panelRow.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: f ? TvMetro.accentText : TvDS.inkMuted),
            ),
          if (a.selected) Icon(Icons.check_rounded, size: 22, color: TvMetro.accentText),
        ],
      ),
    );
  }
}

/// Ask before a reset or clear: Cancel / [action]. Either way [back] (if given) reopens the
/// panel it came from.
void tvConfirm(BuildContext context, {required String title, required String action, required Future<void> Function() onConfirm, VoidCallback? back}) {
  showTvPanel(
    context,
    title: title,
    actions: [
      TvAction(Icons.arrow_back_rounded, 'Cancel', back ?? () {}),
      TvAction(Icons.restart_alt_rounded, action, () async {
        await onConfirm();
        back?.call();
      }, danger: true),
    ],
  );
}
