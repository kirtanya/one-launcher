import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/pixel/pixel_drawer.dart';
import 'package:one_launcher/pixel/pixel_popup.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  final loader = FontLoader('InstrumentSans');
  for (final w in [400, 500, 600]) {
    loader.addFont(Future.value(ByteData.view(File('assets/fonts/InstrumentSans-$w.ttf').readAsBytesSync().buffer)));
  }
  await loader.load();
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
  }
}

const _names = [
  'Zomato', 'WhatsApp', 'Maps', 'Gmail', 'Calendar', 'Camera', 'Chrome', 'Clock', 'Drive', 'Files', 'Instagram',
  'Messages', 'Photos', 'Settings', 'Slack', 'Spotify', 'Swiggy', 'Uber', 'YouTube', 'Paytm', 'PhonePe', 'Figma',
  'Calculator', 'Contacts', 'Docs', 'Meet', 'Netflix', 'Notes', 'Play Store', 'Sheets',
];

final _calls = <MethodCall>[];

void _mock(TestWidgetsFlutterBinding b) {
  _calls.clear();
  b.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
    _calls.add(call);
    switch (call.method) {
      case 'listShortcuts':
        return {
          'allowed': true,
          'shortcuts': [
            {'id': 's1', 'label': 'Compose', 'app': 'Gmail', 'package': 'com.gmail', 'work': false},
            {'id': 's2', 'label': 'Search mail', 'app': 'Gmail', 'package': 'com.gmail', 'work': false},
            {'id': 's3', 'label': 'Other', 'app': 'Maps', 'package': 'com.maps', 'work': false},
          ],
        };
      case 'listWidgetProviders':
        return [
          {'provider': 'com.gmail/.W', 'serial': 0, 'label': 'Inbox', 'app': 'Gmail', 'package': 'com.gmail'},
        ];
    }
    return null;
  });
}

List<AppEntry> _apps() => [
  for (final n in _names) AppEntry(package: 'com.${n.toLowerCase().replaceAll(' ', '')}', label: n, system: n == 'Settings'),
];

Future<Prefs> _prefs([Map<String, Object> init = const {}]) async {
  SharedPreferences.setMockInitialValues(init);
  return Prefs.load();
}

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(useMaterial3: true, fontFamily: 'InstrumentSans', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4), brightness: Brightness.dark)),
  home: Scaffold(body: child),
);

void main() {
  setUpAll(_loadFonts);

  Future<void> pumpDrawer(WidgetTester tester, Prefs prefs, {VoidCallback? onClose, VoidCallback? onDragStart, List<AppEntry>? apps}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    _mock(tester.binding);
    await tester.pumpWidget(_host(PixelDrawer(prefs: prefs, apps: apps ?? _apps(), onClose: onClose ?? () {}, onDragStart: onDragStart)));
    await tester.pumpAndSettle();
  }

  testWidgets('grid is A-Z with a suggestions row from recent launches', (tester) async {
    final prefs = await _prefs({'lastLaunch': '{"com.uber":5,"com.slack":4,"com.maps":3}'});
    await pumpDrawer(tester, prefs);
    expect(find.byKey(const ValueKey('suggestions')), findsOneWidget);
    expect(find.byKey(const ValueKey('sug:com.uber')), findsOneWidget);
    // Suggestions: most recent first (Uber, Slack, Maps).
    expect(tester.getTopLeft(find.byKey(const ValueKey('sug:com.uber'))).dx, lessThan(tester.getTopLeft(find.byKey(const ValueKey('sug:com.slack'))).dx));
    final calc = tester.getTopLeft(find.byKey(const ValueKey('app:com.calculator')));
    final calendar = tester.getTopLeft(find.byKey(const ValueKey('app:com.calendar')));
    final camera = tester.getTopLeft(find.byKey(const ValueKey('app:com.camera')));
    expect(calc.dx < calendar.dx && calendar.dx < camera.dx, isTrue, reason: 'Calculator, Calendar, Camera in one row, A-Z');
    await expectLater(find.byType(PixelDrawer), matchesGoldenFile('shots/pixel_drawer.png'));
  });

  testWidgets('search filters apps and offers web and Play rows; Enter launches the first', (tester) async {
    final prefs = await _prefs();
    await pumpDrawer(tester, prefs);
    await tester.enterText(find.byKey(const ValueKey('drawerSearch')), 'sl');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('result:com.slack')), findsOneWidget);
    expect(find.byKey(const ValueKey('result:com.maps')), findsNothing);
    expect(find.text('Search the web for “sl”'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('web')));
    expect(_calls.last.method, 'webSearch');
    await tester.tap(find.byKey(const ValueKey('play')));
    expect(_calls.last.method, 'playSearch');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(_calls.any((c) => c.method == 'launch' && (c.arguments as Map)['package'] == 'com.slack'), isTrue);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('tap launches and records', (tester) async {
    final prefs = await _prefs();
    await pumpDrawer(tester, prefs, apps: _apps());
    await tester.tap(find.byKey(const ValueKey('app:com.maps')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_calls.any((c) => c.method == 'launch' && (c.arguments as Map)['package'] == 'com.maps'), isTrue);
    expect(prefs.launchCounts['com.maps'], 1);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('letter scroller jumps the list', (tester) async {
    final prefs = await _prefs({'pixelSettings': '{"suggestions":false}'});
    final apps = [
      for (var i = 0; i < 60; i++) AppEntry(package: 'com.a$i', label: 'Alpha ${i.toString().padLeft(2, '0')}'),
      for (var i = 0; i < 20; i++) AppEntry(package: 'com.z$i', label: 'Zeta ${i.toString().padLeft(2, '0')}'),
    ];
    await pumpDrawer(tester, prefs, apps: apps);
    expect(find.byKey(const ValueKey('app:com.z0')), findsNothing);
    final box = tester.getRect(find.byKey(const ValueKey('scroller')));
    final g = await tester.startGesture(Offset(box.center.dx, box.bottom - 4));
    await tester.pump();
    await g.moveBy(const Offset(0, -30));
    await tester.pump();
    final bubble = find.byWidgetPredicate((w) => w is Text && w.data == 'Z' && w.style?.fontSize == 40);
    expect(bubble, findsOneWidget, reason: 'bubble shows the letter');
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app:com.z0')), findsOneWidget);
    expect(bubble, findsNothing);
  });

  testWidgets('pulling down at the top closes', (tester) async {
    final prefs = await _prefs();
    var closed = 0;
    await pumpDrawer(tester, prefs, onClose: () => closed++);
    await tester.drag(find.byKey(const ValueKey('app:com.calendar')), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('work tabs show only with work apps', (tester) async {
    final prefs = await _prefs();
    await pumpDrawer(tester, prefs);
    expect(find.text('Work'), findsNothing);
    await pumpDrawer(tester, prefs, apps: [..._apps(), const AppEntry(package: 'com.slack@10', label: 'Slack Work', work: true)]);
    expect(find.text('Work'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app:com.slack@10')), findsOneWidget);
    expect(find.byKey(const ValueKey('app:com.maps')), findsNothing);
  });

  testWidgets('long press starts a drag, shows the popup; moving closes it', (tester) async {
    final prefs = await _prefs();
    var started = 0;
    await pumpDrawer(tester, prefs, onDragStart: () => started++);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('app:com.gmail'))));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(started, 1);
    expect(find.text('App info'), findsOneWidget);
    expect(find.text('Compose'), findsOneWidget);
    await g.moveBy(const Offset(0, -40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('App info'), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('popup: shortcuts, App info, Widgets, closes on outside tap', (tester) async {
    final prefs = await _prefs();
    _mock(tester.binding);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(_host(Builder(builder: (c) {
      ctx = c;
      return const SizedBox.expand();
    })));
    final gmail = _apps().firstWhere((a) => a.package == 'com.gmail', orElse: () => const AppEntry(package: 'com.gmail', label: 'Gmail'));
    final h = showPixelAppPopup(ctx, prefs: prefs, app: gmail, anchor: const Rect.fromLTWH(150, 500, 56, 56), onHome: true, onRemove: () {});
    await tester.pumpAndSettle();
    expect(h.isOpen, isTrue);
    expect(find.text('Compose'), findsOneWidget);
    expect(find.text('Search mail'), findsOneWidget);
    expect(find.text('Other'), findsNothing, reason: 'only this app\'s shortcuts');
    expect(find.text('App info'), findsOneWidget);
    expect(find.text('Widgets'), findsOneWidget);
    expect(find.text('Uninstall'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/pixel_popup.png'));
    await tester.tap(find.text('App info'));
    await tester.pumpAndSettle();
    expect(_calls.any((c) => c.method == 'appInfo'), isTrue);
    expect(h.isOpen, isFalse);
    expect(find.text('Compose'), findsNothing);

    final h2 = showPixelAppPopup(ctx, prefs: prefs, app: gmail, anchor: const Rect.fromLTWH(150, 500, 56, 56));
    await tester.pumpAndSettle();
    expect(find.text('Compose'), findsOneWidget);
    await tester.tapAt(const Offset(10, 700));
    await tester.pumpAndSettle();
    expect(h2.isOpen, isFalse);
    expect(find.text('Compose'), findsNothing);
  });
}
