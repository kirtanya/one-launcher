import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../prefs.dart';
import '../ui/ds.dart';
import '../widgets.dart';
import 'tiles_home.dart' show tileSwatches;

/// One stretch of the day the user marks (sleep, office…). Minutes from midnight; [end] before
/// [start] means it runs past midnight.
class DaySlot {
  const DaySlot(this.name, this.start, this.end, this.colour);
  final String name;
  final int start, end;
  final Color colour;

  factory DaySlot.of(Map m) => DaySlot(m['n'] as String, (m['s'] as num).toInt(), (m['e'] as num).toInt(), Color((m['c'] as num).toInt()));
  Map<String, Object> toMap() => {'n': name, 's': start, 'e': end, 'c': colour.toARGB32()};

  int get length => (end - start) % 1440 == 0 ? 1440 : (end - start) % 1440;
  bool covers(int minute) => ((minute - start) % 1440) < length;
  int leftAt(int minute) => length - (minute - start) % 1440;
}

String _hm(int minute) => '${(minute ~/ 60 % 24).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
String _dur(int min) => min >= 60 ? '${min ~/ 60} h${min % 60 == 0 ? '' : ' ${min % 60} min'}' : '$min min';

/// The day as one straight line, 00:00 → 24:00: the user's slots on it, the hours gone shaded,
/// and a marker at now — a glance at how much of the day (and of the current slot) is left.
class DayLine extends StatelessWidget {
  const DayLine({super.key, required this.prefs, this.legend = false, this.radius = 0});
  final Prefs prefs;
  final bool legend; // the large widget lists the slots under the line
  final double radius;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final minute = now.hour * 60 + now.minute;
    final slots = [for (final m in prefs.daySlots) DaySlot.of(m)];
    final current = slots.where((s) => s.covers(minute)).firstOrNull;
    // Nothing on now: the next slot to start.
    final next = current != null || slots.isEmpty
        ? null
        : (slots.toList()..sort((a, b) => ((a.start - minute) % 1440).compareTo((b.start - minute) % 1440))).first;
    const white = Colors.white;
    TextStyle t(double size, {FontWeight w = FontWeight.w300, Color c = white}) =>
        TextStyle(fontFamily: DS.font, color: c, fontSize: size, fontWeight: w, height: 1.15);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // What now: the slot and how long is left of it, or the free time until the next.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(current != null ? current.name.toLowerCase() : 'free time', maxLines: 1, overflow: TextOverflow.ellipsis, style: t(22)),
            ),
            Text(
              current != null
                  ? '${_dur(current.leftAt(minute))} left'
                  : (next != null ? '${next.name.toLowerCase()} in ${_dur((next.start - minute) % 1440)}' : ''),
              style: t(14, w: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 30,
          child: CustomPaint(
            painter: _LinePainter(slots: slots, minute: minute, radius: radius),
          ),
        ),
        const SizedBox(height: 4),
        // Hour marks under the line.
        Row(
          children: [
            for (final h in const [0, 6, 12, 18])
              Expanded(
                child: Text(
                  h.toString().padLeft(2, '0'),
                  style: t(11, c: Colors.white60, w: FontWeight.w400),
                ),
              ),
            Text(
              '24',
              style: t(11, c: Colors.white60, w: FontWeight.w400),
            ),
          ],
        ),
        if (legend) ...[
          const SizedBox(height: 10),
          for (final s in slots)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(width: 10, height: 10, color: s.colour),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.name.toLowerCase(), style: t(14, w: FontWeight.w400)),
                  ),
                  Text(
                    '${_hm(s.start)}–${_hm(s.end)}',
                    style: t(13, c: Colors.white70, w: FontWeight.w400),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.slots, required this.minute, required this.radius});
  final List<DaySlot> slots;
  final int minute;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Rect.fromLTWH(0, 8, size.width, size.height - 16);
    double x(int m) => bar.width * m / 1440;
    final r = Radius.circular(math.min(radius * .3, bar.height / 2));
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(bar, r));
    // The track, then each slot (split at midnight when it wraps).
    canvas.drawRect(bar, Paint()..color = Colors.white.withValues(alpha: .14));
    for (final s in slots) {
      final paint = Paint()..color = s.colour;
      if (s.start + s.length <= 1440) {
        canvas.drawRect(Rect.fromLTRB(x(s.start), bar.top, x(s.start + s.length), bar.bottom), paint);
      } else {
        canvas.drawRect(Rect.fromLTRB(x(s.start), bar.top, bar.right, bar.bottom), paint);
        canvas.drawRect(Rect.fromLTRB(bar.left, bar.top, x(s.start + s.length - 1440), bar.bottom), paint);
      }
    }
    // The hours gone: shaded, so what's left of the day stands out.
    canvas.drawRect(Rect.fromLTRB(bar.left, bar.top, x(minute), bar.bottom), Paint()..color = Colors.black.withValues(alpha: .45));
    // Hour ticks every 6 h.
    final tick = Paint()..color = Colors.white.withValues(alpha: .35);
    for (final h in [6, 12, 18]) {
      canvas.drawRect(Rect.fromLTWH(x(h * 60) - .5, bar.top, 1, bar.height), tick);
    }
    canvas.restore();
    // Now: a white marker standing out above and below the bar.
    final nx = x(minute);
    canvas.drawRect(Rect.fromLTWH(nx - 1.5, 0, 3, size.height), Paint()..color = Colors.white);
    canvas.drawPath(
      Path()
        ..moveTo(nx - 5, 0)
        ..lineTo(nx + 5, 0)
        ..lineTo(nx, 6)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.minute != minute || o.slots != slots || o.radius != radius;
}

/// Day line → its slots: add, edit (name, start, end, colour), delete.
Future<void> showDaySlots(BuildContext context, {required Prefs prefs}) => showOneSheetWith(
  context,
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) {
      final slots = prefs.daySlots;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
            child: SheetHeader(title: 'Your day', subtitle: 'Mark the parts of your day on the line'),
          ),
          for (final (i, m) in slots.indexed)
            InkWell(
              onTap: () => _editSlot(ctx, prefs: prefs, index: i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s24, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: Color((m['c'] as num).toInt()), borderRadius: BorderRadius.circular(DS.rMedia * .4)),
                    ),
                    const SizedBox(width: DS.s16),
                    Expanded(
                      child: Text(m['n'] as String, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w400)),
                    ),
                    Text('${_hm((m['s'] as num).toInt())} – ${_hm((m['e'] as num).toInt())}', style: DS.rowSub),
                    const SizedBox(width: DS.s8),
                    Icon(Icons.chevron_right_rounded, color: DS.inkFaint),
                  ],
                ),
              ),
            ),
          InkWell(
            onTap: () => _editSlot(ctx, prefs: prefs),
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
);

/// Add (no [index]) or edit one slot.
Future<void> _editSlot(BuildContext context, {required Prefs prefs, int? index}) {
  final slots = prefs.daySlots;
  final old = index == null ? null : DaySlot.of(slots[index]);
  var start = old?.start ?? 18 * 60 + 30, end = old?.end ?? 19 * 60 + 30;
  var colour = old?.colour ?? tileSwatches[3];
  return showOneSheetWith(
    context,
    keyboard: true,
    builder: (ctx) => WithTextController(
      text: old?.name ?? '',
      builder: (ctx, name) => StatefulBuilder(
        builder: (ctx, set) {
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
                      Text(_hm(v), style: DS.rowTitle.copyWith(fontSize: 22, fontWeight: FontWeight.w400)),
                    ],
                  ),
                ),
              ),
            ),
          );

          void save() {
            final n = name.text.trim();
            if (n.isEmpty) return;
            HapticFeedback.selectionClick();
            final next = [...prefs.daySlots];
            final slot = DaySlot(n, start, end, colour).toMap();
            index == null ? next.add(slot) : next[index] = slot;
            prefs.setDaySlots(next);
            Navigator.pop(ctx);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s12),
                child: SheetHeader(title: index == null ? 'New slot' : 'Edit slot'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s24),
                child: TextField(
                  controller: name,
                  autofocus: index == null,
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
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, 0),
                child: Wrap(
                  spacing: DS.s8,
                  runSpacing: DS.s8,
                  children: [
                    for (final c in tileSwatches)
                      GestureDetector(
                        onTap: () => set(() => colour = c),
                        child: Container(
                          width: 36,
                          height: 36,
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
                    if (index != null)
                      TextButton(
                        onPressed: () {
                          prefs.setDaySlots([...prefs.daySlots]..removeAt(index));
                          Navigator.pop(ctx);
                        },
                        child: Text(DS.cased('Delete'), style: const TextStyle(color: DS.alert)),
                      ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: DS.metro ? DS.hero : DS.ink,
                        foregroundColor: DS.metro ? Colors.white : DS.card,
                        shape: DS.metro ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)) : const StadiumBorder(),
                      ),
                      onPressed: save,
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
