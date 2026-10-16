import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../prefs.dart';
import '../sheets.dart' show showWidgetPicker;
import '../ui/ds.dart';
import '../widgets.dart';
import 'landing.dart';
import 'tiles_home.dart' show TileGlyph, listSquare, tileAccent, tileAccentText;

/// The Tiles view's "today" page, left of Start (swipe right): what's happening now, in
/// Metro — a big lowercase title, accent section headers, accent squares.
///  · glance: date, next event, next alarm, battery
///  · now playing: the song with ⏮ ⏯ ⏭
///  · notifications: apps with unread ones (counts only; content is never read)
///  · notes: jot, tick off, long-press to delete (stored on the phone)
///  · screen time: today's total + top apps
///  · widgets: any app widgets you add here
class TodayPanel extends StatefulWidget {
  const TodayPanel({super.key, required this.prefs, required this.apps, required this.onLaunch});
  final Prefs prefs;
  final List<AppEntry> apps;
  final ValueChanged<AppEntry> onLaunch;

  @override
  State<TodayPanel> createState() => _TodayPanelState();
}

class _TodayPanelState extends State<TodayPanel> {
  Map _event = const {}, _battery = const {}, _usage = const {};
  (DateTime, String?)? _alarm;
  final _note = TextEditingController();
  Timer? _tick;

  Prefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    todayLanding.addListener(_load); // refreshed each time the page is landed on
    _load();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    todayLanding.removeListener(_load);
    _tick?.cancel();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([Apps.instance.nextEvent(), Apps.instance.battery(), Apps.instance.screenTime(), Apps.instance.nextAlarm()]);
    Apps.instance.refreshNotifCounts();
    Apps.instance.refreshMedia();
    if (!mounted) return;
    setState(() {
      _event = results[0] as Map;
      _battery = results[1] as Map;
      _usage = results[2] as Map;
      _alarm = results[3] as (DateTime, String?)?;
    });
  }

  AppEntry? _app(String package) => widget.apps.where((a) => a.package == package).firstOrNull;

  // ---- building blocks ----

  static const _white = Colors.white;

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(0, DS.s24, 0, DS.s8),
    child: Text(
      text,
      style: TextStyle(fontFamily: DS.font, color: tileAccentText(), fontSize: 22, fontWeight: FontWeight.w300),
    ),
  );

  Widget _square(Widget child, {double size = 44}) =>
      Container(width: size, height: size, decoration: listSquare(prefs, tileAccent(), prefs.tileRadius * .5), alignment: Alignment.center, child: child);

  Widget _row({required Widget lead, required String title, String? sub, VoidCallback? onTap, VoidCallback? onLongPress, Widget? trailing}) => InkWell(
    onTap: onTap,
    onLongPress: onLongPress,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          lead,
          const SizedBox(width: DS.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: DS.font, color: _white, fontSize: 18, fontWeight: FontWeight.w300),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: DS.font, color: Colors.white60, fontSize: 13),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );

  Widget _hint(String text, {VoidCallback? onTap}) => _row(
    lead: _square(const Icon(Icons.lock_open_rounded, color: _white, size: 22)),
    title: text,
    onTap: onTap,
  );

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _dur(int ms) {
    final m = ms ~/ 60000;
    return m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
  }

  // ---- sections ----

  List<Widget> _glance() {
    final now = DateTime.now();
    const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    const months = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
    final rows = <Widget>[];
    // Next event.
    if (_event['granted'] == false) {
      rows.add(_hint('allow calendar for your next event', onTap: Apps.instance.requestCalendar));
    } else if (_event['title'] != null) {
      final b = DateTime.fromMillisecondsSinceEpoch((_event['begin'] as num).toInt());
      final mins = b.difference(now).inMinutes;
      final when = _event['allDay'] == true
          ? 'all day'
          : (mins <= 0 ? 'now' : (mins < 60 ? 'in $mins min · ${_hm(b)}' : '${_hm(b)}${b.day != now.day ? ' · ${days[b.weekday - 1]}' : ''}'));
      rows.add(
        _row(
          lead: _square(const Icon(Icons.event_rounded, color: _white, size: 22)),
          title: _event['title'] as String,
          sub: when,
        ),
      );
    }
    // Next alarm.
    final a = _alarm;
    if (a != null) {
      final t = a.$1;
      rows.add(
        _row(
          lead: _square(const Icon(Icons.alarm_rounded, color: _white, size: 22)),
          title: _hm(t),
          sub: 'next alarm · ${t.day == now.day ? 'today' : days[t.weekday - 1]}',
        ),
      );
    }
    // Battery.
    if (_battery['level'] != null) {
      final level = (_battery['level'] as num).toInt();
      final charging = _battery['charging'] == true;
      final left = (_battery['chargeMsLeft'] as num?)?.toInt() ?? -1;
      rows.add(
        _row(
          lead: _square(Icon(charging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded, color: _white, size: 22)),
          title: '$level%',
          sub: charging ? (left > 0 ? 'charging · full in ${_dur(left)}' : 'charging') : 'battery',
          onTap: Apps.instance.openBatterySettings,
        ),
      );
    }
    return [
      Text(
        '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}',
        style: const TextStyle(fontFamily: DS.font, color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w300),
      ),
      ...rows,
    ];
  }

  Widget _nowPlaying(Map? m) {
    if (m == null || m['granted'] == false) {
      return _hint('allow notification access for music', onTap: Apps.instance.openNotificationAccess);
    }
    final title = m['title'] as String? ?? '';
    if (title.isEmpty) {
      return _row(
        lead: _square(const Icon(Icons.music_note_rounded, color: _white, size: 22)),
        title: 'nothing playing',
      );
    }
    final art = m['art'] as Uint8List?;
    final playing = m['playing'] == true;
    return _row(
      lead: ClipRRect(
        borderRadius: BorderRadius.circular(prefs.tileRadius * .5),
        child: art != null
            ? Image.memory(art, width: 56, height: 56, fit: BoxFit.cover, gaplessPlayback: true)
            : _square(const Icon(Icons.music_note_rounded, color: _white), size: 56),
      ),
      title: title,
      sub: [m['artist'], m['app']].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
      onTap: Apps.instance.mediaOpen,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous',
            onPressed: Apps.instance.mediaPrev,
            icon: const Icon(Icons.skip_previous_rounded, color: _white),
          ),
          IconButton(
            tooltip: playing ? 'Pause' : 'Play',
            onPressed: Apps.instance.mediaPlayPause,
            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: _white, size: 32),
          ),
          IconButton(
            tooltip: 'Next',
            onPressed: Apps.instance.mediaNext,
            icon: const Icon(Icons.skip_next_rounded, color: _white),
          ),
        ],
      ),
    );
  }

  List<Widget> _notifications(Map<String, int> counts, bool granted) {
    if (!granted) return [_hint('allow notification access', onTap: Apps.instance.openNotificationAccess)];
    final rows = [
      for (final e in counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        if (_app(e.key) case final app?)
          _row(
            lead: _square(TileGlyph(app: app, size: 28)),
            title: app.label,
            sub: e.value == 1 ? '1 new' : '${e.value} new',
            onTap: () => widget.onLaunch(app),
          ),
    ];
    if (rows.isEmpty) {
      return [
        _row(
          lead: _square(const Icon(Icons.done_all_rounded, color: _white, size: 22)),
          title: 'all caught up',
        ),
      ];
    }
    return rows.take(6).toList();
  }

  List<Widget> _notes() {
    final notes = prefs.todayNotes;
    void save(List<Map<String, Object>> list) => prefs.setTodayNotes(list);
    void add() {
      final t = _note.text.trim();
      if (t.isEmpty) return;
      HapticFeedback.selectionClick();
      save([
        ...notes.map((m) => {'t': m['t'] as String, 'done': m['done'] == true}),
        {'t': t, 'done': false},
      ]);
      _note.clear();
    }

    return [
      for (final (i, n) in notes.indexed)
        _row(
          lead: _square(Icon(n['done'] == true ? Icons.check_rounded : Icons.circle_outlined, color: _white, size: 22)),
          title: n['t'] as String,
          onTap: () {
            HapticFeedback.selectionClick();
            save([
              for (final (j, m) in notes.indexed) j == i ? {'t': m['t'] as String, 'done': m['done'] != true} : Map<String, Object>.from(m),
            ]);
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            save([
              for (final (j, m) in notes.indexed)
                if (j != i) Map<String, Object>.from(m),
            ]);
          },
          trailing: n['done'] == true ? const Icon(Icons.done_rounded, color: Colors.white38, size: 18) : null,
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            _square(const Icon(Icons.add_rounded, color: _white, size: 22)),
            const SizedBox(width: DS.s16),
            Expanded(
              child: TextField(
                controller: _note,
                onSubmitted: (_) => add(),
                textInputAction: TextInputAction.done,
                cursorColor: _white,
                style: const TextStyle(fontFamily: DS.font, color: _white, fontSize: 18, fontWeight: FontWeight.w300),
                decoration: const InputDecoration(
                  hintText: 'add a note',
                  hintStyle: TextStyle(fontFamily: DS.font, color: Colors.white54, fontSize: 18, fontWeight: FontWeight.w300),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
          ],
        ),
      ),
      if (notes.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: DS.s8),
          child: Text(
            'tap to tick off · long-press to delete',
            style: TextStyle(fontFamily: DS.font, color: Colors.white38, fontSize: 12),
          ),
        ),
    ];
  }

  List<Widget> _screenTime() {
    if (_usage['granted'] == false) return [_hint('allow usage access for screen time', onTap: Apps.instance.openUsageAccess)];
    final total = (_usage['total'] as num?)?.toInt();
    if (total == null) return const [];
    final top = [for (final m in (_usage['top'] as List? ?? const [])) m as Map];
    return [
      _row(
        lead: _square(const Icon(Icons.hourglass_bottom_rounded, color: _white, size: 22)),
        title: _dur(total),
        sub: 'on your phone today',
        onTap: Apps.instance.openScreenTime,
      ),
      for (final m in top.take(3))
        if (_app(m['package'] as String) case final app?)
          _row(
            lead: _square(TileGlyph(app: app, size: 28)),
            title: app.label,
            sub: _dur((m['ms'] as num).toInt()),
            onTap: () => widget.onLaunch(app),
          ),
    ];
  }

  List<Widget> _widgets() {
    final list = prefs.panelWidgets;
    return [
      for (final w in list)
        Padding(
          padding: const EdgeInsets.only(bottom: DS.s12),
          child: GestureDetector(
            onLongPress: () {
              HapticFeedback.mediumImpact();
              showOneSheet(
                context,
                header: SheetHeader(title: w['label'] as String, yours: true),
                actions: [
                  SheetAction(Icons.delete_outline_rounded, 'Remove widget', () {
                    Navigator.pop(context);
                    Apps.instance.removeWidget((w['id'] as num).toInt());
                    prefs.setPanelWidgets([
                      for (final x in list)
                        if (x['id'] != w['id']) Map<String, Object>.from(x),
                    ]);
                  }, danger: true),
                ],
              );
            },
            child: SizedBox(
              height: 180,
              child: _PanelWidget(id: (w['id'] as num).toInt(), label: w['label'] as String),
            ),
          ),
        ),
      _row(
        lead: _square(const Icon(Icons.add_rounded, color: _white, size: 22)),
        title: 'add a widget',
        sub: list.isEmpty ? 'any app’s widget, right here' : 'long-press a widget to remove it',
        onTap: () => showWidgetPicker(
          context,
          prefs: prefs,
          onAdded: (id, label) => prefs.setPanelWidgets([
            ...list.map(Map<String, Object>.from),
            {'id': id, 'label': label},
          ]),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([prefs, Apps.instance.media, Apps.instance.notifCounts]),
      builder: (context, _) {
        final media = Apps.instance.media.value;
        final granted = media?['granted'] != false;
        final sections = <(String, List<Widget>)>[
          ('glance', _glance()),
          ('now playing', [_nowPlaying(media)]),
          ('notifications', _notifications(Apps.instance.notifCounts.value, granted)),
          ('notes', _notes()),
          ('screen time', _screenTime()),
          ('widgets', _widgets()),
        ];
        return ListView(
          padding: EdgeInsets.fromLTRB(DS.s24, pad.top + DS.s24, DS.s16, pad.bottom + DS.s32),
          children: [
            Text(
              'today',
              style: DS.title.copyWith(color: _white, fontSize: 52, fontWeight: FontWeight.w300, letterSpacing: -1.5),
            ),
            for (final (i, (title, rows)) in sections.indexed)
              if (rows.isNotEmpty)
                Landed(
                  landing: todayLanding,
                  style: prefs.tileAnim,
                  delay: Duration(milliseconds: 50 * i),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (i > 0) _header(title) else const SizedBox(height: DS.s8),
                      ...rows,
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// An app widget on the today page (a placeholder in previews and tests).
class _PanelWidget extends StatelessWidget {
  const _PanelWidget({required this.id, required this.label});
  final int id;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Container(
        color: Colors.white12,
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white)),
      );
    }
    return AndroidView(
      key: ValueKey('panelwidget-$id'),
      viewType: 'one_launcher/appwidget',
      creationParams: {'id': id},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
