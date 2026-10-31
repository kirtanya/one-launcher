import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/smart_home.dart';
import 'package:one_launcher/smart_home_sheet.dart';
import 'package:one_launcher/top/smart_home_page.dart';
import 'package:one_launcher/top/top_carousel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final home = SmartHome.instance;
  final calls = <MethodCall>[];

  Future<Prefs> boot(
    WidgetTester tester, [
    Map<String, Object> extra = const {},
  ]) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    addTearDown(home.reset);
    home.reset();
    calls.clear();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('one_launcher/apps'),
      (call) async {
        if (call.method == 'getApps') {
          return [
            {
              'package': 'com.slack',
              'label': 'Slack',
              'system': false,
              'category': -1,
              'installed': 0,
            },
          ];
        }
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('one_launcher/home'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    SharedPreferences.setMockInitialValues({
      'quickChips': ['b:home', 'b:timer'],
      ...extra,
    });
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    return prefs;
  }

  for (final view in ['classic', 'tiles']) {
    testWidgets('sheet: setup card when the SDK bridge is missing ($view)', (
      tester,
    ) async {
      await boot(tester, {'homeView': view});
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('one_launcher/home'),
        null,
      ); // no bridge
      showSmartHome(tester.element(find.byType(Scaffold).first));
      await tester.pumpAndSettle();
      expect(find.text('Control your lights, plugs and AC'), findsOneWidget);
      expect(find.text('Coming in the next update'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: 'Connect is disabled until the bridge exists',
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
      expect(home.value.status, SmartHomeStatus.unavailable);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(OneLauncher),
        matchesGoldenFile('shots/smart_home_setup_$view.png'),
      );
    });
  }

  testWidgets(
    'sheet: tapping a device flips it at once (and goes to the bridge); a failed command rolls back',
    (tester) async {
      await boot(tester);
      home.debugDemo(local: false);
      showSmartHome(tester.element(find.byType(Scaffold).first));
      await tester.pumpAndSettle();
      expect(find.text('Ceiling light'), findsOneWidget);
      expect(home.value.byId('p1')!.on, isFalse);
      await tester.tap(find.text('Lamp plug'));
      await tester.pump();
      expect(home.value.byId('p1')!.on, isTrue, reason: 'optimistic');
      await tester.pumpAndSettle();
      expect(calls.last.method, 'set');
      expect(calls.last.arguments, {'id': 'p1', 'trait': 'on', 'value': true});
      await expectLater(
        find.byType(OneLauncher),
        matchesGoldenFile('shots/smart_home_sheet.png'),
      );

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('one_launcher/home'),
        (call) async =>
            throw PlatformException(code: 'x', message: 'Offline hub'),
      );
      await tester.tap(find.text('Lamp plug'));
      await tester.pumpAndSettle();
      expect(home.value.byId('p1')!.on, isTrue, reason: 'rolled back to on');
      expect(home.value.error, 'Offline hub');
    },
  );

  testWidgets('sheet: light detail page — colour, warmth, effects, room all off', (tester) async {
    await boot(tester);
    home.debugDemo(local: false);
    showSmartHome(tester.element(find.byType(Scaffold).first));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All off').first); // Living room: light + AC on
    await tester.pumpAndSettle();
    expect(home.value.inRoom('Living room').every((d) => !d.on), isTrue);
    await tester.tap(find.byTooltip('Details').first); // Ceiling light
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Warm white'));
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {'id': 'l1', 'trait': 'colorTempK', 'value': 2700});
    expect(home.value.byId('l1')!.colorMode, 'temp');
    expect(home.value.byId('l1')!.on, isTrue);
    await tester.tap(find.bySemanticsLabel('Colour').at(3)); // green
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {'id': 'l1', 'trait': 'color', 'value': {'h': 120.0, 's': 1}});
    await tester.dragUntilVisible(find.text('Fall asleep'), find.byType(Scrollable).last, const Offset(0, -200));
    await tester.tap(find.text('Fall asleep'));
    await tester.pumpAndSettle();
    expect(home.value.byId('l1')!.effect, 'sleep');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/smart_home_light.png'));
    await tester.tap(find.text('Fall asleep'));
    await tester.pumpAndSettle();
    expect(calls.last.arguments['value'], 'stop');
  });

  testWidgets('sheet: AC detail page — setpoint and mode', (tester) async {
    await boot(tester);
    home.debugDemo(local: false);
    showSmartHome(tester.element(find.byType(Scaffold).first));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Details').at(2)); // Living room AC
    await tester.pumpAndSettle();
    expect(find.text('24°'), findsWidgets);
    await tester.tap(find.byTooltip('Warmer'));
    await tester.pumpAndSettle();
    expect(home.value.byId('a1')!.setpoint, 25);
    expect(calls.last.arguments, {
      'id': 'a1',
      'trait': 'setpoint',
      'value': 25.0,
    });
    await tester.tap(find.text('Heat'));
    await tester.pumpAndSettle();
    expect(home.value.byId('a1')!.mode, AcMode.heat);
    await expectLater(
      find.byType(OneLauncher),
      matchesGoldenFile('shots/smart_home_ac.png'),
    );
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(home.value.byId('a1')!.on, isFalse);
  });

  testWidgets('quick chip b:home opens the sheet', (tester) async {
    await boot(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('one_launcher/home'),
      null,
    );
    await tester.tap(find.text('Smart home'));
    await tester.pumpAndSettle();
    expect(find.text('Control your lights, plugs and AC'), findsOneWidget);
  });

  testWidgets(
    'top page: pills toggle, All devices opens the sheet, setup form when not ready',
    (tester) async {
      await boot(tester, {
        'topOrder': ['clock', 'smart_home'],
        'topEnabled': ['clock', 'smart_home'],
        'blankAdded': true,
        'nowPlayingAdded': true,
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('one_launcher/home'),
        null,
      );
      for (var i = 0; i < 2; i++) {
        await tester.fling(
          find.descendant(
            of: find.byType(TopCarousel),
            matching: find.byType(PageView),
          ),
          const Offset(-300, 0),
          1500,
        );
        await tester.pumpAndSettle();
      }
      expect(find.byType(SmartHomePage), findsOneWidget);
      expect(find.text('Set up'), findsOneWidget);
      home.debugDemo(local: false);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('one_launcher/home'),
        (call) async {
          calls.add(call);
          return null;
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Ceiling light'), findsOneWidget);
      await tester.tap(find.text('Ceiling light'));
      await tester.pump();
      expect(home.value.byId('l1')!.on, isFalse);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(OneLauncher),
        matchesGoldenFile('shots/smart_home_top.png'),
      );
      await tester.tap(find.text('All devices'));
      await tester.pumpAndSettle();
      expect(find.byType(SmartHomeBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
