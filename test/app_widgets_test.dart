import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('add an app widget as a top page, then remove it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    final removed = <int>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      switch (call.method) {
        case 'getApps':
          return [
            {'package': 'com.google.android.calendar', 'label': 'Calendar', 'system': false, 'category': -1, 'installed': 0},
          ];
        case 'listWidgetProviders':
          return [
            {
              'provider': 'com.google.android.calendar/.Month',
              'serial': 0,
              'work': false,
              'package': 'com.google.android.calendar',
              'label': 'Month',
              'app': 'Calendar',
              'cols': 4,
              'rows': 2,
            },
            {
              'provider': 'com.google.android.calendar/.Schedule',
              'serial': 0,
              'work': false,
              'package': 'com.google.android.calendar',
              'label': 'Schedule',
              'app': 'Calendar',
              'cols': 2,
              'rows': 2,
            },
          ];
        case 'addWidget':
          return 7;
        case 'removeWidget':
          removed.add((call.arguments as Map)['id'] as int);
          return true;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();

    // Long-press the top → Top widgets → Add app widget → Calendar · Month.
    await tester.longPress(find.byType(FittedBox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add app widget'));
    await tester.pumpAndSettle();
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('4 × 2'), findsOneWidget);
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(prefs.topPages, contains('widget:7'));
    expect(find.text('Calendar · Month'), findsWidgets, reason: 'listed in Top widgets');

    // Close the sheet and swipe to the widget page (placeholder off-device).
    Navigator.of(tester.element(find.text('Top widgets'))).pop();
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) { // clock → screen time → now playing → widget
      await tester.fling(find.byType(PageView), const Offset(-250, 0), 1200);
      await tester.pumpAndSettle();
    }
    // Tests run as "Android", so the real widget view is used (it draws nothing off-device).
    final view = tester.widget<AndroidView>(find.byType(AndroidView));
    expect(view.viewType, 'one_launcher/appwidget');
    expect(view.creationParams, {'id': 7}, reason: 'shows widget 7 on its carousel page');

    // Remove it again (Settings → Top widgets).
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top widgets'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Calendar · Month'));
    await tester.pumpAndSettle();
    expect(prefs.topPages, isNot(contains('widget:7')));
    expect(removed, [7], reason: 'widget id freed');
  });
}
