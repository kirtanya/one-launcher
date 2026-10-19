import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../prefs.dart';
import '../ui/ds.dart';
import '../widgets.dart';
import 'tiles_home.dart' show tileSwatches;

/// One stretch of the day the user marks (sleep, office…): minutes from midnight ([end] before
/// [start] = it runs past midnight) on the weekdays it repeats ([days], 1 = Monday … 7 = Sunday).
class DaySlot {
  const DaySlot(this.name, this.start, this.end, this.colour, [this.days = everyDay]);
  final String name;
  final int start, end;
  final Color colour;
  final Set<int> days;

  static const everyDay = {1, 2, 3, 4, 5, 6, 7};

  factory DaySlot.of(Map m) => DaySlot(
    m['n'] as String,
    (m['s'] as num).toInt(),
    (m['e'] as num).toInt(),
    Color((m['c'] as num).toInt()),
    m['d'] == null ? everyDay : {for (final d in m['d'] as List) (d as num).toInt()},
  );
  Map<String, Object> toMap() => {'n': name, 's': start, 'e': end, 'c': colour.toARGB32(), 'd': (days.toList()..sort())};

  int get length => (end - start) % 1440 == 0 ? 1440 : (end - start) % 1440;
  bool get wraps => start + length > 1440;

  /// Within the slot at [minute] of a day it started on (ignores the weekday).
  bool covers(int minute) => ((minute - start) % 1440) < length;
  int leftAt(int minute) => length - (minute - start) % 1440;
}

/// The week plan: which slots fall on a given day (their own start, plus the tail of
/// yesterday's that ran past midnight), what's on now, what's next.
class DayPlan {
  DayPlan(this.slots);
  final List<DaySlot> slots;

  factory DayPlan.of(Prefs prefs) => DayPlan([for (final m in prefs.daySlots) DaySlot.of(m)]);

  static int _prev(int weekday) => weekday == 1 ? 7 : weekday - 1;

  /// The day's coloured stretches, 0…1440: (slot, from, to).
  List<(DaySlot, int, int)> segments(int weekday) => [
    for (final s in slots)
      if (s.days.contains(weekday)) (s, s.start, math.min(1440, s.start + s.length)),
    for (final s in slots)
      if (s.wraps && s.days.contains(_prev(weekday))) (s, 0, s.start + s.length - 1440),
  ];

  /// The slot on now and the minutes left of it.
  (DaySlot, int)? current(DateTime now) {
    final m = now.hour * 60 + now.minute;
    for (final (s, from, to) in segments(now.weekday)) {
      if (m >= from && m < to) {
        return (s, from == 0 && s.wraps && s.start != 0 ? to - m : s.leftAt(m));
      }
    }
    return null;
  }

  /// The next slot to start within a day, and in how many minutes.
  (DaySlot, int)? next(DateTime now) {
    final m = now.hour * 60 + now.minute;
    (DaySlot, int)? best;
    for (final s in slots) {
      for (final (day, offset) in [(now.weekday, 0), (now.weekday % 7 + 1, 1440)]) {
        if (!s.days.contains(day)) continue;
        final inMin = s.start + offset - m;
        if (inMin > 0 && inMin <= 1440 && (best == null || inMin < best.$2)) best = (s, inMin);
      }
    }
    return best;
  }

  /// The slots set for [weekday] (starting that day), by start time.
  List<DaySlot> on(int weekday) => slots.where((s) => s.days.contains(weekday)).toList()..sort((a, b) => a.start.compareTo(b.start));
}

String hm(int minute) => '${(minute ~/ 60 % 24).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
String _dur(int min) => min >= 60 ? '${min ~/ 60} h${min % 60 == 0 ? '' : ' ${min % 60} min'}' : '$min min';
const _short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// "every day", "weekdays", "weekends", or "Mon, Wed, Fri".
String daysLabel(Set<int> days) {
  if (days.length == 7) return 'Every day';
  if (days.length == 5 && days.containsAll({1, 2, 3, 4, 5})) return 'Weekdays';
  if (days.length == 2 && days.containsAll({6, 7})) return 'Weekends';
  return (days.toList()..sort()).map((d) => _short[d - 1]).join(', ');
}

/// The day as one straight line, 00:00 → 24:00, with the user's slots on it: what's on now and
/// how much of it is left (big, up top), the line (slot names on it, the hours gone shaded, a
/// marker with the time at now), the hours under it. [legend]: also the day's slots and what's
/// left of the day. [weekday]: draw that day without a now (the week editor's preview).
class DayLine extends StatelessWidget {
  const DayLine({super.key, required this.prefs, this.legend = false, this.radius = 0, this.weekday, this.ink = Colors.white});
  final Prefs prefs;
  final bool legend;
  final double radius;
  final int? weekday;

  /// The words' and marker's colour: white on a tile (Metro) or a dark strip; the card's ink
  /// on a Classic card.
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final live = weekday == null || weekday == now.weekday;
    final day = weekday ?? now.weekday;
    final minute = now.hour * 60 + now.minute;
    final plan = DayPlan.of(prefs);
    final segs = plan.segments(day);
    final current = live ? plan.current(now) : null;
    final next = live && current == null ? plan.next(now) : null;
    final white = ink, soft = ink.withValues(alpha: .7), faint = ink.withValues(alpha: .6);
    // Metro: lowercase, light. Classic: names as typed, Sentence case, a touch heavier.
    final metro = DS.metro;
    String cs(String s) => metro ? s.toLowerCase() : (s.isEmpty ? s : s[0].toUpperCase() + s.substring(1));
    TextStyle t(double size, {FontWeight w = FontWeight.w300, Color? c}) =>
        TextStyle(fontFamily: DS.font, color: c ?? white, fontSize: size, fontWeight: metro || w.value >= 500 ? w : FontWeight.w400, height: 1.1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (weekday == null)
          // Now: the slot (in its colour) and how long is left — the thing to read at a glance.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (current != null) ...[
                Container(width: 12, height: 12, margin: const EdgeInsets.only(bottom: 6), color: current.$1.colour),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(current != null ? cs(current.$1.name) : cs('free time'), maxLines: 1, overflow: TextOverflow.ellipsis, style: t(24)),
                    if (next != null)
                      Text(
                        '${cs(next.$1.name)} at ${hm(next.$1.start)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t(13, c: soft, w: FontWeight.w400),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(current != null ? _dur(current.$2) : (next != null ? _dur(next.$2) : ''), style: t(24)),
                  Text(
                    current != null ? 'left' : (next != null ? 'until ${metro ? next.$1.name.toLowerCase() : next.$1.name}' : ''),
                    style: t(12, c: soft, w: FontWeight.w400),
                  ),
                ],
              ),
            ],
          ),
        SizedBox(height: weekday == null ? 12 : 4),
        LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            double x(int m) => w * m / 1440;
            return SizedBox(
              height: live ? 46 : 30,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The line, with the slots' names written on them where there's room.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: live ? 16 : 0,
                    height: 22,
                    child: CustomPaint(
                      painter: _LinePainter(segs: segs, minute: live ? minute : null, radius: radius, ink: ink),
                    ),
                  ),
                  for (final (s, from, to) in segs)
                    if (x(to) - x(from) > 44)
                      Positioned(
                        left: x(from) + 6,
                        width: x(to) - x(from) - 8,
                        top: (live ? 16 : 0) + 4,
                        child: Text(
                          metro ? s.name.toLowerCase() : s.name,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: t(
                            11,
                            w: FontWeight.w600,
                            c: Colors.white.withValues(alpha: live && to <= minute ? .55 : .95), // on the slot's colour
                          ),
                        ),
                      ),
                  // The time now, over the marker.
                  if (live)
                    Positioned(
                      left: (x(minute) - 20).clamp(0, math.max(0, w - 40)),
                      width: 40,
                      top: 0,
                      child: Text(
                        hm(minute),
                        textAlign: TextAlign.center,
                        style: t(11, w: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        // Hour marks, each under its spot on the line.
        LayoutBuilder(
          builder: (context, box) => SizedBox(
            height: 14,
            child: Stack(
              children: [
                for (final h in const [0, 6, 12, 18, 24])
                  Positioned(
                    left: (box.maxWidth * h / 24 - (h == 0 ? 0 : (h == 24 ? 16 : 8))).clamp(0, box.maxWidth),
                    child: Text(
                      h.toString().padLeft(2, '0'),
                      style: t(11, c: faint, w: FontWeight.w400),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (legend) ...[
          const SizedBox(height: 12),
          for (final s in plan.on(day))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(width: 10, height: 10, color: s.colour),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(metro ? s.name.toLowerCase() : s.name, style: t(15, w: FontWeight.w400)),
                  ),
                  Text(
                    '${hm(s.start)} – ${hm(s.end)}',
                    style: t(13, c: soft, w: FontWeight.w400),
                  ),
                ],
              ),
            ),
          if (live)
            Text(
              '${_dur(1440 - minute)} left today',
              style: t(13, c: faint, w: FontWeight.w400),
            ),
        ],
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.segs, required this.minute, required this.radius, this.ink = Colors.white});
  final Color ink;
  final List<(DaySlot, int, int)> segs;
  final int? minute; // null: a day other than today (no now)
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Offset.zero & size;
    double x(int m) => bar.width * m / 1440;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(bar, Radius.circular(math.min(radius * .3, bar.height / 2))));
    canvas.drawRect(bar, Paint()..color = ink.withValues(alpha: .14));
    for (final (s, from, to) in segs) {
      canvas.drawRect(Rect.fromLTRB(x(from), bar.top, x(to), bar.bottom), Paint()..color = s.colour);
    }
    final tick = Paint()..color = ink.withValues(alpha: .3);
    for (final h in [6, 12, 18]) {
      canvas.drawRect(Rect.fromLTWH(x(h * 60) - .5, bar.top, 1, bar.height), tick);
    }
    final m = minute;
    if (m != null) {
      // The hours gone, shaded: what's left of the day stands out.
      canvas.drawRect(Rect.fromLTRB(bar.left, bar.top, x(m), bar.bottom), Paint()..color = Colors.black.withValues(alpha: .45));
    }
    canvas.restore();
    if (m != null) {
      final nx = x(m);
      canvas.drawRect(Rect.fromLTWH(nx - 1.5, -4, 3, size.height + 8), Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.minute != minute || o.radius != radius || o.ink != ink || o.segs.length != segs.length || !identical(o.segs, segs);
}

// ---- the week editor ----

/// Your week: pick a day, see it on a line, its slots under it; add or edit slots (each repeats
/// on the days you choose — office on weekdays, something else at weekends).
Future<void> showDaySlots(BuildContext context, {required Prefs prefs}) {
  var day = DateTime.now().weekday;
  return showOneSheetWith(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => ListenableBuilder(
        listenable: prefs,
        builder: (ctx, _) {
          final plan = DayPlan.of(prefs);
          final today = DateTime.now().weekday;
          final slots = plan.on(day);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s16),
                child: SheetHeader(title: 'Your week', subtitle: 'Each slot repeats on the days you pick'),
              ),
              // The days: tap one to see and plan it.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s16),
                child: Row(
                  children: [
                    for (var d = 1; d <= 7; d++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _DayChip(
                            letter: _letters[d - 1],
                            selected: d == day,
                            today: d == today,
                            busy: plan.on(d).isNotEmpty,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              set(() => day = d);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // That day on the line (Metro: a dark strip so it reads like the tile; Classic: a
              // muted card, like the widget's card).
              Container(
                margin: const EdgeInsets.fromLTRB(DS.s16, DS.s16, DS.s16, DS.s8),
                padding: const EdgeInsets.fromLTRB(DS.s12, DS.s12, DS.s12, DS.s8),
                decoration: BoxDecoration(color: DS.metro ? const Color(0xFF1B1B1B) : DS.cardMuted, borderRadius: BorderRadius.circular(DS.rMedia)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DS.cased(
                        day == today ? 'Today · ${_short[day - 1]}' : ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][day - 1],
                      ),
                      style: TextStyle(fontFamily: DS.font, color: DS.metro ? const Color(0xB3FFFFFF) : DS.inkMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    DayLine(prefs: prefs, weekday: day, radius: DS.rMedia, ink: DS.metro ? Colors.white : DS.ink),
                  ],
                ),
              ),
              if (slots.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s24, DS.s8),
                  child: Text(DS.cased('Nothing planned — a free day'), style: DS.rowSub),
                ),
              for (final s in slots)
                InkWell(
                  onTap: () => _editSlot(ctx, prefs: prefs, slot: s, day: day),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(color: s.colour, borderRadius: BorderRadius.circular(DS.rMedia * .4)),
                        ),
                        const SizedBox(width: DS.s16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
                              Text(DS.cased(daysLabel(s.days)), style: DS.rowSub.copyWith(fontSize: 13)),
                            ],
                          ),
                        ),
                        Text('${hm(s.start)} – ${hm(s.end)}', style: DS.rowSub),
                        const SizedBox(width: DS.s8),
                        Icon(Icons.chevron_right_rounded, color: DS.inkFaint),
                      ],
                    ),
                  ),
                ),
              InkWell(
                onTap: () => _editSlot(ctx, prefs: prefs, day: day),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, color: DS.ink),
                      const SizedBox(width: DS.s16),
                      Text(DS.cased('Add a slot'), style: DS.rowTitle.copyWith(fontWeight: FontWeight.w400)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: DS.s8),
            ],
          );
        },
      ),
    ),
  );
}

/// A weekday in the week strip: the letter; filled when chosen, a dot under today, a line
/// under days that have slots.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.letter, required this.selected, required this.today, required this.busy, required this.onTap});
  final String letter;
  final bool selected, today, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? (DS.metro ? DS.hero : DS.ink) : DS.cardMuted,
    borderRadius: BorderRadius.circular(DS.metro ? DS.rMedia : 14),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(letter, style: DS.rowTitle.copyWith(color: selected ? (DS.metro ? Colors.white : DS.card) : DS.ink)),
            const SizedBox(height: 4),
            Container(
              width: today ? 5 : 14,
              height: today ? 5 : 2,
              decoration: BoxDecoration(
                color: (today || busy) ? (selected ? (DS.metro ? Colors.white : DS.card) : DS.inkMuted) : Colors.transparent,
                shape: today ? BoxShape.circle : BoxShape.rectangle,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Add (no [slot]; starts on [day]) or edit one slot: name, times, the days it repeats, colour.
Future<void> _editSlot(BuildContext context, {required Prefs prefs, DaySlot? slot, required int day}) {
  final old = slot;
  var start = old?.start ?? 18 * 60 + 30, end = old?.end ?? 19 * 60 + 30;
  var colour = old?.colour ?? tileSwatches[3];
  var days = {...?old?.days};
  if (days.isEmpty) days = {day};
  return showOneSheetWith(
    context,
    keyboard: true,
    builder: (ctx) => WithTextController(
      text: old?.name ?? '',
      builder: (ctx, name) => StatefulBuilder(
        builder: (ctx, set) {
          final accent = DS.metro ? DS.hero : DS.ink;
          final onAccent = DS.metro ? Colors.white : DS.card;
          Future<void> pick(bool isStart) async {
            final v = isStart ? start : end;
            final t = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay(hour: v ~/ 60, minute: v % 60),
            );
            if (t != null) set(() => isStart ? start = t.hour * 60 + t.minute : end = t.hour * 60 + t.minute);
          }

          Widget time(String label, int v, bool isStart) => Expanded(
            child: Material(
              color: DS.cardMuted,
              borderRadius: BorderRadius.circular(DS.rMedia),
              child: InkWell(
                onTap: () => pick(isStart),
                child: Padding(
                  padding: const EdgeInsets.all(DS.s12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DS.cased(label), style: DS.rowSub.copyWith(fontSize: 12)),
                      Text(hm(v), style: DS.rowTitle.copyWith(fontSize: 24, fontWeight: FontWeight.w400)),
                    ],
                  ),
                ),
              ),
            ),
          );
          Widget preset(String label, Set<int> value) {
            final on = days.length == value.length && days.containsAll(value);
            return Padding(
              padding: const EdgeInsets.only(right: DS.s8),
              child: Material(
                color: on ? accent : Colors.transparent,
                shape: DS.metro
                    ? RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DS.rMedia),
                        side: BorderSide(color: on ? accent : DS.inkFaint),
                      )
                    : StadiumBorder(side: BorderSide(color: on ? accent : DS.hairline)),
                child: InkWell(
                  onTap: () => set(() => days = {...value}),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text(
                      DS.cased(label),
                      style: DS.rowTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: on ? onAccent : DS.ink),
                    ),
                  ),
                ),
              ),
            );
          }

          final length = (end - start) % 1440 == 0 ? 1440 : (end - start) % 1440;
          void save() {
            final n = name.text.trim();
            if (n.isEmpty || days.isEmpty) return;
            HapticFeedback.selectionClick();
            final list = [for (final m in prefs.daySlots) DaySlot.of(m)];
            final next = DaySlot(n, start, end, colour, days);
            final i = old == null ? -1 : list.indexWhere((s) => s.name == old.name && s.start == old.start && s.end == old.end);
            i < 0 ? list.add(next) : list[i] = next;
            prefs.setDaySlots([for (final s in list) s.toMap()]);
            Navigator.pop(ctx);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s12),
                child: SheetHeader(title: old == null ? 'New slot' : 'Edit slot'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                child: TextField(
                  controller: name,
                  autofocus: old == null,
                  textCapitalization: TextCapitalization.sentences,
                  style: DS.rowTitle.copyWith(fontWeight: FontWeight.w400, fontSize: 18),
                  decoration: InputDecoration(hintText: DS.cased('Name (sleep, office, gym…)'), hintStyle: DS.rowSub),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, 0),
                child: Row(
                  children: [
                    time('Starts', start, true),
                    const SizedBox(width: DS.s12),
                    time('Ends', end, false),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, 6, DS.s24, 0),
                child: Text('${_dur(length)}${start + length > 1440 ? ' · ends the next day' : ''}', style: DS.rowSub.copyWith(fontSize: 13)),
              ),
              // Repeats: a preset, or pick the days.
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s20, DS.s24, DS.s8),
                child: Text(DS.cased('Repeats'), style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                child: Wrap(
                  runSpacing: DS.s8,
                  children: [
                    preset('Every day', DaySlot.everyDay),
                    preset('Weekdays', {1, 2, 3, 4, 5}),
                    preset('Weekends', {6, 7}),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s16, DS.s12, DS.s16, 0),
                child: Row(
                  children: [
                    for (var d = 1; d <= 7; d++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _DayChip(
                            letter: _letters[d - 1],
                            selected: days.contains(d),
                            today: false,
                            busy: false,
                            onTap: () => set(() => days.contains(d) ? days.remove(d) : days.add(d)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (days.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(DS.s24, 6, DS.s24, 0),
                  child: Text(DS.cased('Pick at least one day'), style: DS.rowSub.copyWith(color: DS.alert, fontSize: 13)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s20, DS.s24, 0),
                child: Wrap(
                  spacing: DS.s8,
                  runSpacing: DS.s8,
                  children: [
                    for (final c in tileSwatches)
                      GestureDetector(
                        onTap: () => set(() => colour = c),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(DS.rMedia * .4),
                            border: c.toARGB32() == colour.toARGB32() ? Border.all(color: DS.ink, width: 3) : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s16, DS.s16, DS.s16, DS.s8),
                child: Row(
                  children: [
                    if (old != null)
                      TextButton(
                        onPressed: () {
                          final list = [for (final m in prefs.daySlots) DaySlot.of(m)]
                            ..removeWhere((s) => s.name == old.name && s.start == old.start && s.end == old.end);
                          prefs.setDaySlots([for (final s in list) s.toMap()]);
                          Navigator.pop(ctx);
                        },
                        child: Text(DS.cased('Delete'), style: const TextStyle(color: DS.alert)),
                      ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: onAccent,
                        shape: DS.metro ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)) : const StadiumBorder(),
                      ),
                      onPressed: save, // checks the name and days itself
                      child: Text(DS.cased('Save')),
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
