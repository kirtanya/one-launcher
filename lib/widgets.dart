import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'apps.dart';
import 'ui/ds.dart';
import 'ui/motion.dart';

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
/// [keyboard]: the sheet has a text field — its content makes room for the keyboard.
/// [barrier]: the shade behind the sheet (default when null).
/// [height]: the sheet's height cap; with [fill] it is exactly that tall (content scrolls).
Future<Object?> showOneSheetWith(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollable = true,
  bool back = false,
  double? height,
  bool fill = false,
  Color? barrier,
  bool keyboard = false,
}) {
  var searching = false; // a search field inside is active → the sheet goes full screen
  return showModalBottomSheet<Object?>(
    context: context,
    // The sheet paints its own background and handle (below) so they follow live theme
    // changes — the route's own colour is fixed when it opens.
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    barrierColor: barrier, // lighter for sheets that preview on the home screen behind them
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final screen = MediaQuery.sizeOf(ctx).height;
        // Searching breaks the usual height rule: full screen, room for results and keyboard.
        final full = searching;
        final grow = fill || full;
        return SheetSearchScope(
          onActive: (on) {
            if (on != searching) setSheet(() => searching = on);
          },
          child: PopScope(
            canPop: !back,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) Navigator.pop(ctx, sheetBack);
            },
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(DS.rCard)),
              // A Material (not a plain box) so rows keep their tap ripples.
              child: Material(
                color: DS.card,
                child: AnimatedContainer(
                  duration: Motion.snapDuration,
                  curve: Curves.easeOutCubic,
                  constraints: full
                      ? BoxConstraints.tightFor(height: screen)
                      : height == null
                      ? BoxConstraints(maxHeight: screen)
                      : (fill ? BoxConstraints.tightFor(height: height) : BoxConstraints(maxHeight: height)),
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: DS.s12 + (keyboard ? MediaQuery.viewInsetsOf(ctx).bottom : 0)),
                      child: Column(
                        mainAxisSize: grow ? MainAxisSize.max : MainAxisSize.min,
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
                            fit: grow ? FlexFit.tight : FlexFit.loose,
                            child: scrollable ? SingleChildScrollView(child: builder(ctx)) : builder(ctx),
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
      },
    ),
  );
}

/// Lets a search field inside a sheet tell the sheet it's searching (so it goes full screen).
class SheetSearchScope extends InheritedWidget {
  const SheetSearchScope({super.key, required this.onActive, required super.child});
  final ValueChanged<bool> onActive;

  static ValueChanged<bool>? of(BuildContext context) => context.getInheritedWidgetOfExactType<SheetSearchScope>()?.onActive;

  @override
  bool updateShouldNotify(SheetSearchScope old) => false;
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

/// True if every word of [query] appears in one of [fields] (case-insensitive). Empty matches all.
bool matchesQuery(String query, Iterable<String> fields) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final text = fields.join(' ').toLowerCase();
  return words.every(text.contains);
}

/// Search pill used inside sheets (widget picker, quick actions): icon, hint, clear button.
/// Owns its text controller (so it lives exactly as long as the field, close animation included).
class SheetSearchField extends StatefulWidget {
  const SheetSearchField({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<SheetSearchField> createState() => _SheetSearchFieldState();
}

class _SheetSearchFieldState extends State<SheetSearchField> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_report);
    _text.addListener(_report);
  }

  /// Searching = typing in the field, or a search still showing → the sheet goes full screen.
  void _report() => SheetSearchScope.of(context)?.call(_focus.hasFocus || _text.text.isNotEmpty);

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.s24, DS.s4, DS.s24, DS.s8),
      child: TextField(
        controller: _text,
        focusNode: _focus,
        onChanged: widget.onChanged,
        cursorColor: DS.ink,
        style: DS.rowTitle,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: DS.rowSub.copyWith(fontSize: 16),
          prefixIcon: Icon(Icons.search_rounded, color: DS.inkMuted),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _text,
            builder: (context, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear search',
                    icon: Icon(Icons.close_rounded, color: DS.inkMuted),
                    onPressed: () {
                      _text.clear();
                      widget.onChanged('');
                    },
                  ),
          ),
          filled: true,
          fillColor: DS.cardMuted,
          contentPadding: const EdgeInsets.symmetric(horizontal: DS.s20, vertical: DS.s12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(DS.s24), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
