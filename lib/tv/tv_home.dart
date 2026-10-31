import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tv_real.dart';
import '../third/tactile/tactile.dart';
import '../third/tactile/parts.dart';

import 'package:flutter/services.dart';

import '../apps.dart';
import '../folders.dart';
import '../one_stream.dart';
import '../prefs.dart';
import '../ui/ds.dart';
import '../ui/palette.dart';
import '../ui/theme.dart';
import '../ui/motion.dart';
import '../ui/perf.dart';
import 'catalog.dart';
import 'app_trending.dart';
import 'art_quality.dart';
import 'episode_art.dart';
import 'tv_actions.dart';
import 'tv_all_apps.dart';
import 'tv_apps.dart';
import 'tv_ds.dart';
import 'tv_focus.dart';
import 'tv_parts.dart';
import 'tv_metro.dart';
import 'tv_one_stream.dart';
import 'tv_search.dart';
import 'tv_tiles.dart';
import '../tiles/tiles_home.dart' show TileSpec;
import 'tv_settings.dart';

part 'tv_spotlight.dart';

enum TvKind { app, resume, program, action }

/// Anything on the home screen: an app, the show that's playing/paused, or a streaming
/// app's programme (Watch Next / channels, where the TV allows it).
class TvItem {
  const TvItem({
    required this.key,
    required this.kind,
    required this.title,
    required this.package,
    this.app,
    this.appName,
    this.meta,
    this.description,
    this.image,
    this.art,
    this.progress,
    this.intent,
    this.historyKey,
    this.playing = false,
  });
  final String key;
  final TvKind kind;
  final String title;
  final String package;
  final AppEntry? app;
  final String? appName;
  final String? meta; // "S2 · E5 · Low Tide"
  final String? description;
  final String? image; // artwork uri (programmes)
  final ImageProvider? art; // artwork (what's playing, or saved with the watch history)
  final double? progress; // 0–1 watched
  final String? intent; // deep link into the app
  final String? historyKey; // from the watch history (the app may have closed since)
  final bool playing; // live and playing right now
}

/// One row: Continue watching (wide), app rows (banners), streaming apps' rows (wide).
class TvRow {
  const TvRow(this.id, this.title, this.items, {this.wide = false, this.chips = false});
  final String id;
  final String title;
  final List<TvItem> items;
  final bool wide;
  final bool chips; // the quick action chips above the rows (no title, short)

  /// Customise → App cards → Circle: an app row shows round app icons, not banners.
  bool get round => !wide && !chips && TvLook.str('appCards') == 'round';

  // Customise → Card size scales every card; Row titles off removes their line.
  double get cardW => (round ? TvDS.appCircle : (wide ? TvDS.wideW : TvDS.tileW)) * TvLook.number('cardScale');
  double get cardH => (round ? TvDS.appCircle : (wide ? TvDS.wideH : TvDS.tileH)) * TvLook.number('cardScale');
  double get height => chips
      ? TvDS.cardRowPad + 40 * TvLook.get<double>('quickSize') + TvDS.cardRowGap
      : (TvLook.on('rowTitles') ? TvDS.cardRowTitleH : 0) + TvDS.cardRowPad + cardH + TvDS.cardRowGap;
}

/// The TV home screen, cinematic: the focused item's artwork fills the screen behind a
/// big title block, rows sit along the bottom. The remote steers row by row (each row
/// remembers its tile); the focused row always sits at the same spot, rows above slide away.
class TvHome extends StatefulWidget {
  const TvHome({super.key, required this.prefs, this.theme});
  final Prefs prefs;
  final OneTheme? theme; // colours (Customise → Colours)

  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  List<AppEntry> _apps = const [];
  List<Map> _watchNext = const [], _channels = const [], _history = const [];
  List<OneStreamTitle> _stream = const []; // One Stream's Continue watching (when installed)
  List<TvRow> _rows = const [];
  bool _loaded = false;

  final _v = ScrollController();
  final _h = <String, ScrollController>{};
  final _nodes = <String, FocusNode>{};
  final _col = <String, int>{};
  int _row = 0; // focused row (-1 = top bar)

  TvItem? _hero; // what the title block describes (instant)
  TvItem? _chip; // focused quick action: named in the hint line, the title block stays
  TvItem? _backdrop; // what the big picture shows (settles after a beat, so fast moves don't flicker)
  Timer? _backdropTimer;

  // Inputs, Settings… are quick action chips now; "N permissions needed" while something is off.
  List<String> get _header => ['search', 'voice', 'customise', if (_missing.isNotEmpty) 'perms'];

  /// Permissions the launcher needs that are still off: (icon, name, what it's for, open its settings).
  List<(IconData, String, String, VoidCallback)> get _missing => [
    if (tv.media.value?['granted'] == false)
      (Icons.play_circle_outline_rounded, 'Notification access', 'Continue watching, what’s playing', tv.openNotificationAccess),
    if (!TvApps.demo && !tv.shows.value.on)
      (Icons.subtitles_outlined, 'Accessibility: read show names', 'Episode pictures for apps like JioHotstar', tv.openAccessibility),
  ];

  String get _missingLabel => _missing.length == 1 ? '1 permission needed' : '${_missing.length} permissions needed';

  /// The header's "N permissions needed": each one, opening its page in Android settings.
  void _permissions() => showTvPanel(
    context,
    title: _missingLabel,
    actions: [for (final (icon, name, why, open) in _missing) TvAction(icon, name, open, value: why)],
  );

  Prefs get prefs => widget.prefs;
  TvApps get tv => TvApps.instance;

  @override
  void initState() {
    super.initState();
    tv.onAppsChanged = _load;
    tv.onHomePressed = _home;
    tv.onSearchFor = _searchFor;
    tv.takeSearch().then((q) {
      if (q != null && mounted) _searchFor(q);
    });
    tv.onResumed = () {
      _loadContent();
      if (_tilesView) _tilesKey.currentState?.land(); // back from an app: tiles fly in again
      Catalog.instance.maybeUpdate(); // shows & films catalog: update in the background when due
    };
    tv.media.addListener(_regroup);
    tv.shows.addListener(_regroup); // a show name read from an app's screen: its episode's picture
    prefs.addListener(_regroup);
    OneStream.instance.available.addListener(_loadContent); // installed / removed: its resume items
    _load();
    Catalog.instance.start(prefs); // search's catalog: load the saved one, update when due
  }

  @override
  void dispose() {
    tv.media.removeListener(_regroup);
    tv.shows.removeListener(_regroup);
    prefs.removeListener(_regroup);
    OneStream.instance.available.removeListener(_loadContent);
    _backdropTimer?.cancel();
    _v.dispose();
    for (final c in _h.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final apps = await tv.list();
    if (!mounted) return;
    _apps = apps;
    _regroup();
    await _loadContent();
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusDefault());
    }
  }

  Future<void> _loadContent() async {
    final results = await Future.wait([tv.watchNext(), tv.channels(), tv.history()]);
    final stream = await OneStream.instance.continueWatching();
    await tv.refreshMedia();
    if (!mounted) return;
    _watchNext = results[0];
    _channels = results[1];
    _history = results[2];
    _stream = stream;
    _regroup();
  }

  // ---- Rows ----------------------------------------------------------------

  void _regroup() {
    if (!mounted) return;
    TvLook.read(prefs);
    final hidden = prefs.hidden.toSet();
    final visible = [
      for (final a in _apps)
        if (!hidden.contains(a.package)) a,
    ];
    final byPkg = {for (final a in visible) a.package: a};
    String appName(String pkg) => byPkg[pkg]?.label ?? '';
    TvItem appItem(AppEntry a) => TvItem(key: a.package, kind: TvKind.app, title: a.label, package: a.package, app: a, appName: a.label);

    // Continue watching: what's playing / paused right now, then the apps' Watch Next.
    final cont = <TvItem>[];
    final m = tv.media.value;
    if (m != null && m['active'] == true && m['title'] != null) {
      final dur = (m['duration'] as num?)?.toDouble() ?? 0;
      final pos = (m['position'] as num?)?.toDouble() ?? 0;
      final art = m['art'];
      cont.add(
        TvItem(
          key: 'now:${m['package']}',
          kind: TvKind.resume,
          title: m['title'] as String,
          package: m['package'] as String? ?? '',
          appName: m['app'] as String?,
          meta: _joinMeta([m['artist'] as String?, if (dur > 0) _left(dur - pos)]),
          art: art is Uint8List ? MemoryImage(art) : null,
          image: art is Uint8List ? null : _lookupArt(m['title'] as String, m['artist'] as String?, m['package'] as String? ?? ''),
          progress: dur > 0 ? (pos / dur).clamp(0, 1) : null,
          playing: m['playing'] == true,
        ),
      );
    }
    // One Stream's own Continue watching (real progress; opens right where you left off). It has
    // no times, so each takes the place of its entry in the TV's history (recency); the rest
    // follow the history.
    final stream = [..._stream];
    TvItem streamItem(OneStreamTitle s) => TvItem(
      key: 'os:${s.key}',
      kind: TvKind.resume,
      title: s.title,
      package: OneStream.package,
      appName: byPkg[OneStream.package]?.label ?? 'One Stream',
      meta: _joinMeta([s.subtitle, s.left]),
      image: s.backdrop ?? s.poster,
      progress: s.hasProgress ? s.progress.clamp(0, 1) : null,
      intent: s.link,
    );
    OneStreamTitle? takeStream(String title) {
      final i = stream.indexWhere((s) => s.title.toLowerCase() == title.toLowerCase());
      return i < 0 ? null : stream.removeAt(i);
    }

    // Then the watch history the TV kept (apps closed since): newest first.
    for (final h in _history) {
      final title = h['title'] as String?;
      final pkg = h['package'] as String? ?? '';
      if (title == null || cont.any((c) => c.title == title && c.package == pkg)) continue;
      if (takeStream(title) case final s?) {
        if (!cont.any((c) => c.title == s.title)) cont.add(streamItem(s));
        continue;
      }
      final dur = (h['duration'] as num?)?.toDouble() ?? 0;
      final pos = (h['position'] as num?)?.toDouble() ?? 0;
      final artPath = switch (h['art']) {
        final String p when p.isNotEmpty && p != 'null' => p, // older builds saved "null" as text
        _ => null,
      };
      cont.add(
        TvItem(
          key: 'h:${h['key']}',
          kind: TvKind.resume,
          title: title,
          package: pkg,
          appName: (h['app'] as String?) ?? appName(pkg),
          meta: _joinMeta([h['subtitle'] as String?, if (dur > 0 && pos > 0) _left(dur - pos), _ago((h['at'] as num?)?.toInt())]),
          art: artPath != null && !TvApps.demo ? FileImage(File(artPath)) : null,
          image: artPath == null ? _lookupArt(title, h['subtitle'] as String?, pkg) : null,
          progress: dur > 0 && pos > 0 ? (pos / dur).clamp(0, 1) : null,
          historyKey: h['key'] as String?,
        ),
      );
    }
    for (final s in stream) {
      if (!cont.any((c) => c.title.toLowerCase() == s.title.toLowerCase())) cont.add(streamItem(s));
    }
    for (final p in _watchNext) {
      final item = _program(p, appName(p['package'] as String? ?? ''));
      if (item != null && !cont.any((c) => c.title == item.title)) cont.add(item);
    }

    var fav = [for (final p in prefs.favourites) ?byPkg[p]];
    final groups = groupApps(visible, prefs.folderOverrides, order: prefs.folderOrder);
    if (fav.isEmpty) {
      fav = [
        for (final (f, list) in groups)
          if (f.id == 'media') ...list,
      ].take(8).toList();
    }
    final recents = [for (final p in prefs.tvRecents) ?byPkg[p]].take(10).toList();

    // Quick action chips: built-ins and pinned apps, then "Edit".
    final quick = <TvItem>[
      for (final id in prefs.tvQuickActions)
        if (tvActions[id] case (final label, _))
          TvItem(key: id, kind: TvKind.action, title: label, package: '')
        else if (id.startsWith('a:') && byPkg[id.substring(2)] != null)
          TvItem(key: id, kind: TvKind.action, title: byPkg[id.substring(2)]!.label, package: id.substring(2), app: byPkg[id.substring(2)]),
      const TvItem(key: 'q:edit', kind: TvKind.action, title: 'Edit', package: ''),
    ];

    setState(() {
      _rows = [
        // ▶ Resume: what's playing / paused, one press away (above the quick actions).
        if (cont.firstOrNull case final now? when now.kind == TvKind.resume && TvLook.on('resume'))
          TvRow('resume', 'Resume', [
            now,
            // Live: control it right here (music keeps playing on the home screen).
            if (now.historyKey == null && now.key.startsWith('now:') && TvLook.on('controls')) ...[
              if (m?['canPrev'] == true) const TvItem(key: 'm:prev', kind: TvKind.action, title: 'Previous', package: ''),
              TvItem(key: 'm:toggle', kind: TvKind.action, title: now.playing ? 'Pause' : 'Play', package: ''),
              if (m?['canNext'] == true) const TvItem(key: 'm:next', kind: TvKind.action, title: 'Next', package: ''),
            ],
          ], chips: true),
        if (TvLook.on('quick')) TvRow('quick', 'Quick actions', quick, chips: true),
        if (cont.isNotEmpty && TvLook.on('rowContinue')) TvRow('continue', 'Continue watching', cont, wide: true),
        if (fav.isNotEmpty && TvLook.on('rowFav'))
          TvRow('fav', 'Your apps', [
            for (final a in fav) appItem(a),
            // Every app, one press away: the last tile opens the All apps screen.
            TvItem(key: 'all-apps', kind: TvKind.action, title: 'All apps', package: '', meta: '${visible.length}'),
          ]),
        if (recents.length > 1 && TvLook.on('rowRecent')) TvRow('recent', 'Jump back in', [for (final a in recents) appItem(a)]),
        if (TvLook.on('rowChannels'))
          for (final c in _channels)
            if ((c['programs'] as List?)?.isNotEmpty ?? false)
              TvRow('ch:${c['id']}', '${c['name'] ?? appName(c['package'] as String? ?? '')}', [
                for (final p in (c['programs'] as List).cast<Map>()) ?_program(p, appName(c['package'] as String? ?? '')),
              ], wide: true),
        if (TvLook.on('rowFolders'))
          for (final (f, list) in groups) TvRow(f.id, prefs.folderNames[f.id] ?? f.name, [for (final a in _ordered(f.id, list)) appItem(a)]),
      ];
    });
    // Tiles view: the Resume tile shows what's playing / the latest from history.
    final now = cont.firstOrNull?.kind == TvKind.resume ? cont.first : null;
    _resumeItem = now;
    _cont = cont;
    _resumeInfo = now == null ? null : TvResumeInfo(title: now.title, app: now.appName, art: now.art, progress: now.progress, playing: now.playing);
    // The title block follows focus; keep it pointing at a live item.
    final firstContent = _rows.where((r) => !r.chips).firstOrNull;
    if (_hero == null && firstContent != null) _show(firstContent.items.first, now: true);
  }

  /// A row's apps in the user's order (Hold OK → Move); new apps keep their place after.
  List<AppEntry> _ordered(String row, List<AppEntry> apps) {
    final order = prefs.tvRowOrder(row);
    if (order.isEmpty) return apps;
    int rank(AppEntry a) {
      final i = order.indexOf(a.package);
      return i < 0 ? order.length + apps.indexOf(a) : i;
    }

    return [...apps]..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  TvItem? _program(Map p, String appName) {
    final title = p['title'] as String?;
    if (title == null) return null;
    final dur = (p['duration'] as num?)?.toDouble() ?? 0;
    final pos = (p['position'] as num?)?.toDouble() ?? 0;
    final se = [if (p['season'] != null) 'S${p['season']}', if (p['episode'] != null) 'E${p['episode']}'].join(' · ');
    return TvItem(
      key: 'p:${p['id']}',
      kind: TvKind.program,
      title: title,
      package: p['package'] as String? ?? '',
      appName: appName,
      meta: _joinMeta([se.isEmpty ? null : se, p['episodeTitle'] as String?, if (dur > 0 && pos > 0) _left(dur - pos)]),
      description: p['description'] as String?,
      image: (p['poster'] ?? p['thumbnail']) as String?,
      progress: dur > 0 && pos > 0 ? (pos / dur).clamp(0, 1) : null,
      intent: p['intent'] as String?,
    );
  }

  /// Apps that share no picture at all (JioHotstar): the show's artwork from the catalog, found
  /// by name. Only an exact name match counts, so a show never gets someone else's poster.
  final _artLookups = <String, String?>{};
  String? _lookupArt(String title, String? show, String package) {
    if (TvApps.demo) return null;
    String fold(String x) => x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final episode = RegExp(r'^\s*S\d+\W*E\d+', caseSensitive: false);
    final hasShow = show?.trim().isNotEmpty ?? false;
    if (!hasShow && episode.hasMatch(title)) {
      // Only "S1 E5 Firewall" (JioHotstar). Its show: read from the app's screen for this very
      // episode, else the app's last show (an autoplayed next episode, if it's in that show),
      // else found by the episode's name.
      final names = tv.shows.value;
      final seen = names.showOf(package, title), last = names.lastOf(package);
      final key = '$package|$title|${seen ?? ''}|${last ?? ''}'; // a newly read show: looked up again
      if (_artLookups.containsKey(key)) return _artLookups[key];
      _artLookups[key] = null;
      () async {
        final art = EpisodeArt.instance;
        return (seen != null ? await art.inShow(seen, title) : null) ??
            (last != null && last != seen ? await art.inShow(last, title, sure: false) : null) ??
            await art.find(title);
      }().then((url) {
        // None (or offline): asked again the next time the row is built; EpisodeArt remembers
        // a real "not found" itself, so that costs nothing.
        if (url == null) _artLookups.remove(key);
        if (url == null || !mounted) return;
        _artLookups[key] = url;
        _regroup();
      });
      return null;
    }
    final q = ((show?.trim().isNotEmpty ?? false) ? show! : title).replaceFirst(RegExp(r'^\s*S\d+\W*E\d+\W*', caseSensitive: false), '').trim();
    if (q.length < 2) return null;
    if (_artLookups.containsKey(q)) return _artLookups[q];
    _artLookups[q] = null; // looked up once
    Catalog.instance.searchOnline(q).then((list) {
      final t = list.where((t) => fold(t.title) == fold(q)).firstOrNull;
      if (t == null || !mounted) return;
      _artLookups[q] = t.id.startsWith('tt') ? t.backdrops.first : t.backdrops.last;
      _regroup();
    }, onError: (_) {});
    return null;
  }

  static String? _joinMeta(List<String?> parts) {
    final p = parts.whereType<String>().where((s) => s.isNotEmpty).toList();
    return p.isEmpty ? null : p.join(' · ');
  }

  /// "Today", "Yesterday", "3 days ago" — when it was last watched.
  static String? _ago(int? at) {
    if (at == null || at <= 0) return null;
    final then = DateTime.fromMillisecondsSinceEpoch(at);
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(then.year, then.month, then.day)).inDays;
    return days <= 0 ? 'Today' : (days == 1 ? 'Yesterday' : '$days days ago');
  }

  static String _left(double ms) {
    final min = (ms / 60000).round();
    return min >= 60 ? '${min ~/ 60} h ${min % 60} min left' : '$min min left';
  }

  void _home() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (_tilesView) {
      _tilesKey.currentState?.endMove();
      _tilesKey.currentState?.land();
      return;
    }
    _endMove();
    _focusDefault();
  }

  // ---- Tiles view (Customise → Home view → Tiles) ----

  final _tilesKey = GlobalKey<TvTilesStartState>();
  bool get _tilesView => prefs.homeView == 'tiles';
  bool get _spotlightView => prefs.homeView == 'spotlight'; // TV only: tv_spotlight.dart
  final _spotlightKey = GlobalKey<_SpotlightState>();

  /// Spotlight's columns: Classic's content rows, with the quick actions as a column of small
  /// cards after Your apps (the Resume button is the first Continue watching card already).
  List<TvRow> _spotlightRows() {
    final content = [for (final r in _rows) if (!r.chips && r.items.isNotEmpty) r];
    final quick = _rows.where((r) => r.id == 'quick' && r.items.isNotEmpty).firstOrNull;
    if (quick == null) return content;
    final at = content.indexWhere((r) => r.id == 'fav');
    return [...content]..insert(at < 0 ? content.length : at + 1, quick);
  }
  TvItem? _resumeItem;
  List<TvItem> _cont = const []; // everything to resume (Tiles view: the Resume row)

  /// Tiles view: the quick actions row (same chips as the Cinematic view, + to edit).
  List<TvTileAction> _tilesQuick() {
    final row = _rows.where((r) => r.id == 'quick').firstOrNull;
    if (row == null) return const [];
    return [
      for (final (i, it) in row.items.indexed)
        TvTileAction(
          id: it.key,
          label: it.key == 'q:edit' ? '' : it.title,
          icon: it.key == 'q:edit' ? Icons.add_rounded : tvActions[it.key]?.$2,
          app: it.app,
          onSelect: () => _open(it),
          onOptions: () => _options(row, i),
        ),
    ];
  }

  /// Tiles view: every resume item as a card (playing / paused, history, the apps' Watch Next).
  List<TvResumeCard> _tilesResume() {
    if (!TvLook.on('resume') || _cont.isEmpty) return const [];
    final row = TvRow('continue', 'Continue watching', _cont, wide: true);
    return [
      for (final (i, c) in _cont.indexed)
        TvResumeCard(
          key: c.key,
          info: TvResumeInfo(title: c.title, app: c.appName, art: _tilesArt(c), progress: c.progress, playing: c.playing),
          onSelect: () => _open(c),
          onOptions: () => _options(row, i),
        ),
    ];
  }

  /// A Resume card's picture: its own artwork, else the Watch Next still (fetched once; the row
  /// redraws when it arrives — the Cinematic cards that would load it aren't on screen here).
  ImageProvider? _tilesArt(TvItem c) {
    if (c.art != null || c.image == null) return c.art;
    final ready = tv.imageNow(c.image!);
    if (ready == null) {
      tv.image(c.image!).then((m) {
        if (m != null && mounted) setState(() {}); // (no picture: nothing to redraw, no loop)
      }, onError: (_) {});
    }
    return ready;
  }

  TvResumeInfo? _resumeInfo;

  /// Customise → Tiles → Add a tile: clock, resume, all apps, any quick action. (Apps: All apps →
  /// Hold OK → Pin to Start.)
  /// [back]: where the remote's Back goes (Customise, when opened from there).
  void _addTile({VoidCallback? back}) {
    final have = tvTiles(prefs, _apps).map((t) => t.id).toSet();
    void add(String id, String size) => saveTvTiles(prefs, [...tvTiles(prefs, _apps), TileSpec(id, size)]);
    showTvPanel(
      context,
      title: 'Add a tile',
      onBack: back,
      actions: [
        if (!have.contains('clock')) TvAction(Icons.schedule_rounded, 'Clock', () => add('clock', 'm')),
        if (!have.contains('resume')) TvAction(Icons.play_circle_outline_rounded, 'Resume', () => add('resume', 'w')),
        if (!have.contains('allapps')) TvAction(Icons.apps_rounded, 'All apps', () => add('allapps', 'm')),
        for (final MapEntry(key: id, value: (label, icon)) in tvActions.entries)
          if (!have.contains('qa:$id')) TvAction(icon, label, () => add('qa:$id', 's')),
        TvAction(Icons.push_pin_outlined, 'An app: All apps → Hold OK → Pin to Start', _allApps),
      ],
    );
  }

  /// The top bar in the Tiles view: tile-shaped buttons (search · voice · customise).
  Widget _tilesHeader() => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      for (final (i, id) in _header.indexed) ...[
        if (i > 0) const SizedBox(width: DS.s8),
        TvTileButton(
          prefs: prefs,
          icon: switch (id) {
            'search' => Icons.search_rounded,
            'voice' => Icons.mic_none_rounded,
            'perms' => Icons.warning_amber_rounded,
            _ => Icons.tune_rounded,
          },
          label: switch (id) {
            'search' => 'search',
            'perms' => _missingLabel.toLowerCase(),
            _ => null,
          },
          focusNode: _node(-1, i),
          onSelect: () => _headerAction(id),
          // ↓ into the tiles; ← → along the buttons.
          onMove: (d) {
            if (d == AxisDirection.down) {
              _tilesKey.currentState?.focusFirst();
              return true;
            }
            return _move(-1, i, d);
          },
        ),
      ],
    ],
  );

  /// Landing, Home and Back all go to the default spot: the first quick action, or — with no
  /// quick actions — the first app. (Search is one ↑ away from either.)
  void _focusDefault() {
    if (_tilesView) return _tilesKey.currentState?.land();
    final quick = _rows.indexWhere((r) => r.id == 'quick' && r.items.any((it) => it.key != 'q:edit'));
    final resume = _rows.indexWhere((r) => r.id == 'resume');
    final apps = _rows.indexWhere((r) => !r.chips && r.items.any((it) => it.kind == TvKind.app));
    // Customise → Start on (falls through when that spot isn't there).
    const search = -100; // (indexWhere uses -1 for "not there")
    final order = switch (TvLook.str('landing')) {
      'search' => [search],
      'resume' => [resume, quick, apps],
      'app' => [apps, quick],
      _ => [quick, apps],
    };
    final target = order.firstWhere((r) => r == search || r >= 0, orElse: () => search);
    _focus(target == search ? -1 : target, 0);
    // Every row back to its start; the title block shows the first show / app (not a chip).
    for (final r in _rows) {
      _col.remove(r.id);
      final h = _h[r.id];
      if (h != null && h.hasClients) h.jumpTo(0);
    }
    final first = _rows.where((r) => !r.chips).firstOrNull;
    if (first != null) _show(first.items.first, now: _backdrop == null);
  }

  // ---- Focus ---------------------------------------------------------------

  String _rowId(int r) => r < 0 ? 'header' : _rows[r].id;
  int _len(int r) => r < 0 ? _header.length : _rows[r].items.length;
  String _key(int r, int i) => r < 0 ? 'h:${_header[i]}' : '${_rows[r].id}:${_rows[r].items[i].key}';
  FocusNode _node(int r, int i) => _nodes.putIfAbsent(_key(r, i), () => FocusNode(debugLabel: _key(r, i)));

  void _focus(int r, int i) {
    if (r >= _rows.length || _len(r) == 0) return;
    _node(r, i.clamp(0, _len(r) - 1)).requestFocus();
  }

  bool _move(int r, int i, AxisDirection d) {
    if (_moving != null) {
      // Moving an app: ← → slide it along its row; ↑ ↓ do nothing until OK / Back.
      if (d == AxisDirection.left && i > 0) _shift(r, i, -1);
      // "Edit" / "All apps" stay at the end.
      final last = r >= 0 && (_rows[r].chips || _rows[r].items.last.key == 'all-apps') ? _len(r) - 2 : _len(r) - 1;
      if (d == AxisDirection.right && i < last) _shift(r, i, 1);
      return true;
    }
    switch (d) {
      case AxisDirection.left when i > 0:
        _focus(r, i - 1);
      case AxisDirection.right when i < _len(r) - 1:
        _focus(r, i + 1);
      case AxisDirection.up when r > -1:
        _focus(r - 1, _col[_rowId(r - 1)] ?? 0);
      case AxisDirection.down when r < _rows.length - 1:
        _focus(r + 1, _col[_rowId(r + 1)] ?? 0);
      default:
        return false;
    }
    return true;
  }

  // ---- Reorder ---------------------------------------------------------------

  String? _moving; // focus key of the app being moved

  void _startMove(int r, int i) {
    HapticFeedback.mediumImpact();
    setState(() => _moving = _key(r, i));
    _focus(r, i);
  }

  void _endMove() {
    if (_moving == null) return;
    HapticFeedback.selectionClick();
    setState(() => _moving = null);
  }

  /// Swap the moving app with its neighbour and save the row's new order.
  Future<void> _shift(int r, int i, int by) async {
    final row = _rows[r];
    final list = [
      for (final it in row.items)
        if (it.key != 'all-apps') it.package,
    ];
    list.insert(i + by, list.removeAt(i));
    HapticFeedback.selectionClick();
    if (row.chips) {
      final keys = [
        for (final it in row.items)
          if (it.key != 'q:edit') it.key,
      ];
      keys.insert(i + by, keys.removeAt(i));
      await prefs.setTvQuickActions(keys);
    } else if (row.id == 'fav') {
      await prefs.setFavourites(list); // "Your apps" is the favourites list itself
    } else {
      await prefs.setTvRowOrder(row.id, list);
    }
    // Same focus node (keyed by app), new place: keep it in view.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFocus(r, i + by));
  }

  /// Folder rows can trade places too (the fixed rows on top stay put).
  void _moveRow(TvRow row, int by) {
    final folderRows = [
      for (final r in _rows)
        if (folders.any((f) => f.id == r.id) || r.id == other.id) r.id,
    ];
    final i = folderRows.indexOf(row.id);
    final j = i + by;
    if (i < 0 || j < 0 || j >= folderRows.length) return;
    folderRows.insert(j, folderRows.removeAt(i));
    prefs.setFolderOrder(folderRows);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final r = _rows.indexWhere((x) => x.id == row.id);
      if (r >= 0) _focus(r, _col[row.id] ?? 0);
    });
  }

  void _onFocus(int r, int i) {
    _col[_rowId(r)] = i;
    if (_row != r) setState(() => _row = r);
    if (r >= 0) _show(_withContent(_rows[r].items[i]));
    const dur = Duration(milliseconds: 420);
    const curve = Curves.easeOutCubic;
    // Vertical: the focused row slides to the top of the rows area; rows above slide out.
    if (_v.hasClients) {
      // Resume + quick actions stay together at the top: on either, nothing scrolls.
      final topGroup = _rows.indexWhere((x) => !x.chips);
      var y = 0.0;
      if (topGroup < 0 || r >= topGroup) {
        for (var k = 0; k < r; k++) {
          y += _rows[k].height;
        }
      }
      _v.animateTo(y.clamp(0.0, _v.position.maxScrollExtent), duration: dur, curve: curve);
    }
    // Horizontal: one card peeks on the left so you can tell there's more.
    final h = r < 0 ? null : _h[_rowId(r)];
    if (h != null && h.hasClients && _rows[r].chips) {
      // Chips vary in width: just keep the focused one comfortably in view.
      final ro = _node(r, i).context?.findRenderObject();
      if (ro != null) h.position.ensureVisible(ro, alignment: .2, duration: dur, curve: curve);
    } else if (h != null && h.hasClients) {
      final row = _rows[r];
      final x = ((i - 1) * (row.cardW + TvDS.gap)).clamp(0.0, h.position.maxScrollExtent);
      h.animateTo(x, duration: dur, curve: curve);
    }
  }

  /// An app you were just watching shows that show (title, time left, artwork) when focused.
  TvItem _withContent(TvItem item) {
    final m = tv.media.value;
    if (item.kind != TvKind.app || m == null || m['active'] != true || m['package'] != item.package || m['title'] == null) return item;
    final now = _rows.where((r) => r.id == 'continue').firstOrNull?.items.where((x) => x.kind == TvKind.resume).firstOrNull;
    if (now == null) return item;
    return TvItem(
      key: 'app-now:${item.package}',
      kind: TvKind.resume,
      title: now.title,
      package: item.package,
      appName: item.appName,
      meta: now.meta,
      art: now.art,
      progress: now.progress,
    );
  }

  /// Title block switches at once; the big picture waits until focus rests a moment.
  void _show(TvItem item, {bool now = false}) {
    // A chip keeps the show / app on screen (title and picture); only the hint names the chip.
    if (item.kind == TvKind.action) return setState(() => _chip = item);
    setState(() {
      _hero = item;
      _chip = null;
    });
    _backdropTimer?.cancel();
    if (now) {
      _backdrop = item;
    } else {
      _backdropTimer = Timer(const Duration(milliseconds: 260), () {
        if (mounted) setState(() => _backdrop = item);
      });
    }
  }

  // ---- Actions -------------------------------------------------------------

  void _open(TvItem item) {
    HapticFeedback.selectionClick();
    if (item.package.isNotEmpty) prefs.noteTvLaunch(item.package);
    switch (item.kind) {
      case TvKind.app:
        tv.launch(item.package);
      case TvKind.resume when item.key.startsWith('os:'):
        // Its page here (Resume first); One Stream opens only to play.
        final s = _stream.where((s) => 'os:${s.key}' == item.key).firstOrNull;
        s != null ? Navigator.of(context).push(tvFade(TvOneStreamPage(title: s))) : OneStream.instance.open(item.intent!);
      case TvKind.resume:
        final live = tv.media.value;
        if (item.historyKey != null && !(live?['active'] == true && live?['package'] == item.package)) {
          tv.launch(item.package); // the app closed since: open it (most show "continue watching" first)
        } else {
          tv.mediaResume(); // player to the front + play
        }
      case TvKind.program:
        tv.openProgram(item.intent, item.package);
      case TvKind.action when item.key.startsWith('m:'):
        switch (item.key) {
          case 'm:prev':
            tv.mediaPrev();
          case 'm:next':
            tv.mediaNext();
          default:
            tv.mediaPlayPause();
        }
        return;
      case TvKind.action when item.key == 'all-apps':
        _allApps();
        return;
      case TvKind.action:
        if (item.key == 'q:edit') {
          _editQuick();
        } else if (item.app != null) {
          tv.launch(item.package);
        } else {
          tv.openAction(item.key);
        }
    }
  }

  void _allApps() => Navigator.of(context).push(
    tvFade(
      TvAllApps(
        apps: _apps,
        prefs: prefs,
        onLaunch: (a) => _open(TvItem(key: a.package, kind: TvKind.app, title: a.label, package: a.package, app: a)),
      ),
    ),
  );

  void _options(TvRow row, int i) {
    final item = row.items[i];
    if (item.key == 'all-apps') return _allApps();
    if (row.chips && row.id == 'quick') {
      if (item.key == 'q:edit') return _editQuick();
      showTvPanel(
        context,
        title: item.title,
        actions: [
          TvAction(Icons.open_in_new_rounded, 'Open', () => _open(item)),
          // Move mode belongs to the Cinematic row; the Tiles view's row moves one step per press.
          if (row.items.length > 2 && !_tilesView) TvAction(Icons.open_with_rounded, 'Move', () => _startMove(_rows.indexOf(row), i)),
          if (_tilesView && i > 0) TvAction(Icons.chevron_left_rounded, 'Move left', () => _nudgeQuick(row, i, -1)),
          if (_tilesView && i < row.items.length - 2) TvAction(Icons.chevron_right_rounded, 'Move right', () => _nudgeQuick(row, i, 1)),
          TvAction(
            Icons.remove_circle_outline_rounded,
            'Remove from quick actions',
            () => prefs.setTvQuickActions([...prefs.tvQuickActions]..remove(item.key)),
          ),
          TvAction(Icons.edit_outlined, 'Edit quick actions', _editQuick),
        ],
      );
      return;
    }
    final a = item.app;
    if (a == null) {
      showTvPanel(
        context,
        title: item.title,
        actions: [
          TvAction(Icons.play_arrow_rounded, item.kind == TvKind.resume ? 'Resume' : 'Watch', () => _open(item)),
          if (item.historyKey != null)
            TvAction(Icons.history_toggle_off_rounded, 'Remove from Continue watching', () async {
              await tv.removeHistory(item.historyKey!);
              _history = [
                for (final h in _history)
                  if (h['key'] != item.historyKey) h,
              ];
              _regroup();
            }),
          if (item.package.isNotEmpty) TvAction(Icons.apps_rounded, 'Open ${item.appName ?? 'app'}', () => tv.launch(item.package)),
          if (item.package.isNotEmpty) TvAction(Icons.info_outline_rounded, 'App info', () => tv.appInfo(item.package)),
        ],
      );
      return;
    }
    final fav = prefs.favourites.contains(a.package);
    final favRow = _rows.where((r) => r.id == 'fav').firstOrNull;
    showTvPanel(
      context,
      title: a.label,
      leading: TvAppArt(app: a, width: 128),
      actions: [
        TvAction(Icons.open_in_new_rounded, 'Open', () => _open(item)),
        if (row.id != 'recent' && row.items.length > 1) TvAction(Icons.open_with_rounded, 'Move', () => _startMove(_rows.indexOf(row), i)),
        if (folders.any((f) => f.id == row.id) || row.id == other.id) ...[
          TvAction(Icons.keyboard_arrow_up_rounded, 'Move “${row.title}” row up', () => _moveRow(row, -1)),
          TvAction(Icons.keyboard_arrow_down_rounded, 'Move “${row.title}” row down', () => _moveRow(row, 1)),
        ],
        if (fav) ...[
          TvAction(Icons.star_outline_rounded, 'Remove from Your apps', () => prefs.toggleFavourite(a.package)),
        ] else if (!prefs.favouritesFull)
          TvAction(Icons.star_rounded, 'Add to Your apps', () async {
            // The starter row (Watch & Listen) becomes real picks the first time you edit it.
            if (prefs.favourites.isEmpty && favRow != null) {
              await prefs.setFavourites([for (final x in favRow.items) x.package]);
            }
            await prefs.toggleFavourite(a.package);
          }),
        if (prefs.tvQuickActions.contains('a:${a.package}'))
          TvAction(Icons.bolt_rounded, 'Remove from quick actions', () => prefs.setTvQuickActions([...prefs.tvQuickActions]..remove('a:${a.package}')))
        else
          TvAction(Icons.bolt_rounded, 'Add to quick actions', () => prefs.setTvQuickActions([...prefs.tvQuickActions, 'a:${a.package}'])),
        TvAction(Icons.visibility_off_outlined, 'Hide', () => prefs.toggleHidden(a.package)),
        TvAction(Icons.info_outline_rounded, 'App info', () => tv.appInfo(a.package)),
        if (!a.system) TvAction(Icons.delete_outline_rounded, 'Uninstall', () => tv.uninstall(a.package), danger: true),
      ],
    );
  }

  /// The phone remote's voice search: Search, with the words already in.
  void _searchFor(String q) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.of(context).push(
      tvFade(
        TvSearch(
          prefs: prefs,
          query: q,
          apps: [
            for (final a in _apps)
              if (!prefs.hidden.contains(a.package)) a,
          ],
          onLaunch: (a) => _open(TvItem(key: a.package, kind: TvKind.app, title: a.label, package: a.package, app: a)),
        ),
      ),
    );
  }

  void _headerAction(String id) => switch (id) {
    'search' => Navigator.of(context).push(
      tvFade(
        TvSearch(
          prefs: prefs,
          apps: [
            for (final a in _apps)
              if (!prefs.hidden.contains(a.package)) a,
          ],
          onLaunch: (a) => _open(TvItem(key: a.package, kind: TvKind.app, title: a.label, package: a.package, app: a)),
        ),
      ),
    ),
    'voice' => tv.openAction('t:assistant'), // Google TV voice search
    'perms' => _permissions(),
    _ => _customise(),
  };

  /// Tick quick actions on and off (the chips update behind the panel). Order: Hold OK → Move.
  /// Tiles view: a quick action one place left / right ("Edit" stays last; actions not shown,
  /// like an uninstalled app's, keep their spot at the end).
  void _nudgeQuick(TvRow row, int i, int by) {
    final keys = [
      for (final it in row.items)
        if (it.key != 'q:edit') it.key,
    ];
    final j = i + by;
    if (i >= keys.length || j < 0 || j >= keys.length) return;
    keys.insert(j, keys.removeAt(i));
    prefs.setTvQuickActions([
      ...keys,
      for (final k in prefs.tvQuickActions)
        if (!keys.contains(k)) k,
    ]);
  }

  void _editQuick({VoidCallback? back}) {
    showTvPanel(
      context,
      title: 'Quick actions',
      onBack: back,
      refresh: prefs,
      build: () {
        final on = prefs.tvQuickActions;
        void toggle(String id) => prefs.setTvQuickActions(on.contains(id) ? ([...on]..remove(id)) : [...on, id]);
        return [
          for (final MapEntry(key: id, value: (label, _)) in tvActions.entries)
            TvAction(on.contains(id) ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, label, () => toggle(id), keepOpen: true),
          for (final id in on.where((x) => x.startsWith('a:')))
            if (_apps.where((a) => a.package == id.substring(2)).firstOrNull case final app?)
              TvAction(Icons.check_circle_rounded, app.label, () => toggle(id), keepOpen: true),
          TvAction(
            Icons.restart_alt_rounded,
            'Reset to default',
            () => tvConfirm(
              context,
              title: 'Reset quick actions?',
              action: 'Reset to the default set',
              onConfirm: () => prefs.setTvQuickActions(Prefs.tvQuickDefault),
              back: _editQuick,
            ),
          ),
        ];
      },
    );
  }

  /// The phone's colour themes on the TV: the accent (Resume, progress, glows) and the canvas
  /// tint follow the choice. Changes show live behind the panel.
  void _colours({VoidCallback? back}) {
    final theme = widget.theme!;
    const names = ['Blue', 'Teal', 'Green', 'Yellow', 'Orange', 'Red', 'Pink', 'Purple'];
    showTvPanel(
      context,
      title: 'Colours',
      onBack: back,
      refresh: prefs,
      build: () {
        final source = prefs.themeSource == 'system' && !theme.hasSystem ? 'original' : prefs.themeSource;
        // Tiles: each swatch shows the accent it gives Start (Metro derives its own from the colour).
        final metro = TvMetro.on;
        Color sw(Color c, {String src = 'basic', String? style}) => metro ? TvMetro.accentFor(theme, prefs, source: src, seed: c.toARGB32(), style: style) : c;
        return [
          if (theme.hasSystem)
            TvAction(
              Icons.auto_awesome_outlined,
              'Match your TV',
              () => prefs.setTheme(source: 'system'),
              keepOpen: true,
              swatch: metro ? TvMetro.accentFor(theme, prefs, source: 'system') : theme.systemSeed,
              selected: source == 'system',
            ),
          TvAction(
            Icons.circle,
            'One original',
            () => prefs.setTheme(source: 'original'),
            keepOpen: true,
            swatch: metro ? TvMetro.accentFor(theme, prefs, source: 'original') : OnePalette.original.hero,
            selected: source == 'original',
          ),
          for (final (i, c) in OneTheme.basicSeeds.indexed)
            TvAction(
              Icons.circle,
              names[i],
              () => prefs.setTheme(source: 'basic', seed: c.toARGB32()),
              keepOpen: true,
              swatch: sw(c),
              selected: source == 'basic' && prefs.themeSeed == c.toARGB32(),
            ),
          if (source != 'original')
            for (final MapEntry(key: id, value: (label, _)) in OneTheme.styles.entries)
              TvAction(
                Icons.style_outlined,
                'Style: $label',
                () => prefs.setTheme(style: id),
                keepOpen: true,
                selected: prefs.themeStyle == id,
                // Tiles: the style's accent for the current colour.
                swatch: metro ? TvMetro.accentFor(theme, prefs, style: id) : null,
              ),
        ];
      },
    );
  }

  /// Customise: every look & behaviour setting (tv_settings.dart), plus the editors that
  /// live here (quick actions, colours, apps).
  void _customise() {
    tilesExtras = [
      TvAction(Icons.add_box_outlined, 'Add a tile', () => _addTile(back: _customise)),
      TvAction(
        Icons.restart_alt_rounded,
        'Reset Start',
        () => tvConfirm(context, title: 'Reset Start?', action: 'Reset (tiles, sizes and colours back to the start)', onConfirm: prefs.resetTiles),
        danger: true,
      ),
    ];
    final hidden = [
      for (final a in _apps)
        if (prefs.hidden.contains(a.package)) a,
    ];
    final mediaOff = tv.media.value?['granted'] == false;
    showTvCustomise(
      context,
      prefs: prefs,
      extras: [
        TvAction(Icons.apps_rounded, 'All apps', _allApps),
        TvAction(Icons.bolt_rounded, 'Edit quick actions', () => _editQuick(back: _customise)),
        if (widget.theme != null) TvAction(Icons.palette_outlined, 'Colours', () => _colours(back: _customise)),
        if (mediaOff) TvAction(Icons.play_circle_outline_rounded, 'Show what’s playing', tv.openNotificationAccess),
        for (final a in hidden) TvAction(Icons.visibility_outlined, 'Show ${a.label}', () => prefs.toggleHidden(a.package)),
        TvAction(Icons.home_outlined, 'Make this the home screen', tv.openHomeSettings),
      ],
    );
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // it's the home screen: Back returns to the default spot instead
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_moving != null) return _endMove(); // Back while moving an app = done
        if (_spotlightView) return _spotlightKey.currentState?.land();
        if (_tilesView) {
          final tiles = _tilesKey.currentState;
          if (tiles == null || tiles.endMove()) return;
          switch (TvLook.str('back')) {
            case 'search':
              _focus(-1, 0);
            case 'none':
              break;
            default:
              tiles.land();
          }
          return;
        }
        switch (TvLook.str('back')) {
          case 'search':
            _focus(-1, 0);
          case 'none':
            break;
          default:
            _focusDefault();
        }
      },
      child: _tilesView
          ? Scaffold(
              backgroundColor: TvDS.canvas,
              body: TvTilesStart(
                key: _tilesKey,
                prefs: prefs,
                apps: [
                  for (final a in _apps)
                    if (!prefs.hidden.contains(a.package)) a,
                ],
                header: _tilesHeader(),
                resume: _resumeInfo,
                onLaunch: (a) => _open(TvItem(key: a.package, kind: TvKind.app, title: a.label, package: a.package, app: a)),
                onResume: () => _resumeItem != null ? _open(_resumeItem!) : tv.mediaResume(),
                onAllApps: _allApps,
                onTop: () => _focus(-1, 0),
                quick: _tilesQuick(),
                resumeCards: _tilesResume(),
              ),
            )
          : _spotlightView
          ? Scaffold(
              backgroundColor: const Color(0xFF000000),
              body: Builder(
                builder: (context) {
                  TvLook.read(prefs);
                  return _Spotlight(
                    key: _spotlightKey,
                    rows: _spotlightRows(),
                    prefs: prefs,
                    hero: _hero,
                    backdrop: _backdrop,
                    header: _header,
                    missingLabel: _missingLabel,
                    onShow: _show,
                    onOpen: _open,
                    onOptions: _options,
                    onHeader: _headerAction,
                  );
                },
              ),
            )
          : Scaffold(
              backgroundColor: TvDS.scrim, // Classic: black under the picture and its fades
              body: LayoutBuilder(
                builder: (context, c) {
                  TvLook.read(prefs);
                  final rowsTop = c.maxHeight * TvLook.number('rowsAt');
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // ---- The picture, full screen; shaded behind the text and the rows ----
                      Positioned.fill(
                        child: TvLook.str('backdrop') == 'off'
                            ? const SizedBox.expand()
                            : _Backdrop(item: _backdrop, glowOnly: TvLook.str('backdrop') == 'glow'),
                      ),
                      // Fades into pure black (the canvas grey looked washed out next to the picture).
                      TvScrims(strength: TvLook.number('dim'), colour: TvDS.scrim, cinema: true),

                      // ---- Title block: what's focused ----
                      Positioned(
                        left: TvDS.safe.left,
                        top: TvDS.heroTop,
                        width: TvDS.heroW,
                        height: rowsTop - TvDS.heroTop - DS.s12,
                        child: _HeroInfo(
                          item: TvLook.on('hero') || _moving != null ? _hero : null,
                          chip: _chip,
                          rowTitle: _row >= 0 && _row < _rows.length && !_rows[_row].chips ? _rows[_row].title : null,
                          moving: _moving != null,
                        ),
                      ),

                      // ---- Rows ----
                      Positioned(
                        top: rowsTop,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRect(
                          child: SingleChildScrollView(
                            controller: _v,
                            physics: const ClampingScrollPhysics(),
                            clipBehavior: Clip.none,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final (r, row) in _rows.indexed) _buildRow(r, row),
                                // Room for the last row to reach the top of this area.
                                SizedBox(height: math.max(0, c.maxHeight - rowsTop - (_rows.lastOrNull?.height ?? 0))),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ---- Top bar ----
                      Positioned(
                        top: TvDS.safe.top,
                        left: TvDS.safe.left,
                        right: TvDS.safe.right,
                        child: _TopBar(
                          prefs: prefs,
                          buttons: [
                            for (final (i, id) in _header.indexed)
                              _TopButton(
                                id: id,
                                text: id == 'perms' ? _missingLabel : null,
                                focusNode: _node(-1, i),
                                onSelect: () => _headerAction(id),
                                onMove: (d) => _move(-1, i, d),
                                onFocus: () => _onFocus(-1, i),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _buildRow(int r, TvRow row) {
    final h = _h.putIfAbsent(row.id, ScrollController.new);
    final focusedRow = _row == r;
    if (row.chips) {
      return SizedBox(
        height: row.height,
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: TvDS.cardRowPad),
            child: SingleChildScrollView(
              controller: h,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: TvDS.safe.left),
              child: Row(
                children: [
                  for (final (i, item) in row.items.indexed) ...[
                    if (i > 0) const SizedBox(width: DS.s8),
                    if (item.key.startsWith('m:'))
                      _MediaButton(
                        key: ValueKey(_key(r, i)),
                        item: item,
                        focusNode: _node(r, i),
                        onSelect: () => _open(item),
                        onMove: (d) => _move(r, i, d),
                        onFocus: () => _onFocus(r, i),
                      )
                    else if (row.id == 'resume')
                      _ResumeButton(
                        key: ValueKey(_key(r, i)),
                        item: item,
                        focusNode: _node(r, i),
                        onSelect: () => _open(item),
                        onOptions: () => _options(row, i),
                        onMove: (d) => _move(r, i, d),
                        onFocus: () => _onFocus(r, i),
                      )
                    else
                      _QuickChip(
                        key: ValueKey(_key(r, i)),
                        item: item,
                        focusNode: _node(r, i),
                        moving: _moving == _key(r, i),
                        onSelect: () => _moving != null ? _endMove() : _open(item),
                        onOptions: () => _options(row, i),
                        onMove: (d) => _move(r, i, d),
                        onFocus: () => _onFocus(r, i),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: row.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (TvLook.on('rowTitles'))
            Padding(
              padding: EdgeInsets.only(left: TvDS.safe.left),
              child: SizedBox(
                height: TvDS.cardRowTitleH,
                child: AnimatedDefaultTextStyle(
                  duration: Motion.snapDuration,
                  curve: Motion.settle,
                  style: focusedRow ? TvDS.rowTitleFocused : TvDS.rowTitle,
                  child: Text(row.title),
                ),
              ),
            ),
          const SizedBox(height: TvDS.cardRowPad),
          SizedBox(
            height: row.cardH,
            child: SingleChildScrollView(
              controller: h,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none, // a focused card grows past the row's box
              padding: EdgeInsets.symmetric(horizontal: TvDS.safe.left),
              child: Row(
                children: [
                  for (final (i, item) in row.items.indexed) ...[
                    if (i > 0) const SizedBox(width: TvDS.gap),
                    if (item.key == 'all-apps')
                      _AllAppsTile(
                        key: ValueKey(_key(r, i)),
                        count: item.meta ?? '',
                        round: row.round,
                        width: row.cardW,
                        height: row.cardH,
                        focusNode: _node(r, i),
                        onSelect: () => _open(item),
                        onMove: (d) => _move(r, i, d),
                        onFocus: () => _onFocus(r, i),
                      )
                    else
                      _Card(
                        key: ValueKey(_key(r, i)),
                        item: item,
                        round: row.round,
                        width: row.cardW,
                        height: row.cardH,
                        focusNode: _node(r, i),
                        moving: _moving == _key(r, i),
                        onSelect: () => _moving != null ? _endMove() : _open(item),
                        onOptions: () => _options(row, i),
                        onMove: (d) => _move(r, i, d),
                        onFocus: () => _onFocus(r, i),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Backdrop ------------------------------------------------------------------

/// Full-bleed artwork for the focused item. Programmes show their poster; apps show their
/// banner as a soft, out-of-focus wash (drawn tiny and stretched — a free blur).
/// Each new picture fades in while settling from a slight zoom.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.item, this.glowOnly = false});
  final TvItem? item;
  final bool glowOnly; // Customise → Background picture: Soft glow

  @override
  Widget build(BuildContext context) {
    final it = item;
    return AnimatedSwitcher(
      duration: TvLook.anim(const Duration(milliseconds: 650)),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey(it?.key), child: it == null ? const SizedBox.expand() : _picture(it)),
    );
  }

  /// Where a full-screen picture is anchored: right of centre and high, so faces sit clear of
  /// the title on the left and the rows below.
  static const _focusPoint = Alignment(.5, -.4);

  Widget _picture(TvItem it) {
    if (glowOnly) return _wash(it);
    // Settles in from a slight zoom (1.8 s), then drifts slowly closer (4% over ~25 s) and stops —
    // a Ken Burns move. Reduced motion / lighter effects: still.
    final still = TvLook.str('motion') == 'reduced';
    final drift = !still && !Perf.lite.value;
    Widget settle(Widget child) => RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: drift ? 26000 : 1800),
        builder: (context, t, child) {
          const settleEnd = 1800 / 26000;
          final double scale;
          if (still) {
            scale = 1;
          } else if (!drift) {
            scale = 1.06 - .06 * Curves.easeOutCubic.transform(t);
          } else if (t < settleEnd) {
            scale = 1.06 - .06 * Curves.easeOutCubic.transform(t / settleEnd);
          } else {
            scale = 1 + .04 * Curves.easeInOutSine.transform((t - settleEnd) / (1 - settleEnd));
          }
          return Transform.scale(scale: scale, alignment: _focusPoint, child: child);
        },
        child: child,
      ),
    );
    if (it.art != null) {
      return settle(Image(image: it.art!, fit: BoxFit.cover, alignment: _focusPoint, gaplessPlayback: true, errorBuilder: (_, _, _) => _wash(it)));
    }
    if (it.image != null) {
      // Customise → Picture quality: the size asked of the host, and how wide it's kept.
      final src = ArtQuality.url(it.image!), w = ArtQuality.width;
      final ready = TvApps.instance.imageNow(src, width: w);
      return FutureBuilder<MemoryImage?>(
        future: ready != null ? Future.value(ready) : TvApps.instance.image(src, width: w),
        builder: (context, s) => s.data == null ? _wash(it) : settle(Image(image: s.data!, fit: BoxFit.cover, alignment: _focusPoint, gaplessPlayback: true)),
      );
    }
    // Streaming apps: what's popular on them now, one picture after another (their own art until
    // the first arrives). Other apps: their banner, pre-blurred on the TV into a soft wash.
    if (it.kind == TvKind.app && AppTrending.has(it.package)) {
      return _TrendingShow(package: it.package, still: TvLook.str('motion') == 'reduced', drift: drift, fallback: _appWash(it, settle));
    }
    return _appWash(it, settle);
  }

  Widget _appWash(TvItem it, Widget Function(Widget) settle) {
    if (it.kind == TvKind.app) {
      Widget wash(MemoryImage img) => settle(
        Opacity(
          opacity: .75,
          child: Image(image: img, fit: BoxFit.cover, filterQuality: FilterQuality.medium, gaplessPlayback: true),
        ),
      );
      final ready = TvApps.instance.backdropNow(it.package);
      if (ready != null) return wash(ready);
      return FutureBuilder<MemoryImage?>(future: TvApps.instance.backdrop(it.package), builder: (context, s) => s.data == null ? _wash(it) : wash(s.data!));
    }
    return _wash(it);
  }

  /// No artwork: a soft glow in a colour picked from the title, so each item still feels distinct.
  Widget _wash(TvItem it) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(center: const Alignment(.4, -.3), radius: 1.1, colors: [tvTint(it.title).withValues(alpha: .55), Colors.transparent]),
    ),
  );
}

/// What's popular on a streaming app (AppTrending), one picture every 2 s with a crossfade and
/// a slight drift; the app's own art ([fallback]) until the first one is ready. The next picture
/// loads while this one shows, and the show only moves on once it's there.
class _TrendingShow extends StatefulWidget {
  const _TrendingShow({required this.package, required this.fallback, this.still = false, this.drift = true});
  final String package;
  final Widget fallback;
  final bool still, drift; // reduced motion: no zoom; lighter effects: no drift

  @override
  State<_TrendingShow> createState() => _TrendingShowState();
}

class _TrendingShowState extends State<_TrendingShow> {
  static const every = Duration(seconds: 2), fade = Duration(milliseconds: 700);
  List<({String title, String image})> _titles = const [];
  int _i = -1; // showing
  MemoryImage? _shown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    AppTrending.instance.titles(widget.package).then((list) {
      if (!mounted || list.isEmpty) return;
      _titles = list;
      _next();
      _timer = Timer.periodic(every, (_) => _next());
    });
  }

  /// Moves on to the next picture that has loaded, and starts loading the one after it.
  void _next() {
    if (_titles.isEmpty || !mounted) return;
    final n = (_i + 1) % _titles.length;
    final img = TvApps.instance.imageNow(_src(n), width: ArtQuality.width);
    if (img == null) {
      TvApps.instance.image(_src(n), width: ArtQuality.width); // ready by the next tick
      return;
    }
    setState(() {
      _i = n;
      _shown = img;
    });
    AppTrending.instance.showing.value = (package: widget.package, title: _titles[n].title);
    TvApps.instance.image(_src((n + 1) % _titles.length), width: ArtQuality.width);
  }

  /// Title [i]'s picture at Customise → Picture quality's size.
  String _src(int i) => ArtQuality.url(_titles[i].image);

  @override
  void dispose() {
    _timer?.cancel();
    if (AppTrending.instance.showing.value?.package == widget.package) AppTrending.instance.showing.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _shown;
    return AnimatedSwitcher(
      duration: fade,
      layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: img == null
          ? KeyedSubtree(key: const ValueKey(-1), child: widget.fallback)
          : KeyedSubtree(
              key: ValueKey(_i),
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: widget.still || !widget.drift ? 1.0 : 1.04, end: 1.0), // eases back while it shows
                  duration: every + fade,
                  builder: (context, s, child) => Transform.scale(scale: s, alignment: _Backdrop._focusPoint, child: child),
                  child: Image(image: img, fit: BoxFit.cover, alignment: _Backdrop._focusPoint, gaplessPlayback: true),
                ),
              ),
            ),
    );
  }
}

// ---- Title block ---------------------------------------------------------------

class _HeroInfo extends StatelessWidget {
  const _HeroInfo({required this.item, required this.rowTitle, this.chip, this.moving = false});
  final TvItem? item;
  final TvItem? chip;
  final String? rowTitle;
  final bool moving;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      // Keyed by the item only: moving between chips just changes the hint, the title stays put
      // (re-keying on the chip re-ran the fade + slide, so the title bobbed on every chip).
      child: it == null ? const SizedBox.shrink() : KeyedSubtree(key: ValueKey('${it.key}$moving'), child: _content(it)),
    );
  }

  Widget _content(TvItem it) {
    final eyebrow = switch (it.kind) {
      TvKind.resume => 'CONTINUE WATCHING${it.appName != null ? ' · ${it.appName!.toUpperCase()}' : ''}',
      TvKind.program => (it.appName ?? '').toUpperCase(),
      TvKind.app => (rowTitle ?? 'App').toUpperCase(),
      TvKind.action => it.app != null ? 'QUICK ACTION · APP' : 'QUICK ACTION',
    };
    final c = chip;
    final action = c != null
        ? (c.key == 'q:edit' ? 'Edit quick actions' : (c.key.startsWith('m:') ? c.title : 'Open ${c.title}'))
        : switch (it.kind) {
            TvKind.resume => 'Resume',
            TvKind.program => (it.progress ?? 0) > 0 ? 'Resume' : 'Watch',
            TvKind.app || TvKind.action => it.key == 'q:edit' ? 'Edit' : 'Open',
          };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow.isNotEmpty) ...[Text(eyebrow, style: TvDS.heroEyebrow, maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: DS.s8)],
        Text(it.title, style: TvDS.heroTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        // A streaming app: what the picture behind is ("Popular on Netflix · Lupin").
        if (it.kind == TvKind.app && AppTrending.has(it.package))
          ValueListenableBuilder(
            valueListenable: AppTrending.instance.showing,
            builder: (context, now, _) => AnimatedSwitcher(
              // The old name fades out, then the new one in (crossfading text jumbles).
              duration: const Duration(milliseconds: 500),
              switchInCurve: const Interval(.5, 1),
              switchOutCurve: const Interval(.5, 1),
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
              child: now?.package != it.package
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey(now!.title),
                      padding: const EdgeInsets.only(top: DS.s8),
                      child: Text(
                        'Popular on ${AppTrending.providers[it.package]!.$2} · ${now.title}',
                        style: TvDS.heroMeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ),
        if (it.meta != null) ...[const SizedBox(height: DS.s8), Text(it.meta!, style: TvDS.heroMeta, maxLines: 1, overflow: TextOverflow.ellipsis)],
        if (it.progress != null) ...[const SizedBox(height: DS.s12), SizedBox(width: 220, child: _Progress(value: it.progress!))],
        if (it.description != null) ...[
          const SizedBox(height: DS.s12),
          Text(it.description!, style: TvDS.heroBody, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: DS.s16),
        if (moving)
          Row(
            children: [
              const _Keycap('', icons: [Icons.arrow_left_rounded, Icons.arrow_right_rounded]),
              const SizedBox(width: DS.s8),
              Text('Move', style: TvDS.heroMeta.copyWith(fontSize: 13)),
              const SizedBox(width: DS.s20),
              _Keycap('OK'),
              const SizedBox(width: DS.s8),
              Text('Done', style: TvDS.heroMeta.copyWith(fontSize: 13)),
            ],
          )
        else if (TvLook.on('hints'))
          Row(
            children: [
              _Keycap('OK'),
              const SizedBox(width: DS.s8),
              Text(action, style: TvDS.heroMeta.copyWith(fontSize: 13)),
              const SizedBox(width: DS.s20),
              _Keycap('Hold OK'),
              const SizedBox(width: DS.s8),
              Text('More', style: TvDS.heroMeta.copyWith(fontSize: 13)),
            ],
          ),
      ],
    );
  }
}

/// A remote button drawn as a little key, for the hints under the title.
class _Keycap extends StatelessWidget {
  const _Keycap(this.label, {this.icons = const []});
  final String label;
  final List<IconData> icons; // drawn keys (the font has no arrow glyphs)

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: TvDS.inkMuted),
    ),
    child: icons.isEmpty
        ? Text(label, style: TvDS.keycap)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final i in icons) Icon(i, size: 15, color: TvDS.ink)],
          ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: TvDS.progressH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: TvDS.line),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: ColoredBox(color: DS.hero),
          ),
        ],
      ),
    ),
  );
}

// ---- Top bar -------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.prefs, required this.buttons});
  final Prefs prefs;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, b) in buttons.indexed) ...[if (i > 0) const SizedBox(width: DS.s8), b],
        const Spacer(),
        // Centred on the buttons' 40-pt line (their labels hang below it).
        SizedBox(
          height: 40,
          child: Center(child: _Clock(prefs: prefs)),
        ),
      ],
    );
  }
}

/// Search is a pill with a label (the thing people use most); the rest are icons that say
/// what they are when focused.
class _TopButton extends StatelessWidget {
  const _TopButton({required this.id, required this.focusNode, required this.onSelect, this.onMove, this.onFocus, this.text, this.compact = false});
  final String id;
  final bool compact; // Spotlight: Search is an icon too (its name shows under it on focus)
  final String? text; // "2 permissions needed"
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (id) {
      'search' => (Icons.search_rounded, 'Search'),
      'voice' => (Icons.mic_none_rounded, 'Voice search'),
      'perms' => (Icons.warning_amber_rounded, text ?? 'Permissions needed'),
      _ => (Icons.tune_rounded, 'Customise'),
    };
    final pill = id == 'perms' || (id == 'search' && !compact);
    final warn = id == 'perms'; // the alert colour until focused
    return Semantics(
      button: true,
      label: label,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: TvLook.anim(Motion.pressIn * 2),
              height: 40,
              width: pill ? null : 40,
              padding: pill ? const EdgeInsets.symmetric(horizontal: DS.s16) : EdgeInsets.zero,
              decoration: DS.third
                  // Real: a key on the set (lit when focused; the warning one has a red cap).
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: Tactile.capFace(warn ? const Color(0xFFB03A36) : null),
                      border: Border.all(color: f ? Tactile.light : Tactile.rim, width: f ? 1.4 : .6),
                      boxShadow: [
                        ...Tactile.raised(pressed: f),
                        if (f) BoxShadow(color: Tactile.light.withValues(alpha: .4), blurRadius: 16),
                      ],
                    )
                  : BoxDecoration(
                      color: f ? TvDS.surfaceFocused : (warn ? DS.alert.withValues(alpha: .22) : TvDS.surface),
                      border: warn && !f ? Border.all(color: DS.alert.withValues(alpha: .7)) : null,
                      borderRadius: BorderRadius.circular(20),
                    ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: DS.third ? (warn ? Colors.white : Tactile.ink) : (f ? (warn ? DS.alert : TvDS.onLight) : TvDS.ink)),
                  if (pill) ...[
                    const SizedBox(width: DS.s8),
                    Text(
                      DS.third ? label.toUpperCase() : label,
                      style: DS.third
                          ? TvReal.legend(13, color: warn ? Colors.white : Tactile.ink)
                          : TvDS.hint.copyWith(fontSize: 15, color: f ? TvDS.onLight : TvDS.ink),
                    ),
                  ],
                ],
              ),
            ),
            // Label hangs under the icon without widening it (keeps the icons evenly spaced).
            if (!pill)
              SizedBox(
                width: 40,
                height: 26,
                child: OverflowBox(
                  maxWidth: 120,
                  alignment: Alignment.bottomCenter,
                  child: AnimatedOpacity(
                    opacity: f ? 1 : 0,
                    duration: TvLook.anim(Motion.pressIn * 2),
                    child: Text(label, style: TvDS.hint, maxLines: 1, softWrap: false),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small time + date, top right (the big picture is the star now).
class _Clock extends StatefulWidget {
  const _Clock({required this.prefs});
  final Prefs prefs;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _t;
  DateTime _now = DateTime.now();
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
    _tick();
  }

  // Wake on the next minute (no per-second rebuilds).
  void _tick() {
    final now = DateTime.now();
    _t = Timer(Duration(seconds: 60 - now.second, milliseconds: -now.millisecond + 20), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _tick();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h24 = switch (TvLook.str('clock24')) {
      '12' => false,
      '24' => true,
      _ => MediaQuery.alwaysUse24HourFormatOf(context),
    };
    final h = h24 ? _now.hour : (_now.hour % 12 == 0 ? 12 : _now.hour % 12);
    final time = '${h.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    // Real: the set's channel display — date and time as a lit dot-matrix readout.
    if (DS.third) {
      final read = [if (TvLook.on('date')) '${_days[_now.weekday - 1]} ${_now.day} ${_months[_now.month - 1]}', if (TvLook.on('clock')) time].join('  ');
      return TLcd(
        radius: 10,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: DotMatrix(read, dot: 2.6, color: TLcd.text),
      );
    }
    return ListenableBuilder(
      listenable: widget.prefs,
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (TvLook.on('date')) Text('${_days[_now.weekday - 1]} ${_now.day} ${_months[_now.month - 1]}', style: TvDS.date.copyWith(fontSize: 15)),
          if (TvLook.on('date') && TvLook.on('clock')) const SizedBox(width: DS.s12),
          if (TvLook.on('clock')) Text(time, style: TvDS.topClock.copyWith(fontSize: 22)),
        ],
      ),
    );
  }
}

// ---- Cards ---------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    required this.focusNode,
    required this.onSelect,
    required this.onOptions,
    this.onMove,
    this.onFocus,
    this.moving = false,
    this.round = false,
  });
  final bool moving; // being reordered: shows ‹ › and lifts a little higher
  final bool round; // an app as a circle (its icon), not a banner
  final TvItem item;
  final double width, height;
  final FocusNode focusNode;
  final VoidCallback onSelect, onOptions;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  double get radius => round ? width / 2 : TvDS.rTile;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: item.title,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onLongSelect: onOptions,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => AnimatedContainer(
          duration: TvLook.anim(Motion.pressIn * 2),
          width: width,
          height: height,
          // Ring + glow only on the focused card (one blur on screen at a time).
          foregroundDecoration: TvRing(on: f, radius: radius),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: f && TvLook.str('focus') == 'glow' ? const [BoxShadow(color: TvDS.glow, blurRadius: 22)] : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                item.app != null
                    ? (round ? TvAppIcon(app: item.app!, size: width) : TvAppArt(app: item.app!, width: width))
                    : _ProgramArt(item: item, width: width, height: height),
                // Moving: arrows on both sides say "← → to slide me".
                if (moving)
                  const ColoredBox(
                    color: Color(0x66000000),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.chevron_left_rounded, size: 36, color: TvDS.ink),
                        Icon(Icons.chevron_right_rounded, size: 36, color: TvDS.ink),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A show / film card: its still (or a tinted title card), app name, progress along the bottom.
class _ProgramArt extends StatelessWidget {
  const _ProgramArt({required this.item, required this.width, required this.height});
  final TvItem item;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    Widget picture;
    if (item.art != null) {
      // A saved picture that won't open: the title card, never a black box.
      picture = Image(image: item.art!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => _titleCard());
    } else if (item.image != null) {
      final ready = TvApps.instance.imageNow(item.image!);
      picture = FutureBuilder<MemoryImage?>(
        future: ready != null ? Future.value(ready) : TvApps.instance.image(item.image!),
        builder: (context, s) => s.data == null ? _titleCard() : Image(image: s.data!, fit: BoxFit.cover, gaplessPlayback: true),
      );
    } else {
      picture = _titleCard();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        picture,
        // Bottom shade so the name and progress read on any picture.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB3000000)], stops: [.45, 1]),
          ),
        ),
        Positioned(
          left: DS.s12,
          right: DS.s12,
          bottom: item.progress != null ? DS.s16 : DS.s12,
          child: Text(
            item.appName ?? '',
            style: TvDS.tileName.copyWith(color: TvDS.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (item.progress != null)
          Positioned(
            left: DS.s12,
            right: DS.s12,
            bottom: DS.s8,
            child: _Progress(value: item.progress!),
          ),
      ],
    );
  }

  /// No still: the title set large on a tint from its name — still looks intentional.
  Widget _titleCard() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tvTint(item.title), TvDS.canvas]),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(DS.s12, DS.s12, DS.s12, 34),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(item.title, style: TvDS.panelTitle.copyWith(fontSize: 20, height: 1.1), maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    ),
  );
}

// ---- Quick action chips ----------------------------------------------------------

/// A quick action above the rows: icon (or the app's picture) + label, white when focused.
class _QuickChip extends StatelessWidget {
  const _QuickChip({
    super.key,
    required this.item,
    required this.focusNode,
    required this.onSelect,
    required this.onOptions,
    this.onMove,
    this.onFocus,
    this.moving = false,
  });
  final TvItem item;
  final FocusNode focusNode;
  final VoidCallback onSelect, onOptions;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;
  final bool moving;

  @override
  Widget build(BuildContext context) {
    final edit = item.key == 'q:edit';
    final icon = edit ? Icons.add_rounded : tvActions[item.key]?.$2;
    // Customise → Resume & quick actions: chip size, and labels always / only when focused / never.
    final k = TvLook.get<double>('quickSize');
    final labels = TvLook.get<String>('quickLabels');
    return Semantics(
      button: true,
      label: edit ? 'Edit quick actions' : item.title,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onLongSelect: onOptions,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => AnimatedContainer(
          duration: TvLook.anim(Motion.pressIn * 2),
          height: 40 * k,
          padding: EdgeInsets.symmetric(horizontal: (edit || labels == 'never' || (labels == 'focus' && !f) ? DS.s12 : DS.s16) * k),
          decoration: BoxDecoration(
            color: f ? TvDS.surfaceFocused : const Color(0x33000000),
            borderRadius: BorderRadius.circular(20 * k),
            border: Border.all(color: f ? Colors.transparent : TvDS.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (moving) Icon(Icons.chevron_left_rounded, size: 18, color: f ? TvDS.onLight : TvDS.ink),
              if (item.app != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 32 * k,
                    height: 18 * k,
                    child: TvAppArt(app: item.app!, width: 32 * k),
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 20 * k, color: f ? TvDS.onLight : TvDS.ink),
              if (!edit && (labels == 'always' || (labels == 'focus' && f))) ...[
                SizedBox(width: DS.s8 * k),
                Text(
                  item.title,
                  style: TvDS.hint.copyWith(fontSize: 14 * k, color: f ? TvDS.onLight : TvDS.ink),
                ),
              ],
              if (moving) Icon(Icons.chevron_right_rounded, size: 18, color: f ? TvDS.onLight : TvDS.ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big "▶ Resume" button above the quick actions: picks up what's playing / paused.
class _ResumeButton extends StatelessWidget {
  const _ResumeButton({super.key, required this.item, required this.focusNode, required this.onSelect, required this.onOptions, this.onMove, this.onFocus});
  final TvItem item;
  final FocusNode focusNode;
  final VoidCallback onSelect, onOptions;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final app = item.appName;
    const ink = TvDS.ink;
    return Semantics(
      button: true,
      label: 'Resume ${item.title}',
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onLongSelect: onOptions,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => AnimatedContainer(
          duration: TvLook.anim(Motion.pressIn * 2),
          height: 40,
          padding: const EdgeInsets.only(left: DS.s12, right: DS.s20),
          // Outlined at rest (a light ring over a soft shade, like the chips), white when focused.
          // The border keeps its width either way, so nothing shifts on focus.
          decoration: BoxDecoration(
            color: f ? TvDS.surfaceFocused : const Color(0x33000000),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: f ? Colors.transparent : const Color(0xCCFFFFFF), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, size: 24, color: f ? TvDS.onLight : ink),
              const SizedBox(width: DS.s4),
              Text(
                item.playing ? 'Now playing' : 'Resume',
                style: TvDS.hint.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: f ? TvDS.onLight : ink),
              ),
              const SizedBox(width: DS.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  [item.title, if (app != null && app.isNotEmpty) 'on $app'].join(' '),
                  style: TvDS.hint.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: (f ? TvDS.onLight : ink).withValues(alpha: .75)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ⏮ ⏯ ⏭ next to Resume: round, quiet until focused.
class _MediaButton extends StatelessWidget {
  const _MediaButton({super.key, required this.item, required this.focusNode, required this.onSelect, this.onMove, this.onFocus});
  final TvItem item;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.key) {
      'm:prev' => Icons.skip_previous_rounded,
      'm:next' => Icons.skip_next_rounded,
      _ => item.title == 'Pause' ? Icons.pause_rounded : Icons.play_arrow_rounded,
    };
    return Semantics(
      button: true,
      label: item.title,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => AnimatedContainer(
          duration: TvLook.anim(Motion.pressIn * 2),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: f ? TvDS.surfaceFocused : const Color(0x33000000),
            shape: BoxShape.circle,
            border: Border.all(color: f ? Colors.transparent : TvDS.line),
          ),
          child: Icon(icon, size: 24, color: f ? TvDS.onLight : TvDS.ink),
        ),
      ),
    );
  }
}

/// The last tile of Your apps: a grid icon + "All apps · 42". Opens the All apps screen.
class _AllAppsTile extends StatelessWidget {
  const _AllAppsTile({
    super.key,
    required this.count,
    this.round = false,
    required this.width,
    required this.height,
    required this.focusNode,
    required this.onSelect,
    this.onMove,
    this.onFocus,
  });
  final String count;
  final bool round; // in a row of round app icons: a circle with the grid icon
  final double width, height;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final bool Function(AxisDirection)? onMove;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'All apps',
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onMove: onMove,
        onFocus: onFocus,
        builder: (context, f) => AnimatedContainer(
          duration: TvLook.anim(Motion.pressIn * 2),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: f ? TvDS.surfaceFocused : TvDS.surface,
            borderRadius: BorderRadius.circular(round ? width / 2 : TvDS.rTile),
            border: Border.all(color: f ? Colors.transparent : TvDS.line),
          ),
          child: round
              ? Icon(Icons.apps_rounded, size: width * .4, color: f ? TvDS.onLight : TvDS.ink) // the title block says "All apps"
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.apps_rounded, size: 32, color: f ? TvDS.onLight : TvDS.ink),
                    const SizedBox(height: DS.s8),
                    Text(count.isEmpty ? 'All apps' : 'All apps · $count', style: TvDS.tileName.copyWith(fontSize: 14, color: f ? TvDS.onLight : TvDS.ink)),
                  ],
                ),
        ),
      ),
    );
  }
}
