
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/pixel/pixel_drawer.dart';
import 'package:one_launcher/pixel/pixel_folder.dart';
import 'package:one_launcher/pixel/pixel_home.dart';
import 'package:one_launcher/pixel/pixel_model.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _names = [
  'Slack',
  'Maps',
  'Camera',
  'Zoom',
  'Amazon',
  'Notes',
  'Phone',
  'Chrome',
  'Photos',
  'Clock',
  'Mail',
  'Music',
];

Future<Prefs> _setUp(
  WidgetTester tester, {
  Map<String, Object> initial = const {},
  List<MethodCall>? calls,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.88;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('one_launcher/apps'),
    (call) async {
      calls?.add(call);
      if (call.method == 'getApps') {
        return [
          for (final l in _names)
            {
              'package': 'com.${l.toLowerCase()}',
              'label': l,
              'system': false,
              'category': -1,
              'installed': 0,
            },
        ];
      }
      return null;
    },
  );
  SharedPreferences.setMockInitialValues({'homeView': 'pixel', ...initial});
  final prefs = await Prefs.load();
  await tester.pumpWidget(OneLauncher(prefs: prefs));
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  testWidgets(
    'seeds a layout: At a Glance + dock + search pill; tap launches',
    (tester) async {
      final calls = <MethodCall>[];
      final prefs = await _setUp(tester, calls: calls);
      expect(find.byType(PixelHome), findsOneWidget);
      final l = PixelLayout.of(prefs)!;
      expect(l.pages.first.any((s) => s.id == 'glance'), isTrue);
      expect(l.dock.whereType<String>().length, 5);
      expect(find.byKey(const Key('pixel-search')), findsOneWidget);
      await expectLater(
        find.byType(OneLauncher),
        matchesGoldenFile('shots/pixel_home.png'),
      );
      final first = l.pages.first
          .lastWhere((s) => s.id.startsWith('app:'))
          .id
          .substring(4);
      final label = _names.firstWhere((n) => 'com.${n.toLowerCase()}' == first);
      await tester.tap(find.text(label).hitTestable().first);
      await tester.pumpAndSettle();
      expect(
        calls.where(
          (c) =>
              c.method == 'launch' && (c.arguments as Map)['package'] == first,
        ),
        isNotEmpty,
      );
    },
  );

  testWidgets('drop an app on an app makes a folder; it opens and closes', (
    tester,
  ) async {
    final prefs = await _setUp(tester);
    final l = PixelLayout.of(prefs)!;
    final apps = l.pages.first.where((s) => s.id.startsWith('app:')).toList();
    expect(apps.length, greaterThanOrEqualTo(2));
    String label(PixelSlot s) =>
        _names.firstWhere((n) => 'com.${n.toLowerCase()}' == s.id.substring(4));
    final a = find.text(label(apps[0])).hitTestable().first,
        b = find.text(label(apps[1])).hitTestable().first;
    final from = tester.getCenter(a) - const Offset(0, 22); // the icon, not its label
    final target = tester.getCenter(b) - const Offset(0, 22);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, target, i / 8)!);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    final saved = PixelLayout.of(prefs)!;
    expect(saved.folders, hasLength(1));
    expect(saved.folders.values.first.apps.length, 2);
    final folderIcon = find.byType(PixelFolderIcon);
    expect(folderIcon, findsOneWidget);
    await tester.tap(folderIcon);
    await tester.pumpAndSettle();
    expect(find.byType(PixelFolderOpen), findsOneWidget);
    expect(find.text('Edit name'), findsOneWidget);
    await expectLater(
      find.byType(OneLauncher),
      matchesGoldenFile('shots/pixel_home_folder.png'),
    );
    await tester.tapAt(const Offset(10, 700));
    await tester.pumpAndSettle();
    expect(find.byType(PixelFolderOpen), findsNothing);
  });

  testWidgets('swipe up opens the drawer', (tester) async {
    await _setUp(tester);
    final before = tester.getTopLeft(find.byType(PixelDrawer)).dy;
    expect(before, greaterThan(500));
    await tester.fling(
      find.byKey(const Key('pixel-search')),
      const Offset(0, -500),
      1500,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(PixelDrawer)).dy, lessThan(1));
  });

  testWidgets('long-press on empty space shows the 3-item menu', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.longPressAt(const Offset(190, 500));
    await tester.pumpAndSettle();
    expect(find.text('Wallpaper & style'), findsOneWidget);
    expect(find.text('Widgets'), findsOneWidget);
    expect(find.text('Home settings'), findsOneWidget);
  });
}
