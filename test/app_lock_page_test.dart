import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/app_lock_ui.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App lock page on a 375 pt phone: the five "Reopen without lock" choices fit, and the
/// screen-lock switch is there and on.
void main() {
  testWidgets('reopen times fit and the screen-lock switch shows', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async => null);
    SharedPreferences.setMockInitialValues({'lockGrace': 300});
    final prefs = await Prefs.load();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(child: TextButton(onPressed: () => showAppLockPage(c, prefs: prefs, apps: const [], height: 700), child: const Text('open'))),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final t in ['Off', '5 s', '10 s', '5 min', '10 min']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(tester.takeException(), isNull, reason: 'no overflow at 375 pt');
    final sw = tester.widget<SwitchListTile>(find.byKey(const ValueKey('lock-relock')));
    expect(sw.value, isTrue);
  });
}
