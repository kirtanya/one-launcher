import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/app_lock.dart';
import 'package:one_launcher/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<(String, Object?)> calls;
  late DateTime clock;
  var recent = false; // what the native guard answers to lockRecent

  Future<AppLock> make({Map<String, Object> initial = const {}}) async {
    calls = [];
    recent = false;
    clock = DateTime(2026);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      calls.add((call.method, call.arguments));
      return call.method == 'lockRecent' ? recent : null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null); // haptics
    SharedPreferences.setMockInitialValues({'lockedApps': ['com.bank'], ...initial});
    return AppLock(await Prefs.load(), now: () => clock);
  }

  void wait(int ms) => clock = clock.add(Duration(milliseconds: ms));

  test('unlocked apps always open', () async {
    final lock = await make();
    expect(lock.tap('com.other'), isTrue);
  });

  test('a single tap does not launch; a fast double tap does, lockAllow first', () async {
    final lock = await make();
    expect(await lock.gate('com.bank'), isFalse);
    expect(calls.where((c) => c.$1 == 'lockAllow'), isEmpty);
    expect(calls.last.$1, 'toast'); // a swallowed tap says only "App not supported"
    expect(calls.last.$2, {'text': 'App not supported'});
    wait(200);
    expect(await lock.gate('com.bank'), isTrue);
    expect(calls.last.$1, 'lockAllow');
    expect(calls.last.$2, {'package': 'com.bank'});
  });

  test('slow taps never add up', () async {
    final lock = await make();
    expect(lock.tap('com.bank'), isFalse);
    wait(400);
    expect(lock.tap('com.bank'), isFalse);
    wait(400);
    expect(lock.tap('com.bank'), isFalse);
  });

  test('triple mode needs 3 fast taps', () async {
    final lock = await make(initial: {'lockTaps': 3});
    expect(lock.tap('com.bank'), isFalse);
    wait(200);
    expect(lock.tap('com.bank'), isFalse);
    wait(200);
    expect(lock.tap('com.bank'), isTrue);
  });

  test('unlocking needs the right PIN; the PIN is stored hashed', () async {
    final lock = await make();
    await lock.setPin('1234');
    expect(lock.prefs.lockPinHash, isNot(contains('1234')));
    expect(await lock.unlock('com.bank', '0000'), isFalse);
    expect(lock.isLocked('com.bank'), isTrue);
    expect(await lock.unlock('com.bank', '1234'), isTrue);
    expect(lock.isLocked('com.bank'), isFalse);
  });

  test('setLockedApps is sent with the whole list on every change', () async {
    final lock = await make();
    await lock.sync();
    expect(calls.last.$1, 'setLockedApps');
    expect(calls.last.$2, {'packages': ['com.bank']});
    await lock.lock('com.mail');
    expect(calls.last.$2, {'packages': ['com.bank', 'com.mail']});
  });

  test('reopen without lock: a just-left app opens on one tap, only when the window is on', () async {
    var lock = await make();
    recent = true;
    expect(await lock.gate('com.bank'), isFalse, reason: 'off: the native answer is not even asked');
    expect(calls.where((c) => c.$1 == 'lockRecent'), isEmpty);

    lock = await make(initial: {'lockGrace': 5});
    recent = true;
    expect(await lock.gate('com.bank'), isTrue);
    expect(calls.last.$1, 'lockAllow');
    expect(calls.last.$2, {'package': 'com.bank'});
    recent = false;
    wait(1000);
    expect(await lock.gate('com.bank'), isFalse, reason: 'window over: taps again');
  });

  test('setGrace stores it and tells the native guard; sync sends it too', () async {
    final lock = await make();
    await lock.setGrace(10);
    expect(lock.prefs.lockGrace, 10);
    expect(calls.last.$1, 'setLockGrace');
    expect(calls.last.$2, {'seconds': 10});
    await lock.sync();
    expect(calls.map((c) => c.$1), containsAllInOrder(['setLockGrace', 'setLockedApps']));
    expect(lock.prefs.exportBackup(), isNot(contains('lockGrace')), reason: 'phone-only, like the lock list');
  });

  test('sha256 matches a known vector', () {
    final h = sha256('abc'.codeUnits).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(h, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
}
