import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/ui/perf.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<Prefs> launch(WidgetTester tester, {required Map<String, Object> device, Map<String, Object> stored = const {}}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      switch (call.method) {
        case 'getApps':
          return [
            for (final n in ['WhatsApp', 'Slack', 'Paytm']) {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
          ];
        case 'deviceClass':
          return device;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await Prefs.load();
    await Perf.init(prefs);
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('budget phone (2 GB, low-RAM flag) → lighter effects on automatically; switch overrides', (tester) async {
    final prefs = await launch(tester, device: {'lowRam': true, 'ramGb': 2.0, 'cores': 4});
    expect(Perf.lite.value, isTrue, reason: 'auto mode on a budget phone');
    // No decorative layers: the landing animation and pop-ins are skipped.
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing, reason: 'no pop-ins');

    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lighter effects'));
    await tester.pumpAndSettle();
    expect(find.text('On for this phone (automatic)'), findsOneWidget);
    await tester.tap(find.text('Lighter effects'));
    await tester.pumpAndSettle();
    expect(prefs.effects, 'full');
    expect(Perf.lite.value, isFalse, reason: 'the user can turn it off');
    expect(find.text('Off · all animations'), findsOneWidget);
    expect(prefs.exportBackup(), isNot(contains('slowFrames')), reason: 'phone-specific');
  });

  testWidgets('fast phone → full effects unless chosen', (tester) async {
    final prefs = await launch(tester, device: {'lowRam': false, 'ramGb': 8.0, 'cores': 8}, stored: {'effects': 'auto', 'slowFrames': false});
    expect(Perf.lite.value, isFalse);
    await prefs.setEffects('lite');
    await tester.pumpAndSettle();
    expect(Perf.lite.value, isTrue, reason: 'chosen in Settings');
    await prefs.setEffects('auto');
    await tester.pumpAndSettle();
    expect(Perf.lite.value, isFalse);
  });

  testWidgets('a phone that dropped frames before starts light', (tester) async {
    await launch(tester, device: {'lowRam': false, 'ramGb': 8.0, 'cores': 8}, stored: {'slowFrames': true});
    expect(Perf.lite.value, isTrue);
  });
}
