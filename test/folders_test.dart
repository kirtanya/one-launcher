import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/search_dock.dart';
import 'package:one_launcher/ui/motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('folder opens and glides in one motion; long folder header pins', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Slack', 'Gmail', 'Paytm', 'PhonePe', 'Splitwise', 'Spotify', 'Maps', 'Uber', 'Settings'])
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

    // Open the 80-app Games folder: it's capped so the card above and the folder below
    // (Tools) both stay in view; its apps scroll inside the card.
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    final header = tester.getTopLeft(find.text('Games')).dy;
    final toolsY = tester.getTopLeft(find.text('Tools')).dy;
    final dockTop = tester.getTopLeft(find.byIcon(Icons.search_rounded).last).dy - 16; // top of the search bar
    expect(header, greaterThan(70), reason: 'a slice of the card above stays visible');
    expect(toolsY, lessThan(dockTop - 8), reason: 'the folder below stays visible above the search bar');
    expect(toolsY - header, lessThan(screenH), reason: 'folder never taller than the screen');

    // Drag inside the folder: only its apps move.
    final app0 = tester.getTopLeft(find.text('Game 12')).dy;
    await tester.drag(find.text('Game 12'), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Games')).dy, closeTo(header, 1), reason: 'main list stays put');
    expect(tester.getTopLeft(find.text('Game 12')).dy, lessThan(app0 - 200), reason: 'apps scrolled inside the card');
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/8_folder_scrolls_inside.png'));

    // Keep dragging past the folder's last row: the rest moves the main list.
    for (var k = 0; k < 6; k++) {
      await tester.dragFrom(Offset(180, header + 200), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(tester.getTopLeft(find.text('Games')).dy, lessThan(header - 40), reason: 'main list took over after the folder ended');
    expect(find.text('Game 80').hitTestable(), findsOneWidget, reason: 'reached the end of the folder');

    // Close and reopen Games (it re-centres; its grid starts at the top again), then one hard
    // flick: the fling runs through the folder and its leftover momentum scrolls the main list.
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    final restY = tester.getTopLeft(find.text('Games')).dy;
    await tester.flingFrom(Offset(180, restY + 200), const Offset(0, -300), 9000);
    await tester.pumpAndSettle();
    expect(find.text('Game 80').hitTestable(), findsOneWidget, reason: 'fling went through the folder');
    expect(tester.getTopLeft(find.text('Games')).dy, lessThan(restY - 20), reason: 'and carried on into the main list');
  });

  testWidgets('a folder gliding into view does not expand the shrunk search bar', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Slack', 'Gmail', 'Paytm', 'PhonePe', 'Spotify', 'YouTube', 'Maps', 'Uber', 'Swiggy', 'Zomato', 'Kindle', 'Chess'])
            {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
          for (var i = 1; i <= 30; i++) {'package': 'com.tool$i', 'label': 'Tool $i', 'system': true, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(OneLauncher(prefs: await Prefs.load()));
    await tester.pumpAndSettle();
    bool compact() => tester.widget<SearchDock>(find.byType(SearchDock)).compact;

    // Full screen, then scroll the list up so the search bar shrinks to a circle.
    await tester.fling(find.text('Social'), const Offset(0, -300), 1500);
    await tester.pumpAndSettle();
    await tester.drag(find.text('Money'), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(compact(), isTrue, reason: 'user scrolled up');

    // Open a folder sitting high on screen: the list glides back down to centre it.
    final before = tester.getTopLeft(find.text('Money')).dy;
    await tester.tap(find.text('Money'));
    // Check every frame of the glide (the bug flipped it on the first frame).
    for (var f = 0; f < 40; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(compact(), isTrue, reason: 'stays a circle during the glide (frame $f)');
    }
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Money')).dy, greaterThan(before + 20), reason: 'list scrolled down to centre it');
    expect(compact(), isTrue, reason: 'scrolling done by the app must not expand the search bar');

    // Closing and opening from the top: opening shrinks the bar straight away.
    await tester.drag(find.text('Money'), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(compact(), isFalse, reason: 'back at the top: full bar');
    await tester.tap(find.text('Work'));
    await tester.pump();
    expect(compact(), isTrue, reason: 'opening a folder shrinks the search bar');
    await tester.pumpAndSettle();
    expect(compact(), isTrue, reason: 'stays shrunk until the user scrolls');

    // A real finger scroll back down still expands it.
    await tester.drag(find.text('Money'), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(compact(), isFalse, reason: 'user scrolled down');
  });

  testWidgets('icons scale in/out at the folder edge; sheet and folders snap with haptics', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Settings'])
            {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': n == 'Settings', 'category': -1, 'installed': 0},
          for (var i = 1; i <= 80; i++) {'package': 'com.game$i', 'label': 'Game ${i.toString().padLeft(2, '0')}', 'system': false, 'category': 0, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(OneLauncher(prefs: await Prefs.load()));
    await tester.pumpAndSettle();

    // Snap the sheet to full screen → a tick.
    haptics.clear();
    await tester.fling(find.text('Social'), const Offset(0, -300), 1500);
    await tester.pumpAndSettle();
    expect(haptics, contains('HapticFeedbackType.lightImpact'), reason: 'sheet snapped full');

    // Open Games → press tap + settle tick.
    haptics.clear();
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    expect(haptics, containsAllInOrder(['HapticFeedbackType.selectionClick', 'HapticFeedbackType.lightImpact']), reason: 'folder tap + snap');

    // Icons at the grid's edge are part-scaled, the rest are full size.
    List<double> fractions() => [for (final r in tester.renderObjectList<RenderEdgeScale>(find.byType(EdgeScale))) r.visibleFraction];
    final before = fractions();
    expect(before.where((f) => f >= .999), isNotEmpty, reason: 'icons fully in view are 100%');
    expect(before.where((f) => f > .01 && f < .99), isNotEmpty, reason: 'icons cut by the edge are part-scaled');
    await tester.drag(find.text('Game 05'), const Offset(0, -130));
    await tester.pumpAndSettle();
    expect(fractions(), isNot(equals(before)), reason: 'scaling follows the scroll');

    // Close Games → tap + settle tick.
    haptics.clear();
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    expect(haptics, containsAllInOrder(['HapticFeedbackType.selectionClick', 'HapticFeedbackType.lightImpact']), reason: 'folder closed + snap');
  });

  testWidgets('folder cards scale 60→100% at the list edges', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['WhatsApp', 'Slack', 'Paytm', 'Spotify', 'Swiggy', 'Maps', 'Kindle', 'Chess', 'Fitbit', 'Settings', 'Zzz'])
            {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': n == 'Settings', 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(OneLauncher(prefs: await Prefs.load()));
    await tester.pumpAndSettle();
    await tester.fling(find.text('Social'), const Offset(0, -300), 1500); // full screen
    await tester.pumpAndSettle();

    double scaleOf(String folder) {
      final r = tester.renderObject<RenderEdgeScale>(find.ancestor(of: find.text(folder), matching: find.byType(EdgeScale)).first);
      return r.minScale + (1 - r.minScale) * Curves.easeOut.transform(r.visibleFraction);
    }

    final names = ['Social', 'Work', 'Money', 'Watch & Listen', 'Shop & Services', 'Travel', 'News & Reading', 'Games', 'Health & Home', 'Tools', 'Everything else'];
    final scales = [for (final n in names) if (tester.any(find.text(n))) scaleOf(n)];
    final partly = scales.where((s) => s < .999).toList();
    expect(scales.where((s) => s >= .999), isNotEmpty, reason: 'folders fully in view are 100%');
    expect(partly, isNotEmpty, reason: 'a folder near the bottom edge is part-scaled');
    expect(partly.every((s) => s >= .6), isTrue, reason: 'never below 60%');
  });
}
