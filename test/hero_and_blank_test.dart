import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('green card has 2 swipeable pages; wallpaper-only top page shows nothing', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    final names = [for (var i = 1; i <= 12; i++) 'App ${i.toString().padLeft(2, '0')}'];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in names) {'package': 'p.${n.replaceAll(' ', '')}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'favourites': [for (final n in names) 'p.${n.replaceAll(' ', '')}'],
    });
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();

    // Green card: page 1 = first 8 pins; page 2 = the rest.
    expect(find.text('App 01'), findsOneWidget);
    expect(find.text('App 09').hitTestable(), findsNothing);
    await tester.fling(find.text('App 06'), const Offset(-250, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('App 09').hitTestable(), findsOneWidget, reason: 'second page');
    expect(find.text('App 01').hitTestable(), findsNothing);

    // Top carousel: Clock → Screen time → Just wallpaper (on by default).
    expect(prefs.topPages, ['clock', 'screen_time', 'now_playing', 'blank']);
    final carousel = find.byType(PageView).first;
    for (var i = 0; i < 3; i++) {
      await tester.fling(carousel, const Offset(-250, 0), 1200);
      await tester.pumpAndSettle();
    }
    final topRect = tester.getRect(carousel);
    final textsOnTop = tester.widgetList<Text>(find.byType(Text)).where((t) {
      final f = find.byWidget(t);
      return tester.any(f.hitTestable()) && topRect.contains(tester.getCenter(f));
    });
    expect(textsOnTop, isEmpty, reason: 'nothing on top but the wallpaper');
    final dots = tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity)).where((o) => o.opacity == 0);
    expect(dots, isNotEmpty, reason: 'page dots and top tint faded out');
  });
}
