import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/pixel/pixel_model.dart';
import 'package:one_launcher/pixel/pixel_settings.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<Prefs> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showPixelHomeSettings(c, prefs: prefs), child: const Text('open')))),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('home settings: options write PixelSettings; reset clears the layout', (tester) async {
    final prefs = await open(tester);
    expect(find.text('Home settings'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/pixel_settings.png'));

    await tester.tap(find.text('6x7'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).grid, '6x7');

    await tester.scrollUntilVisible(find.bySemanticsLabel('arch'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.bySemanticsLabel('arch'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).iconShape, 'arch');

    await tester.scrollUntilVisible(find.byTooltip('More'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).dockCount, 6);

    await tester.scrollUntilVisible(find.text('Double-tap to sleep'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Double-tap to sleep'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).doubleTapSleep, isFalse);

    await tester.scrollUntilVisible(find.text('Most used'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Most used'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).drawerSort, 'most');

    await prefs.setPixelLayout({'pages': [[]], 'dock': [], 'folders': {}});
    await tester.scrollUntilVisible(find.text('Reset home layout'), 300, scrollable: find.byType(Scrollable).first);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/pixel_settings_more.png'));
    await tester.tap(find.text('Reset home layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(prefs.pixelLayout, isNotEmpty, reason: 'cancel keeps it');
    await tester.tap(find.text('Reset home layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(prefs.pixelLayout, isEmpty);
  });
}
