import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';
import 'ui/components.dart';
import 'ui/ds.dart';
import 'ui/perf.dart';

/// Search → "Recent searches": shows while search is open and nothing is typed (Settings →
/// Search → Save search history). Tap a row → it's typed in and searched (and moves to the top);
/// the arrow at the end only fills it in to edit. Swipe a row away, or long-press it, to remove
/// it; "Clear all" asks first. Classic: a card like the other result sections (rows flip when
/// the results grow upward from a bottom bar). Metro ([metro]): an accent header + list rows,
/// like the Tiles search results (docs/DESIGN_LANGUAGES.md).
class RecentSearches extends StatefulWidget {
  const RecentSearches({super.key, required this.prefs, required this.onPick, required this.onFill, this.upward = false, this.metro = false});
  final Prefs prefs;
  final ValueChanged<String> onPick, onFill;
  final bool upward, metro;

  /// Whether the card has anything to show.
  static bool shows(Prefs prefs) => prefs.searchHistory.isNotEmpty;

  @override
  State<RecentSearches> createState() => _RecentSearchesState();
}

class _RecentSearchesState extends State<RecentSearches> {
  /// Swiped away this frame: out of the list at once (a dismissed row can't stay in the tree).
  final _gone = <String>{};

  Prefs get prefs => widget.prefs;
  bool get metro => widget.metro;

  void _pick(String q) {
    HapticFeedback.selectionClick();
    prefs.addSearch(q); // used again: to the top
    widget.onPick(q);
  }

  Future<void> _clearAll() async {
    if (!await confirmReset(context, title: 'Clear search history?', body: 'Your recent searches are removed from this phone.', action: 'Clear')) return;
    HapticFeedback.mediumImpact();
    prefs.clearSearchHistory();
  }

  /// Swiped away: gone, with a short "Removed · Undo" above the keyboard and the search bar.
  void _swiped(String q, int index) {
    HapticFeedback.mediumImpact();
    setState(() => _gone.add(q));
    prefs.removeSearch(q);
    final mq = MediaQuery.of(context);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(DS.cased('Removed')),
          behavior: SnackBarBehavior.floating,
          persist: false,
          duration: const Duration(seconds: 4),
          margin: EdgeInsets.fromLTRB(DS.s16, 0, DS.s16, math.max(mq.viewInsets.bottom, mq.padding.bottom) + 72),
          action: SnackBarAction(
            label: DS.cased('Undo'),
            textColor: metro ? Colors.white : DS.hero,
            onPressed: () => prefs.addSearch(q, at: index),
          ),
        ),
      );
  }

  /// Long-press: a small menu at the row.
  Future<void> _menu(BuildContext rowContext, String q) async {
    HapticFeedback.mediumImpact();
    final box = rowContext.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(rowContext).overlay!.context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(DS.s48, box.size.height / 2), ancestor: overlay);
    final picked = await showMenu<String>(
      context: rowContext,
      color: DS.card,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
          value: 'remove',
          child: Text(DS.cased('Remove from history'), style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
        ),
        PopupMenuItem(
          value: 'clear',
          child: Text(DS.cased('Clear all history'), style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
        ),
      ],
    );
    if (!mounted) return;
    if (picked == 'remove') {
      HapticFeedback.selectionClick();
      prefs.removeSearch(q);
    } else if (picked == 'clear') {
      _clearAll();
    }
  }

  Widget _header() {
    final clear = TextButton(
      onPressed: _clearAll,
      style: TextButton.styleFrom(
        minimumSize: const Size(DS.tap, DS.tap),
        padding: const EdgeInsets.symmetric(horizontal: DS.s12),
      ),
      child: Text(
        DS.cased('Clear all'),
        style: metro
            ? const TextStyle(fontFamily: DS.font, color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w400)
            : DS.rowSub.copyWith(color: DS.ink, fontWeight: FontWeight.w500, fontSize: 13),
      ),
    );
    return Padding(
      padding: metro ? const EdgeInsets.fromLTRB(4, DS.s4, 0, 0) : const EdgeInsets.fromLTRB(DS.s16, 0, DS.s4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DS.cased('Recent searches'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Same headers as the results around it (Classic card title / Metro accent header).
              style: metro
                  ? TextStyle(fontFamily: DS.font, color: DS.accentText, fontSize: 20, fontWeight: FontWeight.w300)
                  : DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 13),
            ),
          ),
          clear,
        ],
      ),
    );
  }

  Widget _row(String q, int index) {
    final ink = metro ? Colors.white : DS.ink;
    final faint = metro ? Colors.white60 : DS.inkFaint;
    // Red under the row, either way it's swiped.
    Widget bin(Alignment side) => Container(
      color: DS.alert,
      alignment: side,
      padding: const EdgeInsets.symmetric(horizontal: DS.s24),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
    );
    return Dismissible(
      key: ValueKey('recent:$q'),
      background: bin(Alignment.centerLeft),
      secondaryBackground: bin(Alignment.centerRight),
      onDismissed: (_) => _swiped(q, index),
      child: Builder(
        builder: (rowContext) => InkWell(
          onTap: () => _pick(q),
          onLongPress: () => _menu(rowContext, q),
          child: Padding(
            padding: metro ? const EdgeInsets.only(left: 4) : const EdgeInsets.only(left: DS.s16, right: DS.s4),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: metro ? 24 : 22, color: faint),
                const SizedBox(width: DS.s16),
                Expanded(
                  child: Text(
                    q,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: metro
                        ? TextStyle(fontFamily: DS.font, color: ink, fontSize: 18, fontWeight: FontWeight.w300)
                        : DS.rowTitle.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                // Fill in, don't search yet (like Google's arrow): to edit before searching.
                IconButton(
                  tooltip: 'Fill in “$q”',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    widget.onFill(q);
                  },
                  icon: Icon(Icons.north_west_rounded, size: 18, color: faint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: prefs, builder: (context, _) => _build());

  Widget _build() {
    final history = prefs.searchHistory;
    _gone.removeWhere((q) => !history.contains(q)); // saved: no longer needed (and Undo brings it back)
    final rows = [
      for (final (i, q) in history.indexed)
        // A short cascade on arrival, newest (nearest the bar) first; rows already shown don't replay.
        if (!_gone.contains(q)) Cascade(key: ValueKey(q), index: i, upward: widget.upward, child: _row(q, i)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    // The title arrives last, after the row farthest from the bar.
    final header = Cascade(key: const ValueKey('header'), index: rows.length, upward: widget.upward, child: _header());
    if (metro) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, ...rows]);
    return OneCard(
      padding: const EdgeInsets.symmetric(vertical: DS.s4),
      // Title stays on top; newest sits nearest the bar.
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, ...(widget.upward ? rows.reversed : rows)]),
    );
  }
}

/// One row (or card) of search results arriving: rising from the bar's side and fading in, a beat
/// after the one nearer the bar ([index] 0 = nearest), so the list builds up one by one. Mounted
/// once per row, so updates and removals don't replay it.
class Cascade extends StatelessWidget {
  const Cascade({super.key, required this.index, required this.child, required this.upward});
  final int index;
  final Widget child;
  final bool upward;

  static const _step = 70; // ms between rows
  static const _each = 380; // ms each row takes

  @override
  Widget build(BuildContext context) {
    if (Perf.lite.value || index > 10) return child;
    final wait = index * _step;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: wait + _each),
      curve: Interval(wait / (wait + _each), 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (upward ? 28 : -28) * (1 - t)), child: child),
      ),
    );
  }
}
