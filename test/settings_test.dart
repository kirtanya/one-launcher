import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<Prefs> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Slack', 'Paytm']) {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('settings: pages slide inside one sheet; back returns; search finds any setting', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    final sheetTop = tester.getTopLeft(find.text('Settings')).dy;
    expect(find.byTooltip('Back'), findsNothing, reason: 'first page: no back arrow');

    await tester.tap(find.text('Colours & style'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Settings'), findsOneWidget, reason: 'the root page is still there under the new one mid-slide');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Basic colours'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Basic colours'), findsNothing);
    expect(tester.getTopLeft(find.text('Settings')).dy, closeTo(sheetTop, 1), reason: 'the sheet never moved');

    // Search settings.
    await tester.enterText(find.byType(TextField), 'brightness');
    await tester.pumpAndSettle();
    expect(find.text('No setting matches “brightness”'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'dim');
    await tester.pumpAndSettle();
    expect(find.text('Wallpaper'), findsOneWidget, reason: 'found by its keywords');
    expect(find.text('LOOK'), findsNothing, reason: 'results replace the groups');
    await tester.tap(find.text('Wallpaper'));
    await tester.pumpAndSettle();
    expect(find.text('Wallpaper dim'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/21_settings_page.png'));
  });

  testWidgets('TV remote: the dock button can be hidden from Settings', (tester) async {
    final prefs = await launch(tester);
    expect(find.byTooltip('TV remote'), findsOneWidget, reason: 'shown by default, between search and settings');
    final remote = tester.getCenter(find.byTooltip('TV remote')).dx;
    expect(remote, lessThan(tester.getCenter(find.byTooltip('Launcher settings')).dx));
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remote button'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remote button'));
    await tester.pumpAndSettle();
    expect(prefs.remoteButton, isFalse);
    expect(find.byTooltip('TV remote'), findsNothing, reason: 'hidden from the dock');
  });
}
