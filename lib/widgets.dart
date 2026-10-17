import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'apps.dart';
import 'ui/ds.dart';
import 'ui/perf.dart';
import 'ui/glass.dart';
import 'ui/motion.dart';

/// App icon from Android, or a letter tile while loading / in the web demo.
class AppIcon extends StatelessWidget {
  const AppIcon(this.app, {super.key, this.size = DS.appIcon});
  final AppEntry app;
  final double size;

  /// Themed icons on (Settings → Colours & style): one-colour glyphs in the theme's colours,
  /// like Pixel. Apps without a glyph keep their own icon. Set by the app from prefs.
  static bool themed = false;

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

  Widget _icon() => themed ? _themed() : _plain();

  Widget _themed() {
    Widget circle(ImageProvider glyph) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: DS.hero, shape: BoxShape.circle),
      child: Image(image: glyph, color: DS.heroInk, colorBlendMode: BlendMode.srcIn, gaplessPlayback: true, filterQuality: FilterQuality.medium),
    );
    final ready = Apps.instance.monoNow(app.package);
    if (ready != null) return withWorkBadge(app, size, circle(ready));
    return FutureBuilder<Uint8List?>(
      future: Apps.instance.monoIcon(app.package),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return SizedBox.square(dimension: size);
        final glyph = Apps.instance.monoNow(app.package);
        return glyph != null ? withWorkBadge(app, size, circle(glyph)) : _plain();
      },
    );
  }

  Widget _plain() {
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

/// Work-profile glyphs (themed / tile icons) get a small briefcase at the bottom-right — the
/// full-colour icons already carry Android's own badge. Tiny icons (folder previews) skip it.
Widget withWorkBadge(AppEntry app, double size, Widget icon) {
  if (!app.work || size < 28) return icon;
  final d = (size * .4).clamp(14.0, 24.0);
  return Stack(
    clipBehavior: Clip.none,
    children: [
      icon,
      Positioned(
        right: -d * .15,
        bottom: -d * .15,
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            color: DS.ink,
            shape: BoxShape.circle,
            border: Border.all(color: DS.card, width: 1.5),
          ),
          child: Icon(Icons.work_rounded, size: d * .58, color: DS.card),
        ),
      ),
    ],
  );
}

/// One option in a bottom sheet: icon + label, full-width 56pt row.
class SheetAction {
  const SheetAction(this.icon, this.label, this.onTap, {this.danger = false, this.enabled = true, this.trailing, this.yours = false});
  final IconData icon;
  final String label;

  /// The label is the user's own content (a contact, a shortcut's name): never re-cased.
  final bool yours;
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
///
/// Sheets with a [height] are *paged*: opening another sheet from inside one (Settings → a
/// detail, Top of home → Clock style…) slides it in as a page of the same sheet, with a back
/// arrow — the sheet itself stays put. Called from inside such a sheet, this pushes a page.
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
  final host = SheetHost.maybeOf(context);
  if (host != null) return host.push(builder, scrollable: scrollable);
  final paged = height != null;
  final nav = GlobalKey<NavigatorState>();
  final depth = ValueNotifier<int>(0); // pages in a paged sheet (the observer counts the first too)
  final observer = _DepthObserver(depth); // one for the sheet's life (rebuilds must not reset it)
  var searching = false; // a search field inside is active → the sheet goes full screen
  return showModalBottomSheet<Object?>(
    context: context,
    // The sheet paints its own background and handle (below) so they follow live theme
    // changes — the route's own colour is fixed when it opens.
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    useRootNavigator: true,
    barrierColor: barrier, // lighter for sheets that preview on the home screen behind them
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final screen = MediaQuery.sizeOf(ctx).height;
        // Searching breaks the usual height rule: full screen, room for results and keyboard.
        final full = searching;
        final grow = fill || full || paged;
        void goBack() => (paged && depth.value > 1) ? nav.currentState!.pop() : Navigator.pop(ctx, sheetBack);
        final content = paged
            ? SheetHost._(
                nav: nav,
                sheet: ctx,
                child: Navigator(
                  key: nav,
                  observers: [observer..onEmpty = () => Navigator.pop(ctx)],
                  onGenerateInitialRoutes: (_, _) => [SheetHost._route(builder, scrollable: scrollable)],
                ),
              )
            : (scrollable ? SingleChildScrollView(child: builder(ctx)) : builder(ctx));
        return SheetSearchScope(
          onActive: (on) {
            if (on != searching) setSheet(() => searching = on);
          },
          child: ValueListenableBuilder<int>(
            valueListenable: depth,
            builder: (ctx, pages, child) {
              final showBack = back || pages > 1;
              return PopScope(
                canPop: !showBack,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) goBack();
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(DS.rCard)),
                  // Metro + glass tiles: the sheet is a frosted pane too.
                  child: _SheetGlass(
                    // A Material (not a plain box) so rows keep their tap ripples.
                    child: Material(
                      color: DS.metro && Glass.tiles ? DS.card.withValues(alpha: .88) : DS.card,
                      child: AnimatedContainer(
                        duration: Motion.snapDuration,
                        curve: Curves.easeOutCubic,
                        constraints: full
                            ? BoxConstraints.tightFor(height: screen)
                            : height == null
                            ? BoxConstraints(maxHeight: screen)
                            : (fill || paged ? BoxConstraints.tightFor(height: height) : BoxConstraints(maxHeight: height)),
                        child: SafeArea(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: DS.s12 + (keyboard ? MediaQuery.viewInsetsOf(ctx).bottom : 0)),
                            child: Column(
                              mainAxisSize: grow ? MainAxisSize.max : MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Drag handle (+ back arrow on a page below the first).
                                SizedBox(
                                  height: showBack ? 52 : 36,
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Container(
                                          width: 32,
                                          height: 4,
                                          decoration: BoxDecoration(color: DS.hairline, borderRadius: BorderRadius.circular(2)),
                                        ),
                                      ),
                                      if (showBack)
                                        Positioned(
                                          left: DS.s12,
                                          top: DS.s4,
                                          child: IconButton(
                                            tooltip: 'Back',
                                            icon: Icon(Icons.arrow_back_rounded, color: DS.ink),
                                            onPressed: goBack,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Flexible(fit: grow ? FlexFit.tight : FlexFit.loose, child: child!),
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
            child: content,
          ),
        );
      },
    ),
  );
}

/// The pages of a paged sheet (see [showOneSheetWith]): sheets opened inside it push here.
class SheetHost extends InheritedWidget {
  const SheetHost._({required this.nav, required this.sheet, required super.child});
  final GlobalKey<NavigatorState> nav;
  final BuildContext sheet; // the sheet's own route context (to close the whole sheet)

  static SheetHost? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<SheetHost>();

  /// Close the whole sheet (from any page), e.g. before opening a system screen.
  static void close(BuildContext context) {
    final host = maybeOf(context);
    host == null ? Navigator.pop(context) : Navigator.pop(host.sheet);
  }

  Future<Object?> push(WidgetBuilder builder, {bool scrollable = true}) => nav.currentState!.push<Object?>(_route(builder, scrollable: scrollable));

  /// A page: slides in from the right over the one before (which eases a little to the left).
  static Route<Object?> _route(WidgetBuilder builder, {required bool scrollable}) => PageRouteBuilder<Object?>(
    transitionDuration: Motion.snapDuration,
    reverseTransitionDuration: Motion.snapDuration,
    pageBuilder: (context, _, _) => Material(
      color: DS.card,
      child: scrollable ? SingleChildScrollView(child: Builder(builder: builder)) : Builder(builder: builder),
    ),
    transitionsBuilder: (context, a, b, child) {
      final inC = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      final outC = CurvedAnimation(parent: b, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(inC),
        child: SlideTransition(
          position: Tween(begin: Offset.zero, end: const Offset(-.25, 0)).animate(outC),
          child: child,
        ),
      );
    },
  );

  @override
  bool updateShouldNotify(SheetHost old) => false;
}

class _DepthObserver extends NavigatorObserver {
  _DepthObserver(this.depth);
  final ValueNotifier<int> depth;
  int _n = 0;

  /// The first page itself was popped (e.g. a page that closes itself when done): close the sheet.
  VoidCallback? onEmpty;

  // Routes change during builds (the first page arrives while the sheet builds): publish the
  // count right after the frame instead of mid-build.
  void _publish() {
    WidgetsBinding.instance.addPostFrameCallback((_) => depth.value = _n);
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _n++;
    _publish();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _n = (_n - 1).clamp(0, 99);
    _publish();
    if (_n == 0) WidgetsBinding.instance.addPostFrameCallback((_) => onEmpty?.call());
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    _n = (_n - 1).clamp(0, 99);
    _publish();
  }
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
                  a.yours ? a.label : DS.cased(a.label),
                  // Metro menus: larger, lighter, lowercase words.
                  style: DS.rowTitle.copyWith(color: color, fontWeight: DS.metro ? FontWeight.w400 : FontWeight.w500, fontSize: DS.metro ? 19 : null),
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

/// Marks a settings page shown in an editor (live preview above, controls below).
class EditorScope extends InheritedWidget {
  const EditorScope({super.key, required super.child});
  static bool within(BuildContext context) => context.getInheritedWidgetOfExactType<EditorScope>() != null;
  @override
  bool updateShouldNotify(EditorScope old) => false;
}

class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.leading, this.yours = false});
  final String title;

  /// The title is the user's own content (an app or folder name): never re-cased.
  final bool yours;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    // In a settings editor the title is already in its top bar: keep just the subtitle.
    if (leading == null && EditorScope.within(context)) {
      return subtitle == null ? const SizedBox.shrink() : Text(subtitle!, style: DS.rowSub);
    }
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: DS.s16)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(yours ? title : DS.cased(title), style: DS.metro ? DS.title.copyWith(fontSize: 28) : DS.title.copyWith(fontSize: 20)),
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

/// Metro sheets over glass tiles: blur what's behind (skipped with lighter effects).
class _SheetGlass extends StatelessWidget {
  const _SheetGlass({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DS.metro || !Glass.tiles || Glass.blur <= 0 || Perf.lite.value) return child;
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: Glass.blur, sigmaY: Glass.blur),
      child: child,
    );
  }
}

/// Owns a [TextEditingController] for exactly as long as its widget lives — for text fields in
/// sheets, which keep building while they animate closed (disposing on close crashes them).
class WithTextController extends StatefulWidget {
  const WithTextController({super.key, this.text = '', required this.builder});
  final String text;
  final Widget Function(BuildContext context, TextEditingController controller) builder;

  @override
  State<WithTextController> createState() => _WithTextControllerState();
}

class _WithTextControllerState extends State<WithTextController> {
  late final _c = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _c);
}
