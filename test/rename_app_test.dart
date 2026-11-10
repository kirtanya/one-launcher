import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/apps.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/search.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a renamed app shows and is found by its new name; empty goes back to its own', () async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          {'package': 'com.whatsapp', 'label': 'WhatsApp'},
          {'package': 'com.spotify.music', 'label': 'Spotify'},
        ];
      }
      return null;
    });
    final prefs = await Prefs.load();
    await prefs.renameApp('com.whatsapp', '  Chats ');

    var apps = await Apps.instance.list();
    final wa = apps.firstWhere((a) => a.package == 'com.whatsapp');
    expect(wa.label, 'Chats');
    expect(Apps.instance.ownLabel(wa), 'WhatsApp');
    expect(searchApps(apps, 'cha').map((a) => a.package), ['com.whatsapp']);
    expect(searchApps(apps, 'whats'), isEmpty);

    await prefs.renameApp('com.whatsapp', '');
    apps = await Apps.instance.list();
    expect(apps.firstWhere((a) => a.package == 'com.whatsapp').label, 'WhatsApp');
    expect(prefs.appNames, isEmpty);
  });
}
