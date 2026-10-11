import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/quick_chips.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('apps open from their icon; landing on return is quick; chips sit above the sheet', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    final launches = <Map>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Slack', 'Gmail'])
            {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      if (call.method == 'launch') launches.add(call.arguments as Map);
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(OneLauncher(prefs: await Prefs.load()));
    await tester.pumpAndSettle();

    // Chips are outside the app sheet: their row ends above the sheet's first card.
    final chipsBottom = tester.getBottomLeft(find.byType(QuickChipsRow)).dy;
    final cardTop = tester.getTopLeft(find.text('Social')).dy;
    expect(chipsBottom, lessThan(cardTop - 30), reason: 'chips float above the sheet');

    // Open Work and tap Gmail: the launch carries the icon's on-screen box.
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    final iconBox = tester.getRect(find.ancestor(of: find.text('Gmail').last, matching: find.byType(InkWell)).first);
    await tester.tap(find.text('Gmail').last);
    await tester.pump();
    final from = (launches.single['from'] as List).cast<int>();
    expect(from[0], closeTo(iconBox.left * 2.88, 3), reason: 'animation starts at the icon');
    expect(from[2], closeTo(iconBox.width * 2.88, 3));
    await tester.pumpAndSettle();

    // Back to the launcher after it was hidden: a quick settle-in, done within ~¼ s.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // The landing is a dark veil clearing over the home (cheap: no full-screen fade layer).
    Iterable<ColoredBox> veils() => tester.widgetList<ColoredBox>(find.byType(ColoredBox)).where((b) => b.color.r == 0 && b.color.g == 0 && b.color.b == 0 && b.color.a > .05 && b.color.a < .46);
    expect(veils(), isNotEmpty, reason: 'landing is playing');
    expect(tester.widgetList<Opacity>(find.byType(Opacity)).where((o) => o.opacity < 1 && o.opacity > 0 && o.opacity != .5), isEmpty, reason: 'no full-screen fade layer');
    await tester.pump(const Duration(milliseconds: 200));
    expect(veils(), isEmpty, reason: 'finished by ~260 ms');
  });
}
