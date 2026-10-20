import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../one_stream.dart';
import '../one_stream_widgets.dart';
import '../prefs.dart';
import '../quick_actions.dart';
import '../quick_chips.dart' show ShortcutIcon;
import '../remote_sheet.dart' show showTvRemote;
import '../sheets.dart' show showWidgetPicker;
import '../top/header_fonts.dart';
import '../ui/components.dart';
import '../ui/ds.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';
import '../widgets.dart';
import 'day_line.dart';
import 'landing.dart';
import 'tiles_home.dart';

/// The "today" page, left of home (swipe right) — Tiles: left of Start; Classic: the side panel
/// left of the clock and drawer, in Classic's own look. One Launcher's own widgets —
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
  // One Stream's Continue watching (offered only while One Stream is installed; not a default).
  'stream': ('Continue watching', Icons.movie_outlined, ['w', 'l'], 'w'),
};

const _sizeNames = {'s': 'Small', 'm': 'Medium', 'w': 'Wide', 'l': 'Large'};

/// The kind of a today tile ('calendar'…, or 'aw' for an app widget).
String todayKind(TileSpec t) => t.id.startsWith('aw:') ? 'aw' : t.id.substring(6);

/// The today page is in edit mode (Back ends editing first, before it leaves the page).
final todayEditing = ValueNotifier<bool>(false);

/// Ping to bring the Classic home's today panel into view (Settings → Today panel → Open it).
final openToday = TodaySignal();

class TodaySignal extends ChangeNotifier {
  void ping() => notifyListeners();
}

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
  List<OneStreamTitle> _watching = const []; // One Stream's Continue watching
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
    if (_tiles.any((t) => t.id == 'today:stream')) {
      OneStream.instance.continueWatching().then((list) {
        if (mounted) setState(() => _watching = list);
      });
    }
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

  /// The Classic home's side panel speaks Classic (docs/DESIGN_LANGUAGES.md): rounded cards in
  /// the theme's palette (glass when the Classic home is glass), Sentence case, medium weights.
  /// Metro (the Tiles view): live tiles, lowercase, light type.
  bool get _classic => !DS.metro;

  /// Whether a widget hugs its content: its own Height, else the panel's Card height setting
  /// (Settings → Today panel). App widgets can't be measured: always the grid's height.
  bool _hugs(TileSpec t) => prefs.todayLayout != 'list' && !t.id.startsWith('aw:') && (t.height ?? (prefs.todayHug ? 'hug' : 'fixed')) == 'hug';

  /// The face being built hugs (set by [_face]).
  bool _hug = false;

  /// The space that pushes a face's words to its bottom — just a small gap when hugging.
  Widget _grow() => _hug ? const SizedBox(height: DS.s12) : const Spacer();
  Widget _flex(Widget child) => _hug ? child : Expanded(child: child);

  /// The ink of what's being built: white on tiles (Metro), over album art and on the wallpaper;
  /// on a Classic card, the card's ink (the hero card: the hero's ink). Set as each widget is built.
  Color _white = Colors.white;
  Color get _soft => _white.withValues(alpha: .7);
  Color get _faint => _white.withValues(alpha: .54);

  TextStyle _t(double size, {FontWeight weight = FontWeight.w300, Color? color}) => TextStyle(
    fontFamily: DS.font,
    color: color ?? _white,
    fontSize: size,
    // Classic: big figures medium, the rest regular (or heavier where asked).
    fontWeight: _classic ? (size >= 20 ? FontWeight.w500 : (weight.value < 400 ? FontWeight.w400 : weight)) : weight,
    letterSpacing: _classic && size >= 26 ? -.5 : null,
    height: 1.15,
  );

  /// Words in the language's case: Metro as written (lowercase); Classic Sentence case.
  String _c(String s) => _classic && s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : s;
  String _day(int weekday) => _c(_days[weekday - 1]);
  String _month(int m) => _c(_months[m - 1]);

  /// The card a Classic widget sits on: the first one is the hero (like the pinned card on
  /// home), the rest the theme's cards.
  Color _cardColour(bool hero) => hero ? DS.hero : DS.card;
  Color _cardInk(bool hero) => hero ? DS.heroInk : DS.ink;

  /// An app's mark: Metro's white glyph on a tile; Classic: the app's own icon.
  Widget _glyph(AppEntry app, double size) => _classic ? AppIcon(app, size: size) : TileGlyph(app: app, size: size);

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
    if (e['allDay'] == true) return b.day == now.day ? 'all day' : '${_day(b.weekday)} · all day';
    final mins = b.difference(now).inMinutes;
    if (mins <= 0) return 'now';
    if (mins < 60) return 'in $mins min';
    return b.day == now.day ? _hm(b) : '${_day(b.weekday).substring(0, 3)} ${_hm(b)}';
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
    'stream' => _watching.isEmpty ? null : () => OneStream.instance.open(_watching.first.link),
    _ => null,
  };

  // ---- tile faces (tiles layout) ----

  Widget _face(TileSpec t, {bool hero = false}) {
    _hug = _hugs(t);
    final big = t.size == 'l', wide = t.size == 'w' || big, small = t.size == 's';
    final now = DateTime.now();
    _white = _classic ? _cardInk(hero) : Colors.white;
    // Classic cards breathe more (and keep words clear of their round corners).
    final inset = _classic
        ? (small ? const EdgeInsets.fromLTRB(14, 12, 12, 12) : const EdgeInsets.fromLTRB(18, 16, 18, 14))
        : const EdgeInsets.fromLTRB(12, 10, 12, 10);
    Widget pad(Widget child) => Padding(padding: inset, child: child);
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
          _grow(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_c(big), style: _t(small ? 26 : 34)),
          ),
          if (caption != null && !small)
            Text(
              _c(caption),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(12, color: _soft, weight: FontWeight.w400),
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
              Text(_day(now.weekday), style: _t(wide ? 26 : 20)),
              Text(
                '${now.day} ${_month(now.month)}',
                style: _t(14, color: _soft, weight: FontWeight.w400),
              ),
              _grow(),
              if (e != null)
                Text(
                  '${e['title']} · ${_when(e)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(13, weight: FontWeight.w500),
                ),
              if (_alarm != null && wide)
                Text(
                  _c('alarm ${_hm(_alarm!.$1)}'),
                  style: _t(12, color: _soft, weight: FontWeight.w400),
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
              _flex(
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    _hm(now),
                    style: style.copyWith(color: _white, shadows: const []),
                  ),
                ),
              ),
              if (!small) Text('${_day(now.weekday)} ${now.day}', style: _t(13, weight: FontWeight.w500)),
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
            Text(_day(now.weekday), style: _t(13, weight: FontWeight.w500)),
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
                _c(_when(e)),
                style: _t(12, color: _soft, weight: FontWeight.w400),
              ),
            ],
          ),
        );
        final none = Text(
          _c('no events'),
          style: _t(14, color: _soft, weight: FontWeight.w400),
        );
        if (!wide) {
          return pad(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [date, _grow(), if (events.isEmpty) none else label(events.first['title'] as String)],
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
        // Over album art the words are white (on its dark fade) in either language.
        if (art != null || !_classic) _white = Colors.white;
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (wide)
              IconButton(
                tooltip: 'Previous',
                onPressed: Apps.instance.mediaPrev,
                icon: Icon(Icons.skip_previous_rounded, color: _white),
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
                icon: Icon(Icons.skip_next_rounded, color: _white),
              ),
          ],
        );
        // Passthrough: fills its tile, or (hugging) takes the words' height.
        return Stack(
          fit: StackFit.passthrough,
          children: [
            if (art != null) Positioned.fill(child: Image.memory(art, fit: BoxFit.cover, gaplessPlayback: true)),
            if (art != null || !_classic)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x26000000), Color(0xCC000000)]),
                  ),
                ),
              ),
            Padding(
              padding: _classic ? const EdgeInsets.fromLTRB(18, 14, 8, 8) : const EdgeInsets.fromLTRB(12, 10, 4, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Classic, no album art: the card says what it is, like the other widgets.
                  if (art == null && _classic) Icon(Icons.music_note_rounded, color: _white, size: 24),
                  _grow(),
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
                      style: _t(12, color: _soft, weight: FontWeight.w400),
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
                    'new',
                    style: _t(13, color: _soft, weight: FontWeight.w400),
                  ),
                ],
              ),
              _grow(),
              if (apps.isEmpty)
                Text(_c('all caught up'), style: _t(13, weight: FontWeight.w500))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (app, n) in apps.take(wide ? 6 : 3))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _glyph(app, 22),
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
        return iconTile(Icons.alarm_rounded, a == null ? 'off' : _hm(a.$1), a == null ? 'no alarm' : (a.$1.day == now.day ? 'today' : _day(a.$1.weekday)));
      case 'screentime':
        if (_usage['granted'] == false) return iconTile(Icons.lock_open_rounded, 'screen time', 'tap to allow');
        final total = (_usage['total'] as num?)?.toInt() ?? 0;
        final top = [for (final m in (_usage['top'] as List? ?? const [])) m as Map];
        return pad(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hourglass_bottom_rounded, color: _white, size: 22),
              _grow(),
              Text(_dur(total), style: _t(wide ? 30 : 24)),
              Text(
                _c('today'),
                style: _t(12, color: _soft, weight: FontWeight.w400),
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
                                _glyph(app, 20),
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
                  Icon(Icons.sticky_note_2_outlined, color: _white, size: 22),
                  const Spacer(),
                  Text(open.isEmpty ? '' : '${open.length}', style: _t(20)),
                ],
              ),
              _grow(),
              if (notes.isEmpty)
                Text(
                  _c('tap to add a note'),
                  style: _t(14, color: _soft, weight: FontWeight.w400),
                ),
              for (final n in notes.take(big ? 7 : (wide ? 2 : 1)))
                Text(
                  '${n['done'] == true ? '✓ ' : '· '}${n['t']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(14, weight: FontWeight.w400, color: n['done'] == true ? _faint : _white),
                ),
            ],
          ),
        );
      case 'remote':
        return iconTile(
          Icons.settings_remote_rounded,
          small
              ? (_classic ? 'TV' : 'tv')
              : (prefs.tvHost == null ? (_classic ? 'TV remote' : 'tv remote') : (_classic ? prefs.tvName : prefs.tvName.toLowerCase())),
          'remote',
        );
      case 'day':
        final radius = _classic ? DS.rMedia : prefs.tileRadius;
        return Padding(
          padding: _classic ? const EdgeInsets.fromLTRB(20, 16, 20, 12) : const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: big
              ? DayLine(prefs: prefs, legend: true, radius: radius, ink: _white)
              : Center(
                  child: DayLine(prefs: prefs, radius: radius, ink: _white),
                ),
        );
      case 'stream':
        final items = _watching;
        if (items.isEmpty) return iconTile(Icons.movie_outlined, 'nothing to continue', null);
        if (big) {
          // Large: up to three, each a row (poster with its progress, title, what's left).
          return pad(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label(_c('continue watching')),
                const SizedBox(height: DS.s8),
                for (final t in items.take(3))
                  _flex(
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _editing ? null : () => OneStream.instance.open(t.link),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            _streamThumb(t, 44, 64),
                            const SizedBox(width: DS.s12),
                            Expanded(child: _streamWords(t, 15)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
        // Wide: the latest one over its backdrop, words on a dark fade, its progress along the bottom.
        final t = items.first;
        _white = Colors.white;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(child: OneStreamArt(title: t, backdrop: true, radius: 0)),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x26000000), Color(0xCC000000)]),
                ),
              ),
            ),
            Padding(
              padding: inset,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.play_circle_outline_rounded, color: _white, size: 24),
                  _grow(),
                  _streamWords(t, 18),
                  if (t.hasProgress) ...[const SizedBox(height: 6), _streamBar(t.progress)],
                ],
              ),
            ),
          ],
        );
      case 'actions':
        final labels = prefs.quickLabels;
        final ids = prefs.quickChips.where((id) => builtInActions.containsKey(id) || labels.containsKey(id)).take(big ? 8 : 4).toList();
        return Padding(
          padding: EdgeInsets.all(_classic ? 12 : 8),
          child: GridView.count(
            shrinkWrap: _hug,
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
                        DS.cased(builtInActions[id]?.$1 ?? labels[id]!.split('|').first),
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

  // ---- One Stream (Continue watching) ----

  /// How far in: a thin bar, the language's accent on a faint track.
  Widget _streamBar(double p, {Color? ink}) => ClipRRect(
    borderRadius: BorderRadius.circular(_classic ? 2 : 0),
    child: SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: (ink ?? _white).withValues(alpha: .25)),
          FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: p.clamp(0, 1).toDouble(), child: ColoredBox(color: ink ?? _white)),
        ],
      ),
    ),
  );

  /// A title's poster with its progress along the bottom.
  Widget _streamThumb(OneStreamTitle t, double w, double h) => SizedBox(
    width: w,
    height: h,
    child: Stack(
      fit: StackFit.expand,
      children: [
        OneStreamArt(title: t, radius: _classic ? 10 : prefs.tileRadius * .5),
        if (t.hasProgress)
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: _streamBar(t.progress, ink: Colors.white), // over the picture
          ),
      ],
    ),
  );

  /// "S2 · E4 · 12 min left" (what One Stream says, and what's left), else the year.
  static String _streamSub(OneStreamTitle t) {
    final s = [?t.subtitle, ?t.left].join(' · ');
    return s.isEmpty ? t.caption : s;
  }

  Widget _streamWords(OneStreamTitle t, double size) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(size, weight: FontWeight.w500)),
      Text(
        _streamSub(t),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _t(12, color: _soft, weight: FontWeight.w400),
      ),
    ],
  );

  // ---- list rows (list layout) ----

  Widget _square(Widget child, {double size = 44}) => _classic
      // Classic: the accent disc of Settings rows.
      ? Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: DS.hero, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: child,
        )
      : Container(width: size, height: size, decoration: listSquare(prefs, tileAccent(), prefs.tileRadius * .5), alignment: Alignment.center, child: child);

  /// An app at the start of a row: Metro, its glyph on an accent square; Classic, its icon.
  Widget _appLead(AppEntry app) => _classic ? AppIcon(app, size: 40) : _square(TileGlyph(app: app, size: 28));

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
                Text(
                  _c(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _classic ? DS.rowTitle.copyWith(fontWeight: FontWeight.w500) : _t(18),
                ),
                if (sub != null && sub.isNotEmpty)
                  Text(
                    _c(sub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _classic ? DS.rowSub.copyWith(fontSize: 13) : _t(13, color: _white.withValues(alpha: .6), weight: FontWeight.w400),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );

  Widget _icon(IconData i) => _square(Icon(i, color: _classic ? DS.heroInk : _white, size: _classic ? 21 : 22));

  List<Widget> _rows(TileSpec t) {
    final now = DateTime.now();
    _white = _classic ? DS.ink : Colors.white; // Classic list: rows on the theme's cards
    switch (todayKind(t)) {
      case 'glance':
        return [
          _row(
            lead: _icon(Icons.today_rounded),
            title: '${_day(now.weekday)}, ${now.day} ${_month(now.month)}',
            sub: [
              if (_eventList.firstOrNull case final e?) '${e['title']} · ${_when(e)}',
              if (_alarm != null) '${_classic ? 'Alarm' : 'alarm'} ${_hm(_alarm!.$1)}',
            ].join('  ·  '),
            onTap: _action(t),
          ),
        ];
      case 'clock':
        return [_row(lead: _icon(Icons.schedule_rounded), title: _hm(now), sub: _day(now.weekday), onTap: _openClock)];
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
              borderRadius: BorderRadius.circular(_classic ? 12 : prefs.tileRadius * .5),
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
                  icon: Icon(Icons.skip_previous_rounded, color: _white),
                ),
                IconButton(
                  tooltip: playing ? 'Pause' : 'Play',
                  onPressed: Apps.instance.mediaPlayPause,
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: _white, size: 30),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: Apps.instance.mediaNext,
                  icon: Icon(Icons.skip_next_rounded, color: _white),
                ),
              ],
            ),
          ),
        ];
      case 'notifications':
        final rows = [
          for (final e in Apps.instance.notifCounts.value.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            if (_app(e.key) case final app?) _row(lead: _appLead(app), title: app.label, sub: '${e.value} new', onTap: () => widget.onLaunch(app)),
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
              _row(lead: _appLead(app), title: app.label, sub: _dur((m['ms'] as num).toInt()), onTap: () => widget.onLaunch(app)),
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
            title: prefs.tvHost == null ? (_classic ? 'Set up a TV' : 'set up a tv') : prefs.tvName,
            sub: _classic ? 'TV remote' : 'tv remote',
            onTap: () => showTvRemote(context, prefs: prefs),
          ),
        ];
      case 'day':
        return [
          GestureDetector(
            onTap: _editing ? null : () => showDaySlots(context, prefs: prefs),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: DayLine(prefs: prefs, legend: t.size == 'l', radius: _classic ? DS.rMedia : prefs.tileRadius, ink: _white),
            ),
          ),
        ];
      case 'stream':
        if (_watching.isEmpty) return [_row(lead: _icon(Icons.movie_outlined), title: 'nothing to continue')];
        return [
          for (final s in _watching.take(t.size == 'l' ? 6 : 3))
            _row(
              lead: _streamThumb(s, 40, 56),
              title: s.title,
              sub: _streamSub(s),
              onTap: () => OneStream.instance.open(s.link),
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
            // Metro: outlined boxes, the accent when chosen. Classic: ink pills.
            child: Material(
              color: on ? (_classic ? DS.ink : DS.hero) : Colors.transparent,
              shape: _classic
                  ? StadiumBorder(side: BorderSide(color: on ? DS.ink : DS.hairline))
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DS.rMedia),
                      side: BorderSide(color: on ? DS.hero : DS.inkFaint, width: 1.5),
                    ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: 10),
                  child: Text(
                    DS.cased(text),
                    style: DS.rowTitle.copyWith(
                      fontSize: 14,
                      fontWeight: _classic ? FontWeight.w500 : null,
                      color: on ? (_classic ? DS.card : Colors.white) : DS.ink,
                    ),
                  ),
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
                    style: DS.rowTitle.copyWith(
                      fontWeight: _classic ? FontWeight.w500 : FontWeight.w400,
                      fontSize: _classic ? 16 : 18,
                      color: tap == null ? DS.inkFaint : (danger ? DS.alert : DS.ink),
                    ),
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
                // Height: this widget's own, or the panel's Card height setting.
                if (kind != 'aw') ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s24, DS.s8),
                    child: Text(DS.cased('Height'), style: DS.eyebrow),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                    child: Wrap(
                      children: [
                        box('Like the rest (${prefs.todayHug ? 'hug' : 'fixed'})', now.height == null, () => update(now.withHeight(null))),
                        box('Fixed', now.height == 'fixed', () => update(now.withHeight('fixed'))),
                        box('Hug content', now.height == 'hug', () => update(now.withHeight('hug'))),
                      ],
                    ),
                  ),
                ],
                // Colour is a tile thing: Classic cards follow the theme (the first one is the hero).
                if (!_classic)
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
          if (!have.contains('today:$kind') && (kind != 'stream' || OneStream.instance.available.value))
            SheetAction(icon, name, () {
              Navigator.pop(context);
              HapticFeedback.mediumImpact();
              _save([..._tiles, TileSpec('today:$kind', size)]).then((_) => kind == 'stream' ? _load() : null);
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
    // Over the wallpaper. Metro: flat boxes, the accent when chosen. Classic: frosted pills
    // like the quick chips, a card-coloured pill when chosen.
    Widget box(String text, bool on, VoidCallback tap) => Padding(
      padding: const EdgeInsets.only(right: DS.s8, bottom: DS.s8),
      child: Material(
        color: _classic ? (on ? DS.card : DS.chipOnWallpaper) : (on ? tileAccent() : Colors.white.withValues(alpha: .1)),
        shape: _classic
            ? StadiumBorder(side: BorderSide(color: on ? Colors.transparent : DS.glassLine))
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(prefs.tileRadius * .5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            tap();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _classic ? 16 : 14, vertical: 10),
            child: Text(
              _c(text),
              style: _classic
                  ? DS.rowTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: on ? DS.ink : DS.onWallpaper)
                  : _t(15, weight: FontWeight.w400),
            ),
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
              // Classic: the theme's plain canvas rather than black.
              box(_classic ? 'plain' : 'black', prefs.todayBg == 'black', () => prefs.setTodayLook(bg: 'black')),
            ],
          ),
          Wrap(children: [box(_classic ? 'add widget' : '+ add widget', false, _add), box('reset', false, () async {
                if (await confirmReset(context, title: 'Reset widgets?', body: 'Back to the starting widgets. Ones you added, sizes and order are lost.')) {
                  await prefs.setTodayTiles(null);
                }
              })]),
          Text(
            _classic ? 'Hold and drag to move · ⋯ for size and more' : 'hold and drag to move · ⋯ for size, colour and more',
            style: _t(12, color: _classic ? DS.onCanvasMuted : Colors.white54, weight: FontWeight.w400),
          ),
        ],
      ),
    );
  }

  Widget _tilesGrid(List<TileSpec> tiles) => LayoutBuilder(
    builder: (context, c) {
      final gap = _classic ? 8.0 : 6.0;
      const cols = 4;
      final unit = (c.maxWidth - (cols - 1) * gap) / cols;
      final placed = packTiles(tiles, cols: cols);
      if (tiles.any(_hugs)) return _hugGrid(placed, unit, gap);
      var rows = 0;
      for (final (t, _, r) in placed) {
        rows = rows < r + t.span.$2 ? r + t.span.$2 : rows;
      }
      return SizedBox(
        height: rows == 0 ? 0 : rows * unit + (rows - 1) * gap,
        child: Stack(
          children: [
            for (final (i, (t, col, row)) in placed.indexed)
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
                  style: _anim,
                  delay: Duration(milliseconds: 40 * col + 22 * row),
                  child: _Reorderable(
                    id: t.id,
                    editing: _editing,
                    onPickUp: _pickUp,
                    onDrop: _drop,
                    onMove: _moveTo,
                    ghost: _classic
                        ? _ClassicCard(
                            colour: _cardColour(i == 0),
                            radius: _radius(t),
                            child: t.id.startsWith('aw:') ? const SizedBox.expand() : _face(t, hero: i == 0),
                          )
                        : (t.id.startsWith('aw:') ? null : _face(t)),
                    child: _TodayTile(
                      tile: t,
                      prefs: prefs,
                      editing: _editing,
                      hero: i == 0,
                      radius: _radius(t),
                      onTap: _editing ? () => _options(t) : _action(t),
                      onMenu: () => _options(t),
                      child: _face(t, hero: i == 0),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  /// The grid, hugging: same places as the square grid, but each row only as tall as the
  /// tallest widget in it (app widgets keep their grid height).
  Widget _hugGrid(List<(TileSpec, int, int)> placed, double unit, double gap) => _HugGrid(
    unit: unit,
    gap: gap,
    children: [
      for (final (i, (t, col, row)) in placed.indexed)
        _HugCell(
          key: ValueKey(t.id),
          col: col,
          row: row,
          span: t.span,
          fixed: !_hugs(t),
          child: Landed(
            landing: todayLanding,
            style: _anim,
            delay: Duration(milliseconds: 40 * col + 22 * row),
            child: _Reorderable(
              id: t.id,
              editing: _editing,
              onPickUp: _pickUp,
              onDrop: _drop,
              onMove: _moveTo,
              ghost: _classic
                  ? _ClassicCard(
                      colour: _cardColour(i == 0),
                      radius: _radius(t),
                      child: t.id.startsWith('aw:') ? const SizedBox.expand() : _face(t, hero: i == 0),
                    )
                  : (t.id.startsWith('aw:') ? null : _face(t)),
              child: _TodayTile(
                tile: t,
                prefs: prefs,
                editing: _editing,
                hero: i == 0,
                radius: _radius(t),
                onTap: _editing ? () => _options(t) : _action(t),
                onMenu: () => _options(t),
                child: _face(t, hero: i == 0),
              ),
            ),
          ),
        ),
    ],
  );

  /// Classic list: each widget on its own card — a small-caps header, then its rows.
  Widget _classicList(List<TileSpec> tiles) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, t) in tiles.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: DS.s8),
          child: Landed(
            landing: todayLanding,
            style: _anim,
            delay: Duration(milliseconds: 50 * i),
            child: _Reorderable(
              id: t.id,
              editing: _editing,
              onPickUp: _pickUp,
              onDrop: _drop,
              onMove: _moveTo,
              ghost: _ClassicCard(
                colour: DS.card,
                radius: DS.rCard,
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: DS.pad),
                  alignment: Alignment.centerLeft,
                  child: Text(_title(t), style: DS.rowTitle),
                ),
              ),
              child: _ClassicCard(
                colour: DS.card,
                radius: DS.rCard,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(DS.pad, DS.s12, DS.s12, DS.s12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 36,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _title(t).toUpperCase(),
                                style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (_editing)
                              IconButton(
                                tooltip: 'Widget options',
                                onPressed: () => _options(t),
                                icon: Icon(Icons.more_horiz_rounded, color: DS.ink),
                              ),
                          ],
                        ),
                      ),
                      ..._rows(t),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  /// Entrances: Metro uses the Start animation; Classic a gentle cascade.
  String get _anim => _classic ? 'cascade' : prefs.tileAnim;

  /// A Classic card's corners: the card radius; small ones a little less, so they stay square-ish.
  double _radius(TileSpec t) => _classic ? (t.size == 's' ? DS.rMedia : DS.rCard) : prefs.tileRadius;

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
                          icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
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

  /// Classic header: "Today" and the date over the wallpaper, with the edit button.
  Widget _classicHeader(DateTime now) => Padding(
    padding: const EdgeInsets.fromLTRB(DS.s16, 0, 0, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_day(now.weekday)}, ${now.day} ${_month(now.month)}', style: DS.wallpaperDate),
              const SizedBox(height: 2),
              const Text(
                'Today',
                style: TextStyle(fontFamily: DS.font, fontSize: 40, fontWeight: FontWeight.w500, height: 1.1, letterSpacing: -1, color: DS.onWallpaper),
              ),
            ],
          ),
        ),
        _editing
            ? FilledButton(
                style: FilledButton.styleFrom(backgroundColor: DS.card, foregroundColor: DS.ink, shape: const StadiumBorder()),
                onPressed: () => setState(() => _editing = false),
                child: const Text(
                  'Done',
                  style: TextStyle(fontFamily: DS.font, fontWeight: FontWeight.w600),
                ),
              )
            : CircleButton(
                icon: Icons.edit_outlined,
                tone: CircleTone.glass,
                tooltip: 'Edit today',
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _editing = true);
                },
              ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final now = DateTime.now();
    return ListenableBuilder(
      listenable: Listenable.merge([prefs, Apps.instance.media, Apps.instance.notifCounts]),
      builder: (context, _) {
        final tiles = _tiles;
        _white = Colors.white; // the header and edit bar sit on the wallpaper
        todayEditing.value = _editing;
        return PopScope(
          canPop: !_editing,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _editing) setState(() => _editing = false);
          },
          child: ColoredBox(
            color: prefs.todayBg == 'black' ? (_classic ? DS.canvas : Colors.black) : Colors.transparent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(), // pull down to search even when it fits
              padding: _classic
                  ? EdgeInsets.fromLTRB(DS.gutter, pad.top + DS.s16, DS.gutter, pad.bottom + DS.s32)
                  : EdgeInsets.fromLTRB(12, pad.top + DS.s24, 12, pad.bottom + DS.s32),
              children: [
                if (_classic)
                  _classicHeader(now)
                else
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
                                  foregroundColor: Colors.white,
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
                                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                              ),
                      ],
                    ),
                  ),
                if (_editing && !_dragging)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: _classic ? DS.s16 : 4),
                    child: _editBar(),
                  ),
                SizedBox(height: _classic ? DS.s16 : DS.s20),
                if (tiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(DS.s16),
                    child: Text(
                      _classic ? 'Nothing here — tap ✎, then Add widget' : 'nothing here — tap ✎, then + add widget',
                      style: _t(16, color: Colors.white70),
                    ),
                  )
                else if (prefs.todayLayout == 'list')
                  _classic ? _classicList(tiles) : Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _list(tiles))
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
/// Classic: a rounded card in the theme's colours (the hero card first), glass when the Classic
/// home is glass, the usual gentle press.
class _TodayTile extends StatelessWidget {
  const _TodayTile({
    required this.tile,
    required this.prefs,
    required this.editing,
    required this.onTap,
    required this.onMenu,
    required this.child,
    this.hero = false,
    this.radius = 0,
  });
  final TileSpec tile;
  final Prefs prefs;
  final bool editing, hero;
  final double radius;
  final VoidCallback? onTap, onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DS.metro) {
      return AnimatedScale(
        duration: const Duration(milliseconds: 200),
        scale: editing ? .95 : 1,
        child: Stack(
          fit: StackFit.passthrough, // fills its cell; hugging, takes the face's height
          children: [
            Pressable(
              scale: .97,
              child: _ClassicCard(
                colour: hero ? DS.hero : DS.card,
                radius: radius,
                child: InkWell(onTap: onTap ?? () {}, child: child),
              ),
            ),
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
                      padding: const EdgeInsets.all(DS.s8),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(color: DS.ink, shape: BoxShape.circle),
                        child: Icon(Icons.more_horiz_rounded, size: 18, color: DS.card),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
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
        fit: StackFit.passthrough,
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

/// A Classic card: the theme's [colour] with [radius] corners — a frosted pane when the Classic
/// home is glass (Home view → Look → Glass).
class _ClassicCard extends StatelessWidget {
  const _ClassicCard({required this.colour, required this.radius, required this.child});
  final Color colour;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => glassOr(
    colour: colour,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    child: child,
  );
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

/// One widget's place in [_HugGrid]: its column / row and span from the packed grid.
class _HugCell extends ParentDataWidget<_HugData> {
  const _HugCell({super.key, required this.col, required this.row, required this.span, required this.fixed, required super.child});
  final int col, row;
  final (int, int) span;
  final bool fixed; // keeps its grid height (app widgets can't be measured)

  @override
  void applyParentData(RenderObject o) {
    final d = o.parentData! as _HugData;
    if (d.col == col && d.row == row && d.span == span && d.fixed == fixed) return;
    d
      ..col = col
      ..row = row
      ..span = span
      ..fixed = fixed;
    o.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _HugGrid;
}

class _HugData extends ContainerBoxParentData<RenderBox> {
  int col = 0, row = 0;
  (int, int) span = (1, 1);
  bool fixed = false;
}

/// The today grid with rows that hug: each widget is measured at its width, every row takes
/// the height of the tallest one-row widget in it, and taller widgets stretch the last of
/// their rows when they need more. Then every widget fills its rows, so edges still line up.
class _HugGrid extends MultiChildRenderObjectWidget {
  const _HugGrid({required this.unit, required this.gap, required super.children});
  final double unit, gap;

  @override
  _RenderHugGrid createRenderObject(BuildContext context) => _RenderHugGrid(unit, gap);

  @override
  void updateRenderObject(BuildContext context, _RenderHugGrid o) => o
    ..unit = unit
    ..gap = gap;
}

class _RenderHugGrid extends RenderBox with ContainerRenderObjectMixin<RenderBox, _HugData>, RenderBoxContainerDefaultsMixin<RenderBox, _HugData> {
  _RenderHugGrid(this._unit, this._gap);
  double _unit, _gap;
  set unit(double v) {
    if (v == _unit) return;
    _unit = v;
    markNeedsLayout();
  }

  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HugData) child.parentData = _HugData();
  }

  double _span(int n) => n * _unit + (n - 1) * _gap;

  @override
  void performLayout() {
    final kids = <(RenderBox, _HugData, double)>[];
    var rows = 0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final d = c.parentData! as _HugData;
      final w = _span(d.span.$1);
      double h;
      if (d.fixed) {
        h = _span(d.span.$2);
      } else {
        c.layout(BoxConstraints(minWidth: w, maxWidth: w), parentUsesSize: true);
        h = c.size.height;
      }
      kids.add((c, d, h));
      rows = math.max(rows, d.row + d.span.$2);
    }
    final rh = List<double>.filled(rows, 0);
    for (final (_, d, h) in kids) {
      if (d.span.$2 == 1) rh[d.row] = math.max(rh[d.row], h);
    }
    for (final (_, d, h) in kids.where((k) => k.$2.span.$2 > 1)) {
      final need = h - (d.span.$2 - 1) * _gap;
      var have = 0.0;
      for (var r = d.row; r < d.row + d.span.$2; r++) {
        have += rh[r];
      }
      if (have < need) rh[d.row + d.span.$2 - 1] += need - have;
    }
    final top = List<double>.filled(rows + 1, 0);
    for (var r = 0; r < rows; r++) {
      top[r + 1] = top[r] + rh[r] + _gap;
    }
    for (final (c, d, _) in kids) {
      final h = top[d.row + d.span.$2] - top[d.row] - _gap;
      c.layout(BoxConstraints.tight(Size(_span(d.span.$1), h)));
      d.offset = Offset(d.col * (_unit + _gap), top[d.row]);
    }
    size = constraints.constrain(Size(constraints.maxWidth, rows == 0 ? 0 : top[rows] - _gap));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
