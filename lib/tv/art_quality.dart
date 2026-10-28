import 'tv_settings.dart';

/// Customise → Home screen → Picture quality: how sharp the full-screen picture is. The TV draws
/// 1920 px wide; pictures used to arrive at 780 and be cut to 960, then stretched 2×.
///
/// - Standard: 780-wide sources, kept at 960 (lightest).
/// - High (default): 1280-wide sources, kept at 1280 (TMDB's own TV-background size).
/// - Best: full-size sources (up to 4K), cut to 1920 on the TV (sharpest; heavier to fetch and
///   decode on this 32-bit TV).
class ArtQuality {
  ArtQuality._();

  static const levels = [('standard', 'Standard'), ('high', 'High'), ('best', 'Best (full size)')];

  static String get level => TvLook.str('artQuality');

  /// The widest a full-screen picture is kept (the TV decodes it to at most this).
  static int get width => widthFor(level);

  static int widthFor(String level) => switch (level) {
    'standard' => 960,
    'best' => 1920,
    _ => 1280,
  };

  /// [url] asking its host for the size [level] wants: TMDB (`image.tmdb.org/t/p/{size}/…`),
  /// Metahub episode stills (…/w780.jpg) and Metahub show backgrounds (background/medium|large).
  /// Anything else is left as it is.
  static String url(String url, [String? level]) {
    final l = level ?? ArtQuality.level;
    final tmdb = switch (l) {
      'standard' => 'w780',
      'best' => 'original',
      _ => 'w1280',
    };
    final episode = RegExp(r'^(https://episodes\.metahub\.space/.+/)(?:w\d+|original)\.jpg$');
    if (episode.hasMatch(url)) return url.replaceFirstMapped(episode, (m) => '${m[1]}$tmdb.jpg');
    final tmdbImg = RegExp(r'^(https://image\.tmdb\.org/t/p/)(?:w\d+|original)(/.+)$');
    if (tmdbImg.hasMatch(url)) return url.replaceFirstMapped(tmdbImg, (m) => '${m[1]}$tmdb${m[2]}');
    final background = RegExp(r'^(https://images\.metahub\.space/background/)(?:small|medium|large)(/.+)$');
    if (background.hasMatch(url)) return url.replaceFirstMapped(background, (m) => '${m[1]}${l == 'best' ? 'large' : 'medium'}${m[2]}');
    return url;
  }
}
