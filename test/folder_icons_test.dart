import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('folder icon = its first apps in a triangle (no number); opening shrinks them to the folder symbol', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Telegram', 'Signal', 'Discord', 'Slack', 'Zoom'])
            {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(OneLauncher(prefs: await Prefs.load()));
    await tester.pumpAndSettle();

    final social = find.ancestor(of: find.text('Social'), matching: find.byType(InkWell)).first;
    expect(find.descendant(of: social, matching: find.text('4')), findsNothing, reason: 'no app count');
    final trio = find.descendant(of: social, matching: find.byType(AppIcon));
    expect(trio, findsNWidgets(3), reason: 'three app icons');
    final sizes = [for (final e in trio.evaluate()) tester.getSize(find.byWidget(e.widget)).width];
    expect(sizes[0], greaterThan(sizes[1]));
    expect(sizes[1], greaterThan(sizes[2]), reason: 'each smaller than the one before');
    final tops = [for (final e in trio.evaluate()) tester.getTopLeft(find.byWidget(e.widget)).dy];
    expect(tops[1], greaterThan(tops[0]), reason: 'triangle: one on top, two below');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/23_folder_trio.png'));

    // Opening: the trio shrinks away to the folder's symbol (no flight); the grid shows the apps.
    await tester.tap(find.text('Social'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: social, matching: find.byType(AppIcon)), findsNothing, reason: 'trio gone while open');
    expect(find.descendant(of: social, matching: find.byIcon(Icons.chat_bubble_outline_rounded)), findsWidgets, reason: 'folder symbol shown');
    expect(find.text('Discord'), findsOneWidget, reason: 'apps in the grid');
    // Closing brings the trio back.
    await tester.tap(find.text('Social'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: social, matching: find.byType(AppIcon)), findsNWidgets(3));
  });
}
