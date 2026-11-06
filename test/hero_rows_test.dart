import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/ui/ds.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pkgs = ['a.one', 'b.two', 'c.three', 'd.four', 'e.five', 'f.six', 'g.seven', 'h.eight', 'i.nine', 'j.ten', 'k.eleven', 'l.twelve', 'm.thirteen', 'n.fourteen'];

/// Classic: the pinned & most used card's rows (2–4 per page) and its optional neutral names.
Future<Prefs> _pump(WidgetTester tester, Map<String, Object> extra) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.88;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
    if (call.method == 'getApps') {
      return [for (final p in _pkgs) {'package': p, 'label': 'App ${p.split('.').last}', 'system': false, 'category': -1, 'installed': 0}];
    }
    return null;
  });
  SharedPreferences.setMockInitialValues({
    'launchCounts': jsonEncode({for (final (i, p) in _pkgs.indexed) p: 100 - i}),
    ...extra,
  });
  final prefs = await Prefs.load();
  await tester.pumpWidget(OneLauncher(prefs: prefs));
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  test('rows stay 2–4 and names start off', () async {
    SharedPreferences.setMockInitialValues({'heroRows': 9});
    final prefs = await Prefs.load();
    expect(prefs.heroRows, 4);
    expect(prefs.heroLabels, isFalse);
  });

  testWidgets('3 rows fit 12 apps on page 1; names show in plain black / white', (tester) async {
    await _pump(tester, {'heroRows': 3, 'heroLabels': true});
    final top = tester.getTopLeft(find.text('App one')).dy;
    // App twelve is in row 3 of the card; App thirteen is on page 2 (not built until swiped to).
    expect(tester.getTopLeft(find.text('App twelve')).dy, greaterThan(top + 100));
    expect(find.text('App thirteen'), findsNothing);
    final style = tester.widget<Text>(find.text('App one')).style!;
    expect(style.color, DS.hero.computeLuminance() > .4 ? Colors.black : Colors.white, reason: 'no tint: black on a light card, white on a dark one');
  });

  testWidgets('Customise changes rows and names', (tester) async {
    final prefs = await _pump(tester, {});
    expect(find.text('App one'), findsNothing, reason: 'icons only by default');
    await tester.tap(find.byTooltip('Customise pinned & most used'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show app names'));
    await tester.pumpAndSettle();
    expect(prefs.heroLabels, isTrue);
    expect(find.text('App one'), findsOneWidget);
    await tester.tap(find.byTooltip('Customise pinned & most used'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rows: 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 rows'));
    await tester.pumpAndSettle();
    expect(prefs.heroRows, 4);
  });

  testWidgets('leaving the launcher on page 2 brings it back on page 1', (tester) async {
    await _pump(tester, {'heroLabels': true});
    final pager = find.ancestor(of: find.text('App one'), matching: find.byType(PageView)).first;
    await tester.fling(pager, const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('App nine'), findsOneWidget, reason: 'on page 2 now');
    expect(find.text('App one'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('App one'), findsOneWidget, reason: 'back on page 1');
  });
}
