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
    expect(
      find.descendant(of: preview, matching: find.byType(QuickChip)),
      findsWidgets,
      reason: 'chips in the live preview',
    );

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(chipMaterial().color, const Color(0xFFFFFFFF).withValues(alpha: .3), reason: 'light glass at its starting opacity');
    await tester.drag(find.byType(Slider).first, const Offset(600, 0)); // opacity → solid
    await tester.pumpAndSettle();
    expect(find.text('Solid'), findsOneWidget);
    expect(chipMaterial().color, const Color(0xFFFFFFFF));
    await tester.ensureVisible(find.text('Square')); // the controls panel scrolls
    await tester.pumpAndSettle();
    await tester.tap(find.text('Square'));
    await tester.pumpAndSettle();
    // Size, padding, gap and the space around the row are sliders.
    Slider sliderFor(String title) => tester.widget<Slider>(
      find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(Column)).first,
        matching: find.byType(Slider),
      ),
    );
    sliderFor('Size').onChanged!(48);
    await tester.pumpAndSettle();
    sliderFor('Padding inside').onChanged!(20);
    await tester.pumpAndSettle();
    Finder surface(Finder chip) => find.descendant(of: chip, matching: find.byType(Material)).first;
    expect(tester.getSize(surface(find.byType(QuickChip).first)).height, 48);
    await tester.ensureVisible(find.text('Icon only'));
    await tester.tap(find.text('Icon only'));
    await tester.pumpAndSettle();
    // Icon only: its own padding — 0 lets the icon fill the chip.
    double glyph() => tester.widget<Icon>(find.descendant(of: find.byType(QuickChip).first, matching: find.byType(Icon))).size!;
    expect(glyph(), closeTo(48 * .62, .01), reason: 'icon fills the chip');
    sliderFor('Padding inside').onChanged!(8);
    await tester.pumpAndSettle();
    expect(glyph(), closeTo((48 - 16) * .62, .01), reason: '8 around the icon');
    expect(ChipLook.of(prefs).padding, 20, reason: 'the label padding stays as it was');
    sliderFor('Gap between chips').onChanged!(16);
    sliderFor('Space above & below').onChanged!(20);
    await tester.pumpAndSettle();
    final chips = find.descendant(of: find.byWidgetPredicate((w) => w is HomeScreen && w.preview), matching: find.byType(QuickChip));
    // The live preview is drawn scaled down: measure the gap against a 48 tall chip.
    final scale = (tester.getBottomLeft(surface(chips.first)).dy - tester.getTopLeft(surface(chips.first)).dy) / 48;
    expect((tester.getTopLeft(surface(chips.at(1))).dx - tester.getTopRight(surface(chips.first)).dx) / scale, closeTo(16, .01), reason: 'gap between chips');
    expect(tester.getSize(find.byType(QuickChipsRow).first).height, 48 + 20 * 2, reason: 'space above & below');
    final shape = chipMaterial().shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(6));
    expect(tester.getSize(find.byType(QuickChip).first).height, greaterThanOrEqualTo(48));
    expect(
      find.descendant(of: find.byType(QuickChip).first, matching: find.byType(Text)),
      findsNothing,
      reason: 'icon only',
    );
    await tester.ensureVisible(find.text('Outline'));
    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    expect((chipMaterial().shape as RoundedRectangleBorder).side, BorderSide.none);
    await tester.ensureVisible(find.text('Chip look'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/15_chip_look.png'));

    // Saved (and so in backups), and the back arrow returns to Quick actions.
    expect(ChipLook.of(prefs).toJson(), {
      'tone': 'light',
      'opacity': 1.0,
      'shape': 'square',
      'height': 48.0,
      'content': 'icon',
      'outline': false,
      'gap': 16.0,
      'padding': 20.0,
      'iconPadding': 8.0,
      'space': 20.0,
    });
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
    expect(find.text('Reset the chips’ look?'), findsOneWidget, reason: 'asks first');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Reset')));
    await tester.pumpAndSettle();
    expect(chipMaterial().color, const Color(0xFF141414).withValues(alpha: .4));
    expect(ChipLook.of(prefs).toJson().containsKey('space'), isFalse, reason: 'spacing follows the size again');
  });

  test('older looks saved a size name; Tiles still reads one', () {
    expect(const ChipLook().copyWith(size: 'large').height, 48);
    expect(const ChipLook(height: 33).size, 'small');
    expect(const ChipLook(height: 52).size, 'large');
    expect(const ChipLook(height: 40).rowHeight, 56, reason: 'regular: 8 above and below');
  });
}
