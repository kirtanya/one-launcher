import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadRoboto() async {
  // Real font so the snapshot shows readable text.
  final f = File('/System/Library/Fonts/Supplemental/Arial.ttf');
  if (!f.existsSync()) return;
  final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
  await loader.load();
}

void main() {
  testWidgets('home renders clock, favourites and drawer', (tester) async {
    await _loadRoboto();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['Calendar', 'Camera', 'Chrome', 'Clock', 'Figma', 'Gmail', 'Maps', 'Slack', 'Spotify', 'WhatsApp'])
            {'package': n.toLowerCase(), 'label': n, 'system': false},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({'favourites': ['whatsapp', 'slack', 'figma', 'spotify']});
    final prefs = await Prefs.load();

    await tester.pumpWidget(ColoredBox(color: const Color(0xFF3A4A6B), child: OneLauncher(prefs: prefs)));
    await tester.pump();
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('All apps'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/home.png'));

    await tester.tap(find.text('All apps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Gmail'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ma');
    await tester.pump();
    expect(find.text('↵ Open'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/drawer.png'));
  });
}
