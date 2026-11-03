import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/smart_home.dart';
import 'package:one_launcher/smart_home_sheet.dart';
import 'package:one_launcher/top/smart_home_page.dart';
import 'package:one_launcher/top/top_carousel.dart';
import 'package:one_launcher/ui/ds.dart';
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
      expect(find.text('Ceiling light'), findsWidgets, reason: 'its tile, and its chip in the quick lights up top');
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
      expect(home.value.byId('p1')!.noReply, isTrue);
      expect(find.text('Not responding'), findsOneWidget, reason: 'its tile says so, controls stay on');
      expect(find.byIcon(Icons.error_outline_rounded), findsWidgets);

      // The next command goes through: back to normal.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('one_launcher/home'),
        (call) async => null,
      );
      await tester.tap(find.text('Lamp plug'));
      await tester.pumpAndSettle();
      expect(home.value.byId('p1')!.noReply, isFalse);
      expect(find.text('Not responding'), findsNothing);
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
    "top page: quick lights — a light's dot toggles it, All dims and colours every light",
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
      expect(find.text('Tap to connect Google Home'), findsOneWidget);
      home.debugDemo(local: false);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('one_launcher/home'),
        (call) async {
          calls.add(call);
          return null;
        },
      );
      await tester.pumpAndSettle();
      expect(find.text(DS.cased('Ceiling light')), findsOneWidget);
      expect(find.text('1 of 2 on'), findsOneWidget);
      await tester.ensureVisible(find.bySemanticsLabel('Bedside light on or off'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Bedside light on or off'));
      await tester.pump();
      expect(home.value.byId('l2')!.on, isTrue);
      await tester.pumpAndSettle();
      expect(calls.last.arguments, {'id': 'l2', 'trait': 'on', 'value': true});
      // All lights, warm white (the colour row swaps in for the chips): only the one that can take it.
      await tester.tap(find.byTooltip('Colour'));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Warm white'));
      await tester.pumpAndSettle();
      expect(calls.last.arguments, {'id': 'l1', 'trait': 'colorTempK', 'value': 2700});
      // Pick one light, then its power button.
      await tester.tap(find.byTooltip('Colour'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(DS.cased('Bedside light')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(DS.cased('Bedside light')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Power'));
      await tester.pumpAndSettle();
      expect(home.value.byId('l2')!.on, isFalse);
      expect(home.value.byId('l1')!.on, isTrue);
      await tester.dragUntilVisible(find.text(DS.cased('All')), find.byKey(const ValueKey('chips')), const Offset(300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(DS.cased('All')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(OneLauncher),
        matchesGoldenFile('shots/smart_home_top.png'),
      );
      await tester.tap(find.text('All lights'));
      await tester.pumpAndSettle();
      expect(find.byType(SmartHomeBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets("sheet: a room's lights as one — power, colour; homes pick which devices show", (tester) async {
    await boot(tester);
    home.debugDemo(local: false);
    showSmartHome(tester.element(find.byType(Scaffold).first));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.bySemanticsLabel('Bedroom controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Bedroom controls'));
    await tester.pumpAndSettle();
    expect(find.text('All lights off'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(home.value.byId('l2')!.on, isTrue);
    expect(home.value.byId('a2')!.on, isFalse, reason: 'only lights');
    expect(tester.takeException(), isNull);

    // Two homes: devices follow the one picked.
    home.state.value = home.value.copyWith(
      homes: [('h1', 'My home'), ('h2', "Sam's home")],
      homeId: 'h1',
      devices: [
        for (final d in home.value.all)
          SmartDevice(id: d.id, name: d.name, room: d.room, type: d.type, homeId: d.id == 'l2' ? 'h2' : 'h1'),
      ],
    );
    expect(home.value.devices.map((d) => d.id), isNot(contains('l2')));
    await home.chooseHome('h2');
    expect(home.value.devices.map((d) => d.id), ['l2']);
    expect((await SharedPreferences.getInstance()).getString('smartHome.home'), 'h2');
  });

  test('offline (Google says so) vs not responding (a command failed or timed out) read differently', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    home.reset();
    addTearDown(home.reset);
    home.debugDemo(local: false);
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('one_launcher/home'), (call) => Completer<void>().future); // never answers
    final off = SmartDevice.fromMap({'id': 'x', 'name': 'Lamp', 'type': 'light', 'online': false, 'reach': 'offline'});
    expect(smartSub(off), 'Offline');
    SmartHome.answerIn = const Duration(milliseconds: 20);
    addTearDown(() => SmartHome.answerIn = const Duration(seconds: 10));
    await home.set('l2', 'on', true);
    expect(home.value.byId('l2')!.on, isFalse, reason: 'rolled back');
    expect(home.value.byId('l2')!.noReply, isTrue);
    expect(smartSub(home.value.byId('l2')!), 'Not responding');
    expect(home.value.error, "Bedside light isn't responding");
    // Device updates keep the mark until a command goes through (or 3 minutes pass).
    m.handlePlatformMessage(
      'one_launcher/home',
      const StandardMethodCodec().encodeMethodCall(MethodCall('homeChanged', [
        {'id': 'l2', 'name': 'Bedside light', 'type': 'light', 'online': true, 'reach': 'unknown', 'on': false},
      ])),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(home.value.byId('l2')!.noReply, isTrue);
  });

  test('quick repeats: one command out at a time, only the newest waits; stale echoes stay hidden', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    home.reset();
    addTearDown(home.reset);
    home.debugDemo(local: false);
    final sent = <Object?>[];
    final gate = <Completer<void>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('one_launcher/home'),
      (call) async {
        sent.add((call.arguments as Map)['value']);
        final c = Completer<void>();
        gate.add(c);
        await c.future;
        return null;
      },
    );
    final a = home.set('l1', 'brightness', 10);
    await Future<void>.delayed(Duration.zero);
    final b = home.set('l1', 'brightness', 20);
    final c = home.set('l1', 'brightness', 30);
    expect(home.value.byId('l1')!.brightness, 30, reason: 'screen shows the newest at once');
    gate.first.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(sent, [10, 30], reason: '20 was replaced while 10 was out');
    gate.last.complete();
    await Future.wait([a, b, c]);
    // The device then reports its old level (the cloud lags): the screen keeps 30.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'one_launcher/home',
      const StandardMethodCodec().encodeMethodCall(MethodCall('homeChanged', [
        {'id': 'l1', 'name': 'Ceiling light', 'type': 'light', 'online': true, 'on': true, 'brightness': 70},
      ])),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(home.value.byId('l1')!.brightness, 30);
  });
}
