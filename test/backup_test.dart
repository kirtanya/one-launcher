import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('backup → change everything → restore brings it all back (widgets on this phone stay)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    String? saved;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      switch (call.method) {
        case 'getApps':
          return [
            for (final n in ['WhatsApp', 'Slack', 'Paytm']) {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
          ];
        case 'saveBackup':
          saved = (call.arguments as Map)['text'] as String;
          return true;
        case 'openBackup':
          return saved;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    // A setup worth keeping.
    await prefs.toggleFavourite('com.whatsapp');
    await prefs.toggleFavourite('com.slack');
    await prefs.renameFolder('money', 'Payments');
    await prefs.setTheme(source: 'basic', seed: 0xFF9C27B0, style: 'vibrant');
    await prefs.setTopShare(0.4);
    await prefs.setTopPadding(24);
    await prefs.setClockStyle(weight: 800, width: 60, slant: -10);
    await prefs.setTopEnabled('battery', true);
    await prefs.addWidgetPage(7, 'Calendar · Month'); // a widget on this phone

    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();

    // Settings → Backup & restore → Save.
    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Backup & restore')); // last group: may sit below the fold
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup & restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save backup to a file'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(find.textContaining('Saved OneLauncher-backup-'), findsOneWidget);
    expect(saved, isNot(contains('widget:7')), reason: 'widgets stay out of backups');

    // Change everything.
    await prefs.unpinAll();
    await prefs.renameFolder('money', null);
    await prefs.setTheme(source: 'original');
    await prefs.setTopShare(0.2);
    await prefs.setClockStyle(weight: 300, width: 25, slant: 0);
    await tester.pumpAndSettle();

    // Restore (confirm in the dialog).
    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Restore backup from'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Restored'), findsOneWidget);

    expect(prefs.favourites, ['com.whatsapp', 'com.slack']);
    expect(prefs.folderNames['money'], 'Payments');
    expect((prefs.themeSource, prefs.themeSeed, prefs.themeStyle), ('basic', 0xFF9C27B0, 'vibrant'));
    expect(prefs.topShare, 0.4);
    expect(prefs.topPadding, 24);
    expect((prefs.clockWeight, prefs.clockWidth, prefs.clockSlant), (800.0, 60.0, -10.0), reason: 'clock style restored');
    expect(prefs.topPages, containsAllInOrder(['clock', 'screen_time', 'battery', 'widget:7', 'blank']), reason: 'pages back + this phone\'s widget kept');

    // A random file is refused.
    expect(() => prefs.importBackup('{"hello": 1}'), throwsA(isA<FormatException>()));
  });
}
