/// The Google Play build (`--dart-define=PLAY_BUILD=true`, tool/build_play.sh): leaves out what
/// Play's policies would question — Play Store results read from its web page, Google's typed
/// suggestions, Smart home (Google Home APIs, not approved for the public yet), One Stream, and
/// Mindful open's background guard (a special-use foreground service). See store/PLAY_REVIEW.md.
const playBuild = bool.fromEnvironment('PLAY_BUILD');
