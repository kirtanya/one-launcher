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

  test('a description naming other numbers is left out', () {
    expect(
      EpisodeArt.showsFrom(['episode of Desperate Housewives (S4 E17)', 'episode of Nikita (S1 E12)', 'episode of Prison Break'], season: 4, episode: 24),
      ['Prison Break'],
    );
  });

  test('episode still: exact match, else the name alone within the show', () {
    String still(int s, int e) => 'https://episodes.example/$s/$e.jpg';
    final videos = [
      {'season': 4, 'episode': 22, 'name': 'Killing Your Number', 'thumbnail': still(4, 22)},
      {'season': 0, 'episode': 1, 'name': 'The Old Ball and Chain (1)', 'thumbnail': still(0, 1)},
      {'season': 0, 'episode': 2, 'name': 'Free (2)', 'thumbnail': still(0, 2)},
    ];
    expect(EpisodeArt.stillFor(videos, 4, 22, 'Killing Your Number'), still(4, 22));
    expect(EpisodeArt.stillFor(videos, 4, 24, 'Free'), still(0, 2), reason: 'JioHotstar S4 E24 = Cinemeta special "Free (2)"');
    expect(EpisodeArt.stillFor(videos, 4, 23, 'Pilot'), isNull);
    final twice = [
      ...videos,
      {'season': 2, 'episode': 5, 'name': 'Free', 'thumbnail': still(2, 5)},
    ];
    expect(EpisodeArt.stillFor(twice, 4, 24, 'Free'), isNull, reason: 'two episodes of that name, neither numbered so: no guess');
    expect(EpisodeArt.foldName('Free, Part 2'), 'free');
  });
}
