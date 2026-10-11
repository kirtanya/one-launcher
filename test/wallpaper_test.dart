import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/photo_wallpaper.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// File reads, decoding and blur baking run outside the fake test clock: give them real time.
Future<void> settleImages(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Settings → Wallpaper → Your photo: picked, framed (zoom, position, blur), back to phone wallpaper', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    // A real image file stands in for the picked photo.
    final photo = File('${Directory.systemTemp.createTempSync().path}/photo.png');
    photo.writeAsBytesSync(File('test/shots/1_rest.png').readAsBytesSync());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      switch (call.method) {
        case 'getApps':
          return [
            for (final n in ['WhatsApp', 'Slack', 'Paytm']) {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
          ];
        case 'pickPhoto':
          return photo.path;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Launcher settings'));
    await tester.pumpAndSettle();
    expect(find.text('Phone wallpaper · dim 20%'), findsOneWidget);
    await tester.tap(find.text('Wallpaper'));
    await tester.pumpAndSettle();
    expect(find.text('Zoom'), findsNothing, reason: 'no framing for the phone wallpaper');

    await tester.tap(find.text('Your photo'));
    await tester.pumpAndSettle();
    expect(prefs.wallpaperPhoto, photo.path);
    await settleImages(tester);
    // Picking opens the full-screen editor straight away.
    expect(find.text('Drag to move · pinch to zoom'), findsOneWidget);
    final editor = find.byType(PhotoWallpaper).last;
    expect(find.descendant(of: editor, matching: find.byType(CustomPaint)), findsOneWidget, reason: 'photo shown');

    // Pinch out → zoom in, then drag down → the photo moves down (shows more of its top).
    final c = tester.getCenter(editor);
    final a = await tester.startGesture(c - const Offset(40, 0));
    final b = await tester.startGesture(c + const Offset(40, 0), pointer: 2);
    await a.moveTo(c - const Offset(100, 0));
    await b.moveTo(c + const Offset(100, 0));
    await a.up();
    await b.up();
    await tester.pump();
    expect(prefs.photoZoom, greaterThan(1.3), reason: 'pinch zooms (minus touch slop)');
    await tester.dragFrom(c, const Offset(0, 200));
    await tester.pump();
    expect(prefs.photoY, lessThan(-.2), reason: 'drag down shows the top of the photo');
    // Only the top window (above the app sheet) is clear; the rest is shaded and labelled.
    expect(find.text('Your apps cover this part'), findsOneWidget);
    final screen = tester.getSize(editor);
    final win = photoWindow(prefs, screen);
    expect(tester.getTopLeft(find.text('Drag to move · pinch to zoom')).dy, greaterThan(win), reason: 'hint sits in the covered part');
    // The photo always covers the window, whatever the framing.
    final r = photoRect(const Size(1080, 2400), screen, win, prefs.photoZoom, prefs.photoX, prefs.photoY);
    expect(r.top, lessThanOrEqualTo(0));
    expect(r.left, lessThanOrEqualTo(0));
    expect(r.right, greaterThanOrEqualTo(screen.width - .01));
    expect(r.bottom, greaterThanOrEqualTo(win - .01));

    // Blur is baked into a small copy of the photo.
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await settleImages(tester);
    expect(prefs.photoBlur, 24);
    await expectLater(find.byType(OneLauncher), matchesGoldenFile('shots/14_photo_editor.png'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Adjust photo'), findsOneWidget, reason: 'back on the Wallpaper sheet');
    expect(find.descendant(of: find.byType(PhotoWallpaper), matching: find.byType(CustomPaint)), findsOneWidget, reason: 'photo behind the launcher');

    // Back to the phone wallpaper: the photo goes away.
    await tester.tap(find.text('Phone wallpaper'));
    await tester.pumpAndSettle();
    expect(prefs.wallpaperPhoto, isNull);
    expect(find.descendant(of: find.byType(PhotoWallpaper), matching: find.byType(CustomPaint)), findsNothing);
    // Back arrow → grouped settings with the new summary.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Phone wallpaper · dim 20%'), findsOneWidget);
    expect(prefs.exportBackup(), isNot(contains('wallpaperPhoto')), reason: 'the photo path is phone-specific');
  });
}
