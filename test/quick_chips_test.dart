import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/home.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Android's screen timeout and "Modify system settings", as the Caffeine chip sees them.
  var screenTimeout = 30000;
  var canWrite = true;

  Future<(Prefs, List<MethodCall>)> launch(WidgetTester tester, {bool shortcutsAllowed = true}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getApps':
          return [
            for (final n in ['Paytm', 'Gmail'])
              {'package': n == 'Paytm' ? 'net.one97.paytm' : 'com.google.android.gm', 'label': n, 'system': false, 'category': -1, 'installed': 0},
          ];
        case 'listShortcuts':
          if (!shortcutsAllowed) return {'allowed': false};
          return {
            'allowed': true,
            'shortcuts': [
              {'id': 's:com.google.android.gm|compose|0', 'package': 'com.google.android.gm', 'app': 'Gmail', 'label': 'Compose', 'work': false},
              {'id': 's:net.one97.paytm|scan|0', 'package': 'net.one97.paytm', 'app': 'Paytm', 'label': 'Scan any QR', 'work': false},
            ],
          };
        case 'quickAction':
          return true;
        case 'caffeineState':
          return {'canWrite': canWrite, 'timeout': screenTimeout};
        case 'setScreenTimeout':
          screenTimeout = (call.arguments as Map)['ms'] as int;
          return true;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    Apps.instance.init();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    return (prefs, calls);
  }

  testWidgets('chips: Paytm scan seeded first, actions run, flashlight lights up, customise', (tester) async {
    final (prefs, calls) = await launch(tester);
    expect(prefs.quickChips.first, 's:net.one97.paytm|scan|0', reason: 'Scan QR seeded first');
    expect(find.text('Scan any QR'), findsOneWidget);
    expect(find.text('Set timer'), findsOneWidget);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/13_quick_chips.png'));

    await tester.tap(find.text('Set timer'));
    await tester.pump();
    expect(calls.where((c) => c.method == 'quickAction').last.arguments, {'id': 'b:timer'});
    await tester.tap(find.text('Scan any QR'));
    await tester.pump();
    expect(calls.where((c) => c.method == 'quickAction').last.arguments, {'id': 's:net.one97.paytm|scan|0'});

    // Android says the flashlight came on.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'one_launcher/apps',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('torchChanged', true)),
      (_) {},
    );
    await tester.pump();
    await tester.drag(find.text('Set timer'), const Offset(-200, 0)); // scroll the chip row like a person would
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.flashlight_on_rounded), findsOneWidget, reason: 'chip shows it on');

    // Customise (＋ at the end of the row): add Gmail → Compose, remove Camera.
    await tester.drag(find.text('Flashlight'), const Offset(-800, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Customise quick actions'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Compose'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    expect(prefs.quickChips, contains('s:com.google.android.gm|compose|0'));
    await tester.scrollUntilVisible(find.byTooltip('Remove Camera'), -200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byTooltip('Remove Camera'));
    await tester.pumpAndSettle();
    expect(prefs.quickChips, isNot(contains('b:camera')));
  });

  testWidgets('quick actions: search finds built-in actions and app shortcuts to add', (tester) async {
    final (prefs, _) = await launch(tester);
    await tester.drag(find.text('Set timer'), const Offset(-800, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Customise quick actions'));
    await tester.pumpAndSettle();
    expect(find.text('Chip look'), findsOneWidget);

    // An editor: the home screen live above, the controls (and their search) below.
    expect(find.byWidgetPredicate((w) => w is HomeScreen && w.preview), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'gmail');
    await tester.pumpAndSettle();
    expect(find.text('Compose'), findsOneWidget, reason: 'matches the app name');
    expect(find.text('Chip look'), findsNothing, reason: 'while searching only addable actions show');
    expect(find.text('Built-in'), findsNothing, reason: 'no built-in matches → no empty section');
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    expect(prefs.quickChips, contains('s:com.google.android.gm|compose|0'));

    await tester.enterText(find.byType(TextField), 'blue');
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth'), findsOneWidget, reason: 'built-in action found');
    expect(find.text('Alarms'), findsNothing);
    expect(find.text('No app shortcuts match “blue”.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Chip look'), findsOneWidget, reason: 'cleared → the whole page again');
  });

  testWidgets('not the home app: explains why app shortcuts are missing', (tester) async {
    final (prefs, _) = await launch(tester, shortcutsAllowed: false);
    expect(prefs.qrSeeded, isFalse, reason: 'will try again once allowed');
    await tester.longPress(find.text('Set timer')); // long-press any chip also opens it
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Set One Launcher as your home app'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('Set One Launcher as your home app'), findsOneWidget);
  });

  testWidgets('caffeine: asks for the permission, cycles the timeout, puts the phone\'s own back', (tester) async {
    screenTimeout = 30000;
    canWrite = false;
    final (prefs, calls) = await launch(tester);
    await prefs.addQuickChip('b:caffeine', first: true);
    await tester.pumpAndSettle();
    expect(find.text('Caffeine'), findsOneWidget);

    // Not allowed yet: explains, Allow opens Android's page.
    await tester.tap(find.text('Caffeine'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Modify system settings'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pump();
    expect(calls.map((c) => c.method), contains('openWriteSettings'));
    expect(calls.map((c) => c.method), isNot(contains('setScreenTimeout')));
    ScaffoldMessenger.of(tester.element(find.text('Caffeine'))).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    canWrite = true;
    final sp = await SharedPreferences.getInstance();
    for (final (label, ms) in [('Caffeine · 5 min', 300000), ('Caffeine · 10 min', 600000), ('Caffeine · awake', 2147483647)]) {
      await tester.tap(find.textContaining('Caffeine'));
      await tester.pumpAndSettle();
      expect(screenTimeout, ms);
      expect(find.text(label), findsOneWidget);
      expect(find.byIcon(Icons.coffee_rounded), findsOneWidget, reason: 'lit while on');
    }
    expect(sp.getInt('caffeineOriginal'), 30000, reason: 'the phone\'s own timeout is remembered');

    await tester.tap(find.textContaining('Caffeine'));
    await tester.pumpAndSettle();
    expect(screenTimeout, 30000, reason: 'Off puts the phone\'s own timeout back');
    expect(find.text('Caffeine'), findsOneWidget);
    expect(sp.getInt('caffeineOriginal'), isNull);

    // Long-press: pick a level directly.
    await tester.longPress(find.text('Caffeine'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, '10 min'));
    await tester.pumpAndSettle();
    expect(screenTimeout, 600000);
    expect(find.text('Caffeine · 10 min'), findsOneWidget);
  });
}
