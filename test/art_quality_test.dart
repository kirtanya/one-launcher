import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/tv/art_quality.dart';

void main() {
  test('Picture quality asks each host for the right size', () {
    const still = 'https://episodes.metahub.space/tt23112594/1/5/w780.jpg';
    expect(ArtQuality.url(still, 'standard'), still);
    expect(ArtQuality.url(still, 'high'), 'https://episodes.metahub.space/tt23112594/1/5/w1280.jpg');
    expect(ArtQuality.url(still, 'best'), 'https://episodes.metahub.space/tt23112594/1/5/original.jpg');

    const trending = 'https://image.tmdb.org/t/p/w1280/abc.jpg';
    expect(ArtQuality.url(trending, 'standard'), 'https://image.tmdb.org/t/p/w780/abc.jpg');
    expect(ArtQuality.url(trending, 'best'), 'https://image.tmdb.org/t/p/original/abc.jpg');

    const backdrop = 'https://images.metahub.space/background/medium/tt0455275/img';
    expect(ArtQuality.url(backdrop, 'high'), backdrop);
    expect(ArtQuality.url(backdrop, 'best'), 'https://images.metahub.space/background/large/tt0455275/img');

    const other = 'content://android.media.tv/preview/1';
    expect(ArtQuality.url(other, 'best'), other, reason: 'other hosts left alone');
    expect([for (final (l, _) in ArtQuality.levels) ArtQuality.widthFor(l)], [960, 1280, 1920]);
  });
}
