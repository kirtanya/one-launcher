import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'prefs.dart';
import 'sheets.dart';
import 'tokens.dart';
import 'widgets.dart';

/// All apps, search-first. Typing filters; Enter opens the top match.
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.apps,
    required this.prefs,
    required this.onLaunch,
    required this.onDragClose,
    required this.onDragEnd,
  });

  final List<AppEntry> apps;
  final Prefs prefs;
  final ValueChanged<AppEntry> onLaunch;
  final ValueChanged<double> onDragClose; // finger moved down by dy
  final ValueChanged<double> onDragEnd; // release velocity

  @override
  State<AppDrawer> createState() => AppDrawerState();
}

class AppDrawerState extends State<AppDrawer> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _pullingDown = false;

  /// Drawer finished opening.
  void opened() => _focus.requestFocus();

  /// Drawer finished closing: start fresh next time.
  void closed() {
    _focus.unfocus();
    _query.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<AppEntry> get _results {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) {
      final hidden = widget.prefs.hidden.toSet();
      return widget.apps.where((a) => !hidden.contains(a.package)).toList();
    }
    // Hidden apps are still findable by search.
    int rank(AppEntry a) {
      final l = a.label.toLowerCase();
      if (l.startsWith(q)) return 0;
      if (l.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) return 1;
      if (l.contains(q)) return 2;
      return 3;
    }

    return widget.apps.where((a) => rank(a) < 3).toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  void _onChanged(String _) {
    setState(() {});
    final r = _results;
    if (widget.prefs.autoOpenSingleMatch && _query.text.trim().isNotEmpty && r.length == 1) {
      widget.onLaunch(r.first);
    }
  }

  void _onSubmit(String _) {
    final r = _results;
    if (_query.text.trim().isNotEmpty && r.isNotEmpty) widget.onLaunch(r.first);
  }

  void _longPress(AppEntry app) {
    HapticFeedback.mediumImpact();
    _focus.unfocus();
    showAppSheet(context, prefs: widget.prefs, app: app);
  }

  /// Pulling down when the list is already at the top closes the drawer.
  bool _onScroll(ScrollNotification n) {
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      _pullingDown = true;
      widget.onDragClose(-n.overscroll);
    } else if (n is ScrollUpdateNotification && _pullingDown && n.dragDetails != null) {
      widget.onDragClose(n.dragDetails!.delta.dy);
    } else if (n is ScrollEndNotification && _pullingDown) {
      _pullingDown = false;
      widget.onDragEnd(n.dragDetails?.primaryVelocity ?? 0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final searching = _query.text.trim().isNotEmpty;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: T.drawer,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          // Header: drag here to close.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => widget.onDragClose(d.delta.dy),
            onVerticalDragEnd: (d) => widget.onDragEnd(d.primaryVelocity ?? 0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(T.s16, T.s12, T.s16, T.s8),
              child: Column(children: [
                Container(width: 36, height: 4, decoration: BoxDecoration(color: T.inkFaint, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: T.s16),
                TextField(
                  controller: _query,
                  focusNode: _focus,
                  onChanged: _onChanged,
                  onSubmitted: _onSubmit,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: T.appName.copyWith(fontSize: 17),
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.apps.length} apps',
                    hintStyle: const TextStyle(color: T.inkFaint),
                    prefixIcon: const Icon(Icons.search_rounded, color: T.inkMuted),
                    suffixIcon: searching
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: T.inkMuted),
                            tooltip: 'Clear',
                            onPressed: () => setState(_query.clear),
                          )
                        : null,
                    filled: true,
                    fillColor: T.field,
                    contentPadding: const EdgeInsets.symmetric(vertical: T.s16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(T.rField), borderSide: BorderSide.none),
                  ),
                ),
              ]),
            ),
          ),

          // List
          Expanded(
            child: results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(T.s32),
                    child: Text('No app called “${_query.text.trim()}”', style: T.body, textAlign: TextAlign.center),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: ListView.builder(
                      controller: _scroll,
                      physics: const ClampingScrollPhysics(),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(T.s8, T.s4, T.s8, keyboard + MediaQuery.paddingOf(context).bottom + T.s16),
                      itemCount: results.length,
                      itemBuilder: (context, i) => _AppRow(
                        app: results[i],
                        isTopMatch: searching && i == 0,
                        onTap: () => widget.onLaunch(results[i]),
                        onLongPress: () => _longPress(results[i]),
                      ),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.isTopMatch, required this.onTap, required this.onLongPress});
  final AppEntry app;
  final bool isTopMatch;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(T.rIcon),
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.s12),
          child: Row(children: [
            AppIcon(app),
            const SizedBox(width: T.s16),
            Expanded(child: Text(app.label, style: T.appName, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (isTopMatch)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: T.s8, vertical: T.s4),
                decoration: BoxDecoration(color: T.accent, borderRadius: BorderRadius.circular(8)),
                child: const Text('↵ Open', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1B1C20))),
              ),
          ]),
        ),
      ),
    );
  }
}
