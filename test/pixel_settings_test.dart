import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/pixel/pixel_model.dart';
import 'package:one_launcher/pixel/pixel_settings.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<Prefs> open(WidgetTester tester, {Brightness b = Brightness.dark}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: b, scaffoldBackgroundColor: b == Brightness.dark ? const Color(0xFF1B1B1B) : const Color(0xFFFEF7FF)),
        home: Builder(
          builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showPixelHomeSettings(c, prefs: prefs), child: const Text('open')))),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return prefs;
  }

  Future<void> reveal(WidgetTester tester, Finder f) =>
      tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);

  testWidgets('home settings: options write PixelSettings; reset clears the layout', (tester) async {
    final prefs = await open(tester);
    expect(find.text('Home settings'), findsWidgets);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/pixel_settings.png'));

    await tester.tap(find.text('Notification dots'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).notifDots, isFalse);

    await reveal(tester, find.text('Home grid'));
    await tester.tap(find.text('Home grid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6 × 7'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).grid, '6x7');

    await reveal(tester, find.text('Icon shape'));
    await tester.tap(find.text('Icon shape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arch'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).iconShape, 'arch');

    await reveal(tester, find.text('Dock icons'));
    await tester.tap(find.text('Dock icons'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).dockCount, 7);

    await prefs.setPixelLayout({'pages': [[]], 'dock': [], 'folders': {}});
    await reveal(tester, find.text('Reset home layout'));
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

  testWidgets('apps list settings sub-page writes the drawer options (light theme)', (tester) async {
    final prefs = await open(tester, b: Brightness.light);
    await tester.tap(find.text('Apps list settings'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/pixel_settings_apps.png'));
    await tester.tap(find.text('Sort apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Most used'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).drawerSort, 'most');
    await tester.tap(find.text('Letter scroller'));
    await tester.pumpAndSettle();
    expect(PixelSettings.of(prefs).letterScroller, isFalse);
  });

  testWidgets('home settings: Home view switches to another view and leaves settings', (tester) async {
    final prefs = await open(tester);
    await reveal(tester, find.text('Home view'));
    await tester.tap(find.text('Home view'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiles'));
    await tester.pumpAndSettle();
    expect(prefs.homeView, 'tiles');
    expect(find.text('open'), findsOneWidget, reason: 'back on home');
  });
}
