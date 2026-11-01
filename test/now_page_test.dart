import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/top/now_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The Now page (top carousel page 0) at the heights it gets: tall shows the top row and the wavy
  // seek bar; short folds ⏮ ⏭ beside the play pill. Nothing may overflow.
  for (final h in [320.0, 200.0, 130.0]) {
    testWidgets('Now page player fits at $h', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
        calls.add(call.method);
        if (call.method == 'mediaState') {
          return {
            'granted': true, 'active': true, 'app': 'YouTube Music', 'title': 'Mile Jo Sukoon', 'artist': 'KhoslaRaghu',
            'playing': true, 'position': 35000, 'duration': 256000, 'speed': 0.0, // speed 0: the real clock doesn't move the thumb
            'canPrev': true, 'canNext': true, 'canSeek': true,
          };
        }
        return null;
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      Apps.instance.init();
      await tester.pumpWidget(MaterialApp(
        home: ColoredBox(
          color: const Color(0xFF6A1A1A),
          child: Align(alignment: Alignment.topCenter, child: SizedBox(width: 380, height: h, child: NowPage(prefs: prefs))),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Mile Jo Sukoon'), findsOneWidget);
      if (h == 320) {
        await expectLater(find.byType(NowPage), matchesGoldenFile('shots/12b_now_page.png'));
        await tester.tap(find.bySemanticsLabel('Seek'));
        await tester.pump();
        expect(calls, contains('mediaSeek'));
      }
      await tester.tap(find.bySemanticsLabel('Pause'));
      await tester.pump();
      expect(calls, contains('mediaPlayPause'));
    });
  }
}
