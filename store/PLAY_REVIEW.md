# Play Store review — what could block publishing (phone build 1.47.74 / 5845)

Checked against the built APK (target SDK 36, permissions below) and the code on branch
`play-store`. Version stays 1.47.74 (5845): pass it with `--build-name` / `--build-number`
(`tool/build_play.sh` reads pubspec, which says 1.37.3+5703 — too low, and pubspec isn't edited).

## What could have blocked publishing, and what the Play build does

| # | Feature | Why it was a risk | In the Play build (1.47.74) |
|---|---|---|---|
| 1 | **Play Store results in search** (`lib/play_search.dart`) | Scraped play.google.com; Google's terms forbid automated access to Google Play, and it sent typed text to Google undisclosed. | **Removed.** |
| 2 | **Mindful open** (`lib/app_lock_ui.dart`; background guard `LockService`) | The background guard needed `FOREGROUND_SERVICE_SPECIAL_USE` (a Play Console declaration + video) and usage-access polling, which gets "device abuse" scrutiny. | **Kept, without the background guard.** Chosen apps open only on a double / triple tap inside the launcher. No foreground service, no usage-access polling. |
| 3 | **Notification centre** (`NotificationFeed.kt`, `lib/notifications/`) | Reads full notification text; the store texts said content is never read. | **No way in from the app**, so nothing is read. The listener stays for music controls and badge counts, disclosed in permissions.md, the privacy policy and Data safety. |
| 4 | **Google search suggestions** (`lib/google_suggest.dart`) | Sent typed text to suggestqueries.google.com, undisclosed. | **Removed.** |
| 5 | **Smart home** (Google Home APIs, `android/home-sdk`) | Home APIs need Google's approval and a verified OAuth consent screen before public use. | **Removed** (Home SDK not linked). The dock tab is "Remote" and opens the TV remote. Add back once the Home APIs project is approved. |
| 6 | **One Stream rows** (`com.kirtanya.reel` query, `lib/one_stream*.dart`) | Links to a sideloaded streaming app: IP-policy risk if a reviewer finds it. | **Removed** (query and rows). |
| 7 | **Critics' ratings** (OMDb / TMDB, `lib/ratings.dart`) | Network calls with built-in keys, undisclosed. | **Off:** `build_play.sh` doesn't pass the keys. |
| 8 | **Data safety + privacy policy** | Written for an app with no network use. | **Rewritten** to match this build. The privacy policy needs a public URL (GitHub Pages on the public repo). |

## Fine as is

- Home app (HOME intent), `<queries>` for launcher apps only (no QUERY_ALL_PACKAGES) — good.
- Usage access, Calendar, Set alarm, Expand status bar, Request uninstall, Write settings
  (Caffeine, user grants it in system settings), Post notifications, App widgets, Pin shortcuts.
- TV remote (INTERNET, local Wi-Fi only) — already explained in permissions.md.
- No accessibility service, no SMS/call log/location/all-files. TV flavour stays off Play.
- Target SDK 36 meets Play's current requirement.

## Decided and built (1.47.74 / 5845)

`tool/build_play.sh 1.47.74 5845` → `PLAY_BUILD=true` (env, for Gradle) + `--dart-define=PLAY_BUILD=true`
(`lib/play_build.dart`). Checked in the merged manifest: no LockService, no FOREGROUND_SERVICE*, no
One Stream query, no Home SDK / HomeConnectActivity; signed with the One Launcher release key.

- **Dropped:** Play Store results (scraping), Google suggestions, Smart home (dock tab becomes
  "Remote", its sheet the TV remote), One Stream rows.
- **Mindful open** (all builds): chosen apps open only on a double / triple tap. In the Play build
  it works only inside the launcher: no background guard, so no Usage-access row,
  "Reopen without lock" or "Lock again when the screen locks".
- **Notification centre:** has no way in from the app, so nothing is read; the listener stays
  for music controls and badge counts (disclosed).
- permissions.md, data-safety.md, privacy-policy.html and listing.md rewritten to match.
