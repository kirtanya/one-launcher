import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/tv_remote.dart';

void main() {
  test('TV address in any common form; Wake-on-LAN packet = 6 × FF then the address 16 times', () {
    const mac = [0xc8, 0x7e, 0xa1, 0x88, 0x15, 0xc2];
    expect(TvRemote.macBytes('c8:7e:a1:88:15:c2'), mac);
    expect(TvRemote.macBytes('C8-7E-A1-88-15-C2'), mac);
    expect(TvRemote.macBytes('c87e.a188.15c2'), mac);
    expect(TvRemote.macBytes('c8:7e:a1:88:15'), isNull, reason: 'too short');
    final p = TvRemote.magicPacket(mac);
    expect(p.length, 102);
    expect(p.take(6), everyElement(0xFF));
    expect(p.sublist(6, 12), mac);
    expect(p.sublist(96), mac);
  });
}
