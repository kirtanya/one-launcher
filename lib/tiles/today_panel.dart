import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../prefs.dart';
import '../quick_actions.dart';
import '../quick_chips.dart' show ShortcutIcon;
import '../remote_sheet.dart' show showTvRemote;
import '../sheets.dart' show showWidgetPicker;
import '../top/header_fonts.dart';
import '../ui/ds.dart';
import '../widgets.dart';
import 'day_line.dart';
import 'landing.dart';
import 'tiles_home.dart';

/// The Tiles view's "today" page, left of Start (swipe right): One Launcher's own widgets —
/// glance, clock, calendar, music, notifications, battery, alarm, screen time, notes, TV remote,
/// quick actions — plus any app widget. In Metro, two layouts:
///  · tiles: live tiles on a 4-column grid, like Start (sizes, colours, glass from the tiles);
///  · list: sections with accent headers and accent-square rows.
/// Edit (✎) to add, remove, resize, recolour and reorder widgets and to change the layout and
/// background — all in place.
class TodayPanel extends StatefulWidget {
  const TodayPanel({super.key, required this.prefs, required this.apps, required this.onLaunch});
  final Prefs prefs;
  final List<AppEntry> apps;
  final ValueChanged<AppEntry> onLaunch;

  @override
  State<TodayPanel> createState() => _TodayPanelState();
}

/// One Launcher's own today widgets: kind → (name, icon, sizes it can take, default size).
const todayKinds = <String, (String, IconData, List<String>, String)>{
  'day': ('Your day', Icons.linear_scale_rounded, ['w', 'l'], 'w'),
  'glance': ('Glance', Icons.today_rounded, ['m', 'w'], 'w'),
  'clock': ('Clock', Icons.schedule_rounded, ['s', 'm', 'w'], 'm'),
  'calendar': ('Calendar', Icons.event_rounded, ['m', 'w', 'l'], 'w'),
  'music': ('Music', Icons.music_note_rounded, ['m', 'w', 'l'], 'w'),
  'notifications': ('Notifications', Icons.notifications_none_rounded, ['s', 'm', 'w'], 'm'),
  'battery': ('Battery', Icons.battery_std_rounded, ['s', 'm'], 's'),
  'alarm': ('Alarm', Icons.alarm_rounded, ['s', 'm'], 's'),
  'screentime': ('Screen time', Icons.hourglass_bottom_rounded, ['m', 'w'], 'm'),
  'notes': ('Notes', Icons.sticky_note_2_outlined, ['m', 'w', 'l'], 'w'),
  'remote': ('TV remote', Icons.settings_remote_rounded, ['s', 'm'], 's'),
  'actions': ('Quick actions', Icons.bolt_rounded, ['w', 'l'], 'w'),
};

const _sizeNames = {'s': 'Small', 'm': 'Medium', 'w': 'Wide', 'l': 'Large'};

/// The kind of a today tile ('calendar'…, or 'aw' for an app widget).
String todayKind(TileSpec t) => t.id.startsWith('aw:') ? 'aw' : t.id.substring(6);

/// The starting set (with any app widgets already placed on the page).
List<TileSpec> todayDefaults(Prefs prefs) => [
  const TileSpec('today:day', 'w'),
  const TileSpec('today:glance', 'w'),
  const TileSpec('today:music', 'w'),
  const TileSpec('today:calendar', 'm'),
  const TileSpec('today:notifications', 'm'),
  const TileSpec('today:notes', 'w'),
  const TileSpec('today:battery', 's'),
  const TileSpec('today:alarm', 's'),
  const TileSpec('today:screentime', 'm'),
  for (final w in prefs.panelWidgets) TileSpec('aw:${w['id']}', 'w', null, w['label'] as String?),
];

List<TileSpec> todayTiles(Prefs prefs) => prefs.todayTiles == null ? todayDefaults(prefs) : [for (final m in prefs.todayTiles!) TileSpec.fromJson(m)];

class _TodayPanelState extends State<TodayPanel> {
  Map _events = const {}, _battery = const {}, _usage = const {};
  (DateTime, String?)? _alarm;
  bool _editing = false;
  Timer? _tick;

  Prefs get prefs => widget.prefs;
  List<TileSpec> get _tiles => todayTiles(prefs);
  Future<void> _save(List<TileSpec> tiles) => prefs.setTodayTiles([for (final t in tiles) t.toJson()]);

  @override
  void initState() {
    super.initState();
    todayLanding.addListener(_load); // fresh each time the page is reached
    _load();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    todayLanding.removeListener(_load);
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Future.wait<Object?>([Apps.instance.events(), Apps.instance.battery(), Apps.instance.screenTime(), Apps.instance.nextAlarm()]);
    Apps.instance.refreshNotifCounts();
    Apps.instance.refreshMedia();
    if (!mounted) return;
    setState(() {
      _events = r[0] as Map;
      _battery = r[1] as Map;
      _usage = r[2] as Map;
      _alarm = r[3] as (DateTime, String?)?;
    });
  }

  AppEntry? _app(String package) => widget.apps.where((a) => a.package == package).firstOrNull;

  List<Map> get _eventList => [for (final e in (_events['events'] as List? ?? const [])) e as Map];

  // ---- shared bits ----

  static const _white = Colors.white;
  static TextStyle _t(double size, {FontWeight weight = FontWeight.w300, Color color = _white}) =>
      TextStyle(fontFamily: DS.font, color: color, fontSize: size, fontWeight: weight, height: 1.15);

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  static String _dur(int ms) {
    final m = ms ~/ 60000;
    return m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
  }

  static const _days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  static const _months = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];

  String _when(Map e) {
    final b = DateTime.fromMillisecondsSinceEpoch((e['begin'] as num).toInt());
    final now = DateTime.now();
    if (e['allDay'] == true) return b.day == now.day ? 'all day' : '${_days[b.weekday - 1]} · all day';
    final mins = b.difference(now).inMinutes;
    if (mins <= 0) return 'now';
    if (mins < 60) return 'in $mins min';
    return b.day == now.day ? _hm(b) : '${_days[b.weekday - 1].substring(0, 3)} ${_hm(b)}';
  }

  void _openClock() {
    final clock = widget.apps.where((a) => a.label.toLowerCase() == 'clock' || a.package.contains('deskclock')).firstOrNull;
    if (clock != null) widget.onLaunch(clock);
  }

  /// What tapping a widget does (outside edit).
  VoidCallback? _action(TileSpec t) => switch (todayKind(t)) {
    'glance' || 'calendar' => () {
      final e = _eventList.firstOrNull;
      e != null ? Apps.instance.openEvent((e['id'] as num).toInt()) : Apps.instance.requestCalendar();
    },
    'clock' || 'alarm' => _openClock,
    'music' => Apps.instance.media.value?['granted'] == false ? Apps.instance.openNotificationAccess : Apps.instance.mediaOpen,
    'notifications' => Apps.instance.openNotifications,
    'battery' => Apps.instance.openBatterySettings,
    'screentime' => _usage['granted'] == false ? Apps.instance.openUsageAccess : Apps.instance.openScreenTime,
    'notes' => () => _showNotes(context),
    'remote' => () => showTvRemote(context, prefs: prefs),
    'day' => () => showDaySlots(context, prefs: prefs),
    _ => null,
  };

  // ---- tile faces (tiles layout) ----

  Widget _face(TileSpec t) {
    final big = t.size == 'l', wide = t.size == 'w' || big, small = t.size == 's';
    final now = DateTime.now();
    Widget pad(Widget child) => Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: child);
    Widget label(String text) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _t(13, weight: FontWeight.w500),
    );
    Widget iconTile(IconData icon, String big, String? caption) => pad(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _white, size: small ? 20 : 24),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(big, style: _t(small ? 26 : 34)),
          ),
          if (caption != null && !small)
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(12, color: Colors.white70, weight: FontWeight.w400),
            ),
        ],
      ),
    );

    switch (todayKind(t)) {
      case 'glance':
        final e = _eventList.firstOrNull;
        return pad(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_days[now.weekday - 1], style: _t(wide ? 26 : 20)),
              Text(
                '${now.day} ${_months[now.month - 1]}',
                style: _t(14, color: Colors.white70, weight: FontWeight.w400),
              ),
              const Spacer(),
              if (e != null)
                Text(
                  '${e['title']} · ${_when(e)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(13, weight: FontWeight.w500),
                ),
              if (_alarm != null && wide)
                Text(
                  'alarm ${_hm(_alarm!.$1)}',
                  style: _t(12, color: Colors.white70, weight: FontWeight.w400),
                ),
            ],
          ),
        );
      case 'clock':
        final style = clockStyle(weight: prefs.tileClockWeight, width: prefs.tileClockWidth, slant: prefs.tileClockSlant, round: prefs.tileClockRound);
        return pad(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    _hm(now),
                    style: style.copyWith(color: _white, shadows: const []),
                  ),
                ),
              ),
              if (!small) Text('${_days[now.weekday - 1]} ${now.day}', style: _t(13, weight: FontWeight.w500)),
            ],
          ),
        );
      case 'calendar':
        if (_events['granted'] == false) return iconTile(Icons.lock_open_rounded, 'calendar', 'tap to allow');
        final events = _eventList.take(big ? 6 : (wide ? 2 : 1)).toList();
        final date = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${now.day}', style: _t(wide ? 44 : 40, weight: FontWeight.w200)),
            Text(_days[now.weekday - 1], style: _t(13, weight: FontWeight.w500)),
          ],
        );
        Widget event(Map e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e['title'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(15, weight: FontWeight.w400),
              ),
              Text(
                _when(e),
                style: _t(12, color: Colors.white70, weight: FontWeight.w400),
              ),
            ],
          ),
        );
        final none = Text(
          'no events',
          style: _t(14, color: Colors.white70, weight: FontWeight.w400),
        );
        if (!wide) {
          return pad(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [date, const Spacer(), if (events.isEmpty) none else label(events.first['title'] as String)],
            ),
          );
        }
        return pad(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              date,
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: big ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [if (events.isEmpty) none else ...events.map(event)],
                ),
              ),
            ],
          ),
        );
      case 'music':
        final m = Apps.instance.media.value;
        final title = m?['title'] as String? ?? '';
        if (m?['granted'] == false) return iconTile(Icons.lock_open_rounded, 'music', 'tap to allow');
        if (m == null || title.isEmpty) return iconTile(Icons.music_note_rounded, 'nothing playing', null);
        final art = m['art'] as Uint8List?;
        final playing = m['playing'] == true;
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (wide)
              IconButton(
                tooltip: 'Previous',
                onPressed: Apps.instance.mediaPrev,
                icon: const Icon(Icons.skip_previous_rounded, color: _white),
              ),
            IconButton(
              tooltip: playing ? 'Pause' : 'Play',
              onPressed: Apps.instance.mediaPlayPause,
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: _white, size: 30),
            ),
            if (wide)
              IconButton(
                tooltip: 'Next',
                onPressed: Apps.instance.mediaNext,
                icon: const Icon(Icons.skip_next_rounded, color: _white),
              ),
          ],
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            if (art != null) Image.memory(art, fit: BoxFit.cover, gaplessPlayback: true),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x26000000), Color(0xCC000000)]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(wide ? 18 : 14, weight: FontWeight.w500),
                  ),
                  if ((m['artist'] as String? ?? '').isNotEmpty)
                    Text(
                      m['artist'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(12, color: Colors.white70, weight: FontWeight.w400),
                    ),
                  Align(alignment: Alignment.centerRight, child: controls),
                ],
              ),
            ),
          ],
        );
      case 'notifications':
        final counts = Apps.instance.notifCounts.value;
        final total = counts.values.fold<int>(0, (a, b) => a + b);
        final apps = [
          for (final e in counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            if (_app(e.key) case final app?) (app, e.value),
        ];
        if (small) return iconTile(Icons.notifications_none_rounded, '$total', null);
        return pad(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('$total', style: _t(34)),
                  const SizedBox(width: 8),
                  Text(
                    total == 1 ? 'new' : 'new',
                    style: _t(13, color: Colors.white70, weight: FontWeight.w400),
                  ),
                ],
              ),
              const Spacer(),
              if (apps.isEmpty)
                Text('all caught up', style: _t(13, weight: FontWeight.w500))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (app, n) in apps.take(wide ? 6 : 3))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TileGlyph(app: app, size: 22),
                          if (wide) Text(' $n', style: _t(13, weight: FontWeight.w500)),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        );
      case 'battery':
        final level = (_battery['level'] as num?)?.toInt();
        final charging = _battery['charging'] == true;
        final left = (_battery['chargeMsLeft'] as num?)?.toInt() ?? -1;
        return iconTile(
          charging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
          level == null ? '--' : '$level%',
          charging ? (left > 0 ? 'full in ${_dur(left)}' : 'charging') : 'battery',
        );
      case 'alarm':
        final a = _alarm;
        return iconTile(Icons.alarm_rounded, a == null ? 'off' : _hm(a.$1), a == null ? 'no alarm' : (a.$1.day == now.day ? 'today' : _days[a.$1.weekday - 1]));
      case 'screentime':
        if (_usage['granted'] == false) return iconTile(Icons.lock_open_rounded, 'screen time', 'tap to allow');
        final total = (_usage['total'] as num?)?.toInt() ?? 0;
        final top = [for (final m in (_usage['top'] as List? ?? const [])) m as Map];
        return pad(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.hourglass_bottom_rounded, color: _white, size: 22),
              const Spacer(),
              Text(_dur(total), style: _t(wide ? 30 : 24)),
              Text(
                'today',
                style: _t(12, color: Colors.white70, weight: FontWeight.w400),
              ),
              if (wide)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      for (final m in top.take(3))
                        if (_app(m['package'] as String) case final app?)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Row(
                              children: [
                                TileGlyph(app: app, size: 20),
                                Text(' ${_dur((m['ms'] as num).toInt())}', style: _t(12, weight: FontWeight.w500)),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case 'notes':
        final notes = prefs.todayNotes;
        final open = notes.where((n) => n['done'] != true).toList();
        return pad(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.sticky_note_2_outlined, color: _white, size: 22),
                  const Spacer(),
                  Text(open.isEmpty ? '' : '${open.length}', style: _t(20)),
                ],
              ),
              const Spacer(),
              if (notes.isEmpty)
                Text(
                  'tap to add a note',
                  style: _t(14, color: Colors.white70, weight: FontWeight.w400),
                ),
              for (final n in notes.take(big ? 7 : (wide ? 2 : 1)))
                Text(
                  '${n['done'] == true ? '✓ ' : '· '}${n['t']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(14, weight: FontWeight.w400, color: n['done'] == true ? Colors.white54 : _white),
                ),
            ],
          ),
        );
      case 'remote':
        return iconTile(Icons.settings_remote_rounded, small ? 'tv' : (prefs.tvHost == null ? 'tv remote' : prefs.tvName.toLowerCase()), 'remote');
      case 'day':
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: big
              ? DayLine(prefs: prefs, legend: true, radius: prefs.tileRadius)
              : Center(
                  child: DayLine(prefs: prefs, radius: prefs.tileRadius),
                ),
        );
      case 'actions':
        final labels = prefs.quickLabels;
        final ids = prefs.quickChips.where((id) => builtInActions.containsKey(id) || labels.containsKey(id)).take(big ? 8 : 4).toList();
        return Padding(
          padding: const EdgeInsets.all(8),
          child: GridView.count(
            crossAxisCount: 4,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final id in ids)
                InkWell(
                  onTap: _editing ? null : () => runQuickAction(context, prefs, id, builtInActions[id]?.$1 ?? labels[id]!.split('|').first),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      builtInActions[id] != null ? Icon(builtInActions[id]!.$2, color: _white) : ShortcutIcon(id: id, size: 24, color: _white),
                      const SizedBox(height: 4),
                      Text(
                        (builtInActions[id]?.$1 ?? labels[id]!.split('|').first).toLowerCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(11, weight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case 'aw':
        return _AppWidgetView(id: int.parse(t.id.substring(3)), label: t.name ?? 'Widget');
    }
    return const SizedBox.shrink();
  }

  // ---- list rows (list layout) ----

  Widget _square(Widget child, {double size = 44}) =>
      Container(width: size, height: size, decoration: listSquare(prefs, tileAccent(), prefs.tileRadius * .5), alignment: Alignment.center, child: child);

  Widget _row({required Widget lead, required String title, String? sub, VoidCallback? onTap, Widget? trailing}) => InkWell(
    onTap: _editing ? null : onTap,
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
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(18)),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(13, color: Colors.white60, weight: FontWeight.w400),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );

  Widget _icon(IconData i) => _square(Icon(i, color: _white, size: 22));

  List<Widget> _rows(TileSpec t) {
    final now = DateTime.now();
    switch (todayKind(t)) {
      case 'glance':
        return [
          _row(
            lead: _icon(Icons.today_rounded),
            title: '${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}',
            sub: [if (_eventList.firstOrNull case final e?) '${e['title']} · ${_when(e)}', if (_alarm != null) 'alarm ${_hm(_alarm!.$1)}'].join('  ·  '),
            onTap: _action(t),
          ),
        ];
      case 'clock':
        return [_row(lead: _icon(Icons.schedule_rounded), title: _hm(now), sub: _days[now.weekday - 1], onTap: _openClock)];
      case 'calendar':
        if (_events['granted'] == false) return [_row(lead: _icon(Icons.lock_open_rounded), title: 'allow calendar', onTap: Apps.instance.requestCalendar)];
        final events = _eventList.take(t.size == 'l' ? 6 : 3).toList();
        if (events.isEmpty) return [_row(lead: _icon(Icons.event_available_rounded), title: 'no events')];
        return [
          for (final e in events)
            _row(lead: _icon(Icons.event_rounded), title: e['title'] as String, sub: _when(e), onTap: () => Apps.instance.openEvent((e['id'] as num).toInt())),
        ];
      case 'music':
        final m = Apps.instance.media.value;
        final title = m?['title'] as String? ?? '';
        if (m?['granted'] == false) {
          return [_row(lead: _icon(Icons.lock_open_rounded), title: 'allow notification access', onTap: Apps.instance.openNotificationAccess)];
        }
        if (m == null || title.isEmpty) return [_row(lead: _icon(Icons.music_note_rounded), title: 'nothing playing')];
        final art = m['art'] as Uint8List?;
        final playing = m['playing'] == true;
        return [
          _row(
            lead: ClipRRect(
              borderRadius: BorderRadius.circular(prefs.tileRadius * .5),
              child: art != null ? Image.memory(art, width: 56, height: 56, fit: BoxFit.cover, gaplessPlayback: true) : _icon(Icons.music_note_rounded),
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
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: _white, size: 30),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: Apps.instance.mediaNext,
                  icon: const Icon(Icons.skip_next_rounded, color: _white),
                ),
              ],
            ),
          ),
        ];
      case 'notifications':
        final rows = [
          for (final e in Apps.instance.notifCounts.value.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            if (_app(e.key) case final app?)
              _row(
                lead: _square(TileGlyph(app: app, size: 28)),
                title: app.label,
                sub: '${e.value} new',
                onTap: () => widget.onLaunch(app),
              ),
        ];
        return rows.isEmpty ? [_row(lead: _icon(Icons.done_all_rounded), title: 'all caught up')] : rows.take(6).toList();
      case 'battery':
        final level = (_battery['level'] as num?)?.toInt();
        return [
          _row(
            lead: _icon(_battery['charging'] == true ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded),
            title: level == null ? '--' : '$level%',
            sub: _battery['charging'] == true ? 'charging' : 'battery',
            onTap: Apps.instance.openBatterySettings,
          ),
        ];
      case 'alarm':
        return [_row(lead: _icon(Icons.alarm_rounded), title: _alarm == null ? 'no alarm' : _hm(_alarm!.$1), sub: 'next alarm', onTap: _openClock)];
      case 'screentime':
        if (_usage['granted'] == false) return [_row(lead: _icon(Icons.lock_open_rounded), title: 'allow usage access', onTap: Apps.instance.openUsageAccess)];
        final top = [for (final m in (_usage['top'] as List? ?? const [])) m as Map];
        return [
          _row(
            lead: _icon(Icons.hourglass_bottom_rounded),
            title: _dur((_usage['total'] as num?)?.toInt() ?? 0),
            sub: 'today',
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
      case 'notes':
        final notes = prefs.todayNotes;
        return [
          for (final n in notes.take(t.size == 'l' ? 10 : 4))
            _row(lead: _icon(n['done'] == true ? Icons.check_rounded : Icons.circle_outlined), title: n['t'] as String, onTap: () => _showNotes(context)),
          _row(lead: _icon(Icons.add_rounded), title: notes.isEmpty ? 'add a note' : 'all notes', onTap: () => _showNotes(context)),
        ];
      case 'remote':
        return [
          _row(
            lead: _icon(Icons.settings_remote_rounded),
            title: prefs.tvHost == null ? 'set up a tv' : prefs.tvName,
            sub: 'tv remote',
            onTap: () => showTvRemote(context, prefs: prefs),
          ),
        ];
      case 'day':
        return [
          GestureDetector(
            onTap: _editing ? null : () => showDaySlots(context, prefs: prefs),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: DayLine(prefs: prefs, legend: t.size == 'l', radius: prefs.tileRadius),
            ),
          ),
        ];
      case 'actions':
        return [SizedBox(height: t.size == 'l' ? 180 : 96, child: _face(t))];
      case 'aw':
        return [SizedBox(height: t.size == 'l' ? 360 : 180, child: _face(t))];
    }
    return const [];
  }

  String _title(TileSpec t) => todayKind(t) == 'aw' ? (t.name ?? 'Widget') : todayKinds[todayKind(t)]!.$1;

  // ---- editing ----

  Future<void> _options(TileSpec t) async {
    HapticFeedback.mediumImpact();
    final kind = todayKind(t);
    final sizes = kind == 'aw' ? const ['w', 'l'] : todayKinds[kind]!.$3;
    final tiles = prefs.todayLayout == 'tiles';
    await showOneSheetWith(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          final now = _tiles.firstWhere((x) => x.id == t.id, orElse: () => t);
          final i = _tiles.indexWhere((x) => x.id == t.id);
          Widget box(String text, bool on, VoidCallback tap) => Padding(
            padding: const EdgeInsets.only(right: DS.s8, bottom: DS.s8),
            child: Material(
              color: on ? DS.hero : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DS.rMedia),
                side: BorderSide(color: on ? DS.hero : DS.inkFaint, width: 1.5),
              ),
              child: InkWell(
                onTap: tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: 10),
                  child: Text(DS.cased(text), style: DS.rowTitle.copyWith(fontSize: 14, color: on ? _white : DS.ink)),
                ),
              ),
            ),
          );
          Widget act(IconData icon, String text, VoidCallback? tap, {bool danger = false}) => InkWell(
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: tap == null ? DS.inkFaint : (danger ? DS.alert : DS.ink)),
                  const SizedBox(width: DS.s16),
                  Text(
                    DS.cased(text),
                    style: DS.rowTitle.copyWith(fontWeight: FontWeight.w400, fontSize: 18, color: tap == null ? DS.inkFaint : (danger ? DS.alert : DS.ink)),
                  ),
                ],
              ),
            ),
          );
          Future<void> update(TileSpec next) async {
            await _save([for (final x in _tiles) x.id == t.id ? next : x]);
            refresh(() {});
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s16),
                child: SheetHeader(title: _title(t), yours: kind == 'aw'),
              ),
              if (tiles) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
                  child: Text(DS.cased('Size'), style: DS.eyebrow),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                  child: Wrap(children: [for (final sz in sizes) box(_sizeNames[sz]!, now.size == sz, () => update(now.resized(sz)))]),
                ),
                act(Icons.palette_outlined, 'Colour', () async {
                  final c = await pickTileColour(ctx, current: now.colour);
                  if (c != null) await update(now.recoloured(c == 'default' ? null : c));
                }),
              ],
              act(Icons.arrow_upward_rounded, 'Move earlier', i <= 0 ? null : () => _move(t.id, -1).then((_) => refresh(() {}))),
              act(Icons.arrow_downward_rounded, 'Move later', i < 0 || i >= _tiles.length - 1 ? null : () => _move(t.id, 1).then((_) => refresh(() {}))),
              act(Icons.delete_outline_rounded, 'Remove', () {
                Navigator.pop(ctx);
                _remove(t);
              }, danger: true),
              const SizedBox(height: DS.s8),
            ],
          );
        },
      ),
    );
  }

  /// Holding a widget picks it up: edit mode comes on (with every widget's ⋯ menu).
  void _pickUp() {
    HapticFeedback.mediumImpact();
    setState(() {
      _editing = true;
      _dragging = true;
    });
  }

  /// While a widget is held, the edit toolbar waits: it would push everything down under the
  /// finger. It appears once the widget is let go.
  bool _dragging = false;
  void _drop() {
    if (_dragging && mounted) setState(() => _dragging = false);
  }

  DateTime _lastMove = DateTime(0);

  /// Dragged over another widget: take its place (the rest make room), a beat apart so the
  /// reflow settles under the finger.
  Future<void> _moveTo(String dragged, String target) async {
    final now = DateTime.now();
    if (now.difference(_lastMove) < const Duration(milliseconds: 220)) return;
    _lastMove = now;
    final list = [..._tiles];
    final from = list.indexWhere((t) => t.id == dragged), to = list.indexWhere((t) => t.id == target);
    if (from < 0 || to < 0 || from == to) return;
    list.insert(to, list.removeAt(from));
    HapticFeedback.selectionClick();
    await _save(list);
  }

  Future<void> _move(String id, int by) async {
    final list = [..._tiles];
    final i = list.indexWhere((x) => x.id == id);
    final j = i + by;
    if (i < 0 || j < 0 || j >= list.length) return;
    HapticFeedback.selectionClick();
    list.insert(j, list.removeAt(i));
    await _save(list);
  }

  Future<void> _remove(TileSpec t) async {
    HapticFeedback.mediumImpact();
    if (t.id.startsWith('aw:')) Apps.instance.removeWidget(int.parse(t.id.substring(3)));
    await _save([
      for (final x in _tiles)
        if (x.id != t.id) x,
    ]);
  }

  Future<void> _add() async {
    final have = {for (final t in _tiles) t.id};
    await showOneSheet(
      context,
      header: const SheetHeader(title: 'Add a widget', subtitle: 'One Launcher’s own, or any app’s'),
      actions: [
        for (final MapEntry(key: kind, value: (name, icon, _, size)) in todayKinds.entries)
          if (!have.contains('today:$kind'))
            SheetAction(icon, name, () {
              Navigator.pop(context);
              HapticFeedback.mediumImpact();
              _save([..._tiles, TileSpec('today:$kind', size)]);
            }),
        SheetAction(Icons.widgets_outlined, 'App widget…', () {
          Navigator.pop(context);
          showWidgetPicker(context, prefs: prefs, onAdded: (id, label) => _save([..._tiles, TileSpec('aw:$id', 'w', null, label)]));
        }),
      ],
    );
  }

  /// Notes: add, tick off, delete — a sheet over the page.
  Future<void> _showNotes(BuildContext context) async {
    await showOneSheetWith(
      context,
      keyboard: true,
      builder: (ctx) => WithTextController(
        builder: (ctx, text) => ListenableBuilder(
          listenable: prefs,
          builder: (ctx, _) {
            final notes = prefs.todayNotes;
            List<Map<String, Object>> plain() => [
              for (final n in notes) {'t': n['t'] as String, 'done': n['done'] == true},
            ];
            void add() {
              final v = text.text.trim();
              if (v.isEmpty) return;
              HapticFeedback.selectionClick();
              prefs.setTodayNotes([
                ...plain(),
                {'t': v, 'done': false},
              ]);
              text.clear();
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
                  child: SheetHeader(title: 'Notes', subtitle: 'Tap to tick off · long-press to delete'),
                ),
                for (final (i, n) in notes.indexed)
                  InkWell(
                    onTap: () {
                      final list = plain();
                      list[i] = {'t': list[i]['t']!, 'done': list[i]['done'] != true};
                      prefs.setTodayNotes(list);
                    },
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      prefs.setTodayNotes(plain()..removeAt(i));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            n['done'] == true ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            color: n['done'] == true ? DS.inkFaint : DS.ink,
                          ),
                          const SizedBox(width: DS.s16),
                          Expanded(
                            child: Text(
                              n['t'] as String,
                              style: DS.rowTitle.copyWith(
                                fontWeight: FontWeight.w400,
                                color: n['done'] == true ? DS.inkFaint : DS.ink,
                                decoration: n['done'] == true ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s12, DS.s8),
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, color: DS.ink),
                      const SizedBox(width: DS.s16),
                      Expanded(
                        child: TextField(
                          controller: text,
                          autofocus: notes.isEmpty,
                          onSubmitted: (_) => add(),
                          textInputAction: TextInputAction.done,
                          style: DS.rowTitle.copyWith(fontWeight: FontWeight.w400),
                          decoration: InputDecoration(hintText: DS.cased('Add a note'), border: InputBorder.none, hintStyle: DS.rowSub),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add',
                        onPressed: add,
                        icon: Icon(Icons.arrow_upward_rounded, color: DS.ink),
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

  // ---- layouts ----

  Widget _editBar() {
    Widget box(String text, bool on, VoidCallback tap) => Padding(
      padding: const EdgeInsets.only(right: DS.s8, bottom: DS.s8),
      child: Material(
        color: on ? tileAccent() : Colors.white.withValues(alpha: .1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(prefs.tileRadius * .5)),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            tap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(text, style: _t(15, weight: FontWeight.w400)),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: DS.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            children: [
              box('tiles', prefs.todayLayout == 'tiles', () => prefs.setTodayLook(layout: 'tiles')),
              box('list', prefs.todayLayout == 'list', () => prefs.setTodayLook(layout: 'list')),
              const SizedBox(width: DS.s12),
              box('wallpaper', prefs.todayBg == 'wallpaper', () => prefs.setTodayLook(bg: 'wallpaper')),
              box('black', prefs.todayBg == 'black', () => prefs.setTodayLook(bg: 'black')),
            ],
          ),
          Wrap(children: [box('+ add widget', false, _add), box('reset', false, () => prefs.setTodayTiles(null))]),
          Text(
            'hold and drag to move · ⋯ for size, colour and more',
            style: _t(12, color: Colors.white54, weight: FontWeight.w400),
          ),
        ],
      ),
    );
  }

  Widget _tilesGrid(List<TileSpec> tiles) => LayoutBuilder(
    builder: (context, c) {
      const gap = 6.0, cols = 4;
      final unit = (c.maxWidth - (cols - 1) * gap) / cols;
      final placed = packTiles(tiles, cols: cols);
      var rows = 0;
      for (final (t, _, r) in placed) {
        rows = rows < r + t.span.$2 ? r + t.span.$2 : rows;
      }
      return SizedBox(
        height: rows == 0 ? 0 : rows * unit + (rows - 1) * gap,
        child: Stack(
          children: [
            for (final (t, col, row) in placed)
              AnimatedPositioned(
                key: ValueKey(t.id),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: col * (unit + gap),
                top: row * (unit + gap),
                width: t.span.$1 * unit + (t.span.$1 - 1) * gap,
                height: t.span.$2 * unit + (t.span.$2 - 1) * gap,
                child: Landed(
                  landing: todayLanding,
                  style: prefs.tileAnim,
                  delay: Duration(milliseconds: 40 * col + 22 * row),
                  child: _Reorderable(
                    id: t.id,
                    editing: _editing,
                    onPickUp: _pickUp,
                    onDrop: _drop,
                    onMove: _moveTo,
                    ghost: t.id.startsWith('aw:') ? null : _face(t),
                    child: _TodayTile(
                      tile: t,
                      prefs: prefs,
                      editing: _editing,
                      onTap: _editing ? () => _options(t) : _action(t),
                      onMenu: () => _options(t),
                      child: _face(t),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _list(List<TileSpec> tiles) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, t) in tiles.indexed)
        Landed(
          landing: todayLanding,
          style: prefs.tileAnim,
          delay: Duration(milliseconds: 50 * i),
          child: _Reorderable(
            id: t.id,
            editing: _editing,
            onPickUp: _pickUp,
            onDrop: _drop,
            onMove: _moveTo,
            ghost: Container(
              height: 56,
              color: tileAccent().withValues(alpha: .85),
              padding: const EdgeInsets.symmetric(horizontal: DS.s16),
              alignment: Alignment.centerLeft,
              child: Text(_title(t).toLowerCase(), style: _t(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, DS.s20, 0, DS.s8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_title(t).toLowerCase(), style: _t(22, color: tileAccentText())),
                      ),
                      if (_editing)
                        IconButton(
                          tooltip: 'Widget options',
                          onPressed: () => _options(t),
                          icon: const Icon(Icons.more_horiz_rounded, color: _white),
                        ),
                    ],
                  ),
                ),
                ..._rows(t),
              ],
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final now = DateTime.now();
    return ListenableBuilder(
      listenable: Listenable.merge([prefs, Apps.instance.media, Apps.instance.notifCounts]),
      builder: (context, _) {
        final tiles = _tiles;
        return PopScope(
          canPop: !_editing,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _editing) setState(() => _editing = false);
          },
          child: ColoredBox(
            color: prefs.todayBg == 'black' ? Colors.black : Colors.transparent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(), // pull down to search even when it fits
              padding: EdgeInsets.fromLTRB(12, pad.top + DS.s24, 12, pad.bottom + DS.s32),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('today', style: _t(52, weight: FontWeight.w300).copyWith(letterSpacing: -1.5, height: 1)),
                            const SizedBox(height: 4),
                            Text('${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}', style: _t(17, color: Colors.white70)),
                          ],
                        ),
                      ),
                      _editing
                          ? FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: tileAccent(),
                                foregroundColor: _white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(prefs.tileRadius * .5)),
                              ),
                              onPressed: () => setState(() => _editing = false),
                              child: const Text('done'),
                            )
                          : IconButton(
                              tooltip: 'Edit today',
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() => _editing = true);
                              },
                              icon: const Icon(Icons.edit_outlined, color: _white),
                            ),
                    ],
                  ),
                ),
                if (_editing && !_dragging) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _editBar()),
                const SizedBox(height: DS.s20),
                if (tiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(DS.s16),
                    child: Text('nothing here — tap ✎, then + add widget', style: _t(16, color: Colors.white70)),
                  )
                else if (prefs.todayLayout == 'list')
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _list(tiles))
                else
                  _tilesGrid(tiles),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A today widget as a live tile: the tile look (colour, glass, corners, tilt) from Start.
/// In edit mode it sits back a little and shows ⋯; tap for its options.
class _TodayTile extends StatelessWidget {
  const _TodayTile({required this.tile, required this.prefs, required this.editing, required this.onTap, required this.onMenu, required this.child});
  final TileSpec tile;
  final Prefs prefs;
  final bool editing;
  final VoidCallback? onTap, onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final face = FutureBuilder<Color>(
      future: tileColour(tile, prefs),
      builder: (context, snap) => TileSurface(
        colour: snap.data ?? tileAccent().withValues(alpha: prefs.tileOpacity),
        prefs: prefs,
        onTap: onTap ?? () {},
        child: child,
      ),
    );
    return AnimatedScale(
      duration: const Duration(milliseconds: 200),
      scale: editing ? .94 : 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TilePress(prefs: prefs, child: face),
          // Its menu (size, colour, remove…), like a tile's edit buttons on Start.
          if (editing)
            Positioned(
              right: 0,
              top: 0,
              child: Tooltip(
                message: 'Widget options',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onMenu,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.more_horiz_rounded, size: 18, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hold to pick a widget up (edit mode comes on), drag it over another to take its place.
class _Reorderable extends StatelessWidget {
  const _Reorderable({
    required this.id,
    required this.editing,
    required this.onPickUp,
    required this.onDrop,
    required this.onMove,
    required this.child,
    this.ghost,
  });
  final VoidCallback onDrop;
  final String id;
  final bool editing;
  final VoidCallback onPickUp;
  final Future<void> Function(String dragged, String target) onMove;
  final Widget child;
  final Widget? ghost; // what follows the finger (app widgets: a plain box)

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        if (d.data != id) onMove(d.data, id);
        return d.data != id;
      },
      builder: (context, hovering, _) => LongPressDraggable<String>(
        data: id,
        delay: editing ? const Duration(milliseconds: 150) : kLongPressTimeout,
        onDragStarted: onPickUp,
        onDragEnd: (_) => onDrop(),
        feedback: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: box.maxWidth,
            height: box.hasBoundedHeight ? box.maxHeight : null,
            child: Opacity(opacity: .85, child: ghost ?? Container(color: tileAccent().withValues(alpha: .7))),
          ),
        ),
        childWhenDragging: Opacity(opacity: .25, child: child),
        child: child,
      ),
    ),
  );
}

/// An app widget on the today page (a placeholder in previews and tests).
class _AppWidgetView extends StatelessWidget {
  const _AppWidgetView({required this.id, required this.label});
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
      key: ValueKey('todaywidget-$id'),
      viewType: 'one_launcher/appwidget',
      creationParams: {'id': id},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
