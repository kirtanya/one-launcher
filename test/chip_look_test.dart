import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/home.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/quick_chips.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Quick actions → Chip look: colour, opacity, shape, size, icon-only, outline — live on the home chips', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Slack', 'Paytm']) {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();

    Material chipMaterial() => tester.widget<Material>(find.descendant(of: find.byType(QuickChip).first, matching: find.byType(Material)).first);
    // Default: the original dark see-through pill.
    expect(chipMaterial().color, const Color(0xFF141414).withValues(alpha: .4));

    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Quick chips'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick chips'));
    await tester.pumpAndSettle();
    expect(find.text('Dark · 40% · Pill'), findsOneWidget);
    await tester.tap(find.text('Chip look'));
    await tester.pumpAndSettle();
    // An editor: the home screen (with its chips) live above the controls.
    final preview = find.byWidgetPredicate((w) => w is HomeScreen && w.preview);
    expect(find.descendant(of: preview, matching: find.byType(QuickChip)), findsWidgets, reason: 'chips in the live preview');

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(chipMaterial().color, const Color(0xFFFFFFFF).withValues(alpha: .3), reason: 'light glass at its starting opacity');
    await tester.drag(find.byType(Slider), const Offset(600, 0)); // opacity → solid
    await tester.pumpAndSettle();
    expect(find.text('Solid'), findsOneWidget);
    expect(chipMaterial().color, const Color(0xFFFFFFFF));
    for (final option in ['Square', 'Large']) {
      await tester.ensureVisible(find.text(option)); // the controls panel scrolls
      await tester.pumpAndSettle();
      await tester.tap(find.text(option));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Icon only'));
    await tester.tap(find.text('Icon only'));
    await tester.pumpAndSettle();
    final shape = chipMaterial().shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(6));
    expect(tester.getSize(find.byType(QuickChip).first).height, greaterThanOrEqualTo(48));
    expect(find.descendant(of: find.byType(QuickChip).first, matching: find.byType(Text)), findsNothing, reason: 'icon only');
    await tester.ensureVisible(find.text('Outline'));
    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    expect((chipMaterial().shape as RoundedRectangleBorder).side, BorderSide.none);
    await tester.ensureVisible(find.text('Chip look'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/15_chip_look.png'));

    // Saved (and so in backups), and the back arrow returns to Quick actions.
    expect(ChipLook.of(prefs).toJson(), {'tone': 'light', 'opacity': 1.0, 'shape': 'square', 'size': 'large', 'content': 'icon', 'outline': false});
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Light · 100% · Square'), findsOneWidget);
    // Reset brings the original back.
    await tester.tap(find.text('Chip look'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reset look'));
    await tester.tap(find.text('Reset look'));
    await tester.pumpAndSettle();
    expect(chipMaterial().color, const Color(0xFF141414).withValues(alpha: .4));
  });
}
