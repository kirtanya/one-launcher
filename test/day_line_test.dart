import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/tiles/day_line.dart';

void main() {
  test('day slots: covers / time left, including a slot that runs past midnight', () {
    const office = DaySlot('Office', 9 * 60 + 30, 18 * 60 + 30, Colors.blue);
    const sleep = DaySlot('Sleep', 23 * 60, 7 * 60, Colors.indigo);
    expect(office.length, 9 * 60);
    expect(office.covers(10 * 60), isTrue);
    expect(office.covers(19 * 60), isFalse);
    expect(office.leftAt(17 * 60), 90, reason: '17:00 → 1 h 30 left');
    expect(sleep.length, 8 * 60);
    expect(sleep.covers(23 * 60 + 30), isTrue);
    expect(sleep.covers(3 * 60), isTrue, reason: 'after midnight');
    expect(sleep.covers(8 * 60), isFalse);
    expect(sleep.leftAt(1 * 60), 6 * 60, reason: '01:00 → 6 h left');
  });
}
