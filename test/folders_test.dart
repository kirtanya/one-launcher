import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('folder opens and glides in one motion; long folder header pins', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Slack', 'Gmail', 'Paytm', 'PhonePe', 'Splitwise', 'Spotify', 'Maps', 'Uber'])
            {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
          for (var i = 1; i <= 80; i++)
            {'package': 'com.game$i', 'label': 'Game ${i.toString().padLeft(2, '0')}', 'system': false, 'category': 0, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(OneLauncher(prefs: await Prefs.load()));
    await tester.pumpAndSettle();
    final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;

    // Open a short folder: it should start moving while it is still opening (same motion).
    final y0 = tester.getTopLeft(find.text('Money')).dy;
    await tester.tap(find.text('Money'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // mid-animation
    final yMid = tester.getTopLeft(find.text('Money')).dy;
    final gridMid = tester.any(find.text('PhonePe'));
    await tester.pumpAndSettle();
    final yEnd = tester.getTopLeft(find.text('Money')).dy;
    // ignore: avoid_print
    print('Money header y: start $y0 → mid $yMid → end $yEnd (grid visible mid-way: $gridMid)');
    expect(gridMid, isTrue, reason: 'grid is opening while the folder moves');
    expect(yMid, isNot(closeTo(y0, 2)), reason: 'already moving at 200ms');
    final cardMid = (yEnd - 12 + tester.getBottomLeft(find.text('Splitwise')).dy + 16) / 2;
    expect((cardMid - screenH / 2).abs(), lessThan(90), reason: 'short folder ends centred-ish (card mid $cardMid)');

    // Open the 80-app Games folder: taller than the screen → header stops at the top, not above.
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    final headerTop = tester.getTopLeft(find.text('Games')).dy;
    // ignore: avoid_print
    print('Games header text y after open: $headerTop');
    expect(headerTop, inInclusiveRange(8, 60), reason: 'long folder header sits at the top, visible');

    // Scroll through the folder: header stays pinned while the apps move under it.
    await tester.drag(find.text('Game 12'), const Offset(0, -300));
    await tester.pumpAndSettle();
    final pinnedY = tester.getTopLeft(find.text('Games')).dy;
    final appY0 = tester.getTopLeft(find.text('Game 20')).dy;
    await tester.drag(find.text('Game 20'), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Games')).dy, closeTo(pinnedY, 1), reason: 'header stays pinned while scrolling');
    expect(pinnedY, lessThan(40), reason: 'pinned at the top of the sheet');
    expect(tester.getTopLeft(find.text('Game 20')).dy, lessThan(appY0 - 40), reason: 'apps scroll under it (until the list ends)');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/8_sticky_header.png'));
  });
}
