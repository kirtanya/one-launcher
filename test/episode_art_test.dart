import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/tv/episode_art.dart';

void main() {
  test('reads season, episode and name from an app\'s title', () {
    final p = EpisodeArt.parse('S4 E9 Greatness Achieved')!;
    expect((p.season, p.episode, p.name), (4, 9, 'Greatness Achieved'));
    expect(EpisodeArt.parse('S12E3 · Pilot')?.episode, 3);
    expect(EpisodeArt.parse('Greatness Achieved'), isNull, reason: 'no S/E: not an episode');
  });

  test('show names from Wikidata descriptions', () {
    expect(
      EpisodeArt.showsFrom([
        'episode of Prison Break',
        'episode of M*A*S*H (S7 E18)',
        '8th episode of the third season of Star Trek: The Next Generation',
        '1977 novel by Sondra Marshak',
        null,
        'episode of Prison Break',
      ]),
      ['Prison Break', 'M*A*S*H', 'Star Trek: The Next Generation'],
    );
  });
}
