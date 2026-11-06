import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Classic: Settings → Bottom bar (nav bar or the earlier search bar) and Now page on/off.
Future<Prefs> _pump(WidgetTester tester, Map<String, Object> values) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.88;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
    if (call.method == 'getApps') return [{'package': 'a.one', 'label': 'App one', 'system': false, 'category': -1, 'installed': 0}];
    return null;
  });
  SharedPreferences.setMockInitialValues(values);
  final prefs = await Prefs.load();
  await tester.pumpWidget(OneLauncher(prefs: prefs));
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  testWidgets('nav bar by default, with the Now tab', (tester) async {
    await _pump(tester, {});
    expect(find.byTooltip('Home screen · hold for Settings'), findsOneWidget);
    expect(find.byTooltip("Now: what's playing"), findsOneWidget);
    expect(find.byTooltip('Launcher settings'), findsNothing);
  });

  testWidgets('Now page off: no Now tab', (tester) async {
    await _pump(tester, {'classicToday': false});
    expect(find.byTooltip('Home screen · hold for Settings'), findsOneWidget);
    expect(find.byTooltip("Now: what's playing"), findsNothing);
  });

  testWidgets('search bar: full pill with Smart home and settings on its right', (tester) async {
    final prefs = await _pump(tester, {'dockStyle': 'search'});
    expect(find.byTooltip('Home screen · hold for Settings'), findsNothing);
    expect(find.byTooltip('Smart home and TV remote'), findsOneWidget);
    expect(find.byTooltip('Launcher settings'), findsOneWidget);
    await prefs.setDockStyle('nav');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Home screen · hold for Settings'), findsOneWidget);
  });
}
