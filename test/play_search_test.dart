import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/play_search.dart';

// Trimmed from a real Play Store search page: the top result (big card) and a list result.
const _page = '''
<a href="/store/apps/details?id=com.spotify.music" aria-label="Spotify: Music and Podcasts" class="Qfxief"></a>
<div><img src="https://play-lh.googleusercontent.com/AAA=s64-rw" alt="Icon image" /><div><div class="a">Spotify: Music and Podcasts</div>
<div class="b">Spotify AB</div></div><div role="img" aria-label="Rated 4.2 stars out of five stars"></div>
<a href="intent://play.google.com/store/apps/details?id=com.spotify.music&amp;x=1"></a></div>
<a class="Si6A0c" href="/store/apps/details?id=com.soundcloud.android"><img src="https://play-lh.googleusercontent.com/SHOT=w416-h235-rw" alt="Screenshot image" />
<img src="https://play-lh.googleusercontent.com/BBB=s64-rw" alt="Thumbnail image" /><span>SoundCloud &amp; Friends</span><span>SoundCloud</span>
<div role="img" aria-label="Rated 4.6 stars out of five stars"></div></a>
<a href="/store/apps/details?id=com.spotify.music"></a>
''';

void main() {
  test('reads each app once, in order: name, developer, icon, stars', () {
    final apps = PlaySearch.parse(_page);
    expect(apps.map((a) => a.id), ['com.spotify.music', 'com.soundcloud.android']);
    expect(apps[0].name, 'Spotify: Music and Podcasts');
    expect(apps[0].developer, 'Spotify AB');
    expect(apps[0].rating, 4.2);
    expect(apps[0].icon, 'https://play-lh.googleusercontent.com/AAA=s96-rw');
    expect(apps[1].name, 'SoundCloud & Friends'); // entities decoded
    expect(apps[1].icon, 'https://play-lh.googleusercontent.com/BBB=s96-rw'); // the icon, not the screenshot
    expect(apps[1].rating, 4.6);
  });

  test('a page without results (or a changed page) gives none', () {
    expect(PlaySearch.parse('<html><body>Nothing</body></html>'), isEmpty);
  });
}
