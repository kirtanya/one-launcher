# Handoff: One Launcher + One Stream (2026-10-28)

Start a new session with: "Read ~/one_launcher/docs/HANDOFF.md and continue."

## Projects
- **One Launcher**: ~/one_launcher (Flutter; phone + TV flavors). Repo: **github.com/kirtanya/one-launcher**
  (moved from kirtanyak-pe on 2026-10-24; origin repointed, push works).
- **One Stream**: ~/torrent_app (Kotlin, package com.kirtanya.reel). Rules in its CLAUDE.md (commit by path,
  never print tmdb.key, no P2P from the Mac).
- Devices:
  - Pixel 8 phone over wireless adb: mdns `adb-47041VDJH00305-CKMdTZ._adb-tls-connect._tcp` (or 192.168.1.10:<port>).
  - Acer R4 TV: `192.168.1.128:5555`. **TV: install only.** Never send keys or drive the UI.
  - adb lives at ~/Library/Android/sdk/platform-tools/adb.
- APKs always go in ~/Desktop/APKs.

## Shared working tree: careful
Another session has **uncommitted** pinned-shortcuts work in ~/one_launcher. Never commit or revert these:
- AndroidManifest.xml, MainActivity.kt, PinnedShortcuts.kt
- lib/apps.dart, lib/sheets.dart
- pubspec.yaml (1.38.0+5704)

Commit only your own paths:
`git -c user.name="Kirtanya K" -c user.email="kirtanya.k@peepal.co" commit -m "…" -- <paths>`

To build without their work, use a clean worktree of HEAD and copy in the gitignored files:
- android/key.properties, android/local.properties
- catalog_sources.txt, tmdb.key, omdb.key

## Keys (gitignored, never print)
- `tmdb.key` is a TMDB **v4 Bearer** token (v3 `api_key=` returns 401).
- `omdb.key` is OMDb, free tier, 1,000 requests/day.
- Both live in ~/one_launcher and ~/torrent_app.
- Builds pass them via `--dart-define`:
  - tool/build_tv.sh: always.
  - tool/build_release.sh: only the user's own phone build (one-launcher-phone.apk), never the share APKs.
- To share a TV build with friends, build it without keys (see "Done" below).

## Installed now
- **TV:** One Launcher TV 1.38.3+5709 (HEAD f3c0c74, with keys).
  - The other session sometimes installs higher version codes; bump above what's on the TV.
- **Phone:** One Launcher 1.38.0+5704: working tree, with keys.
- **Phone Download folder:** the friend APKs (OneLauncherTV-1.38.3-share.apk, OneLauncher-1.38.0.apk). Old APKs cleaned up.

## Done this session (all committed + pushed)
- **Today page (phone Tiles):**
  - weekly "Your day" schedule (slots repeat on chosen days)
  - richer day widget
  - hold-and-drag widget reorder, with a ⋯ menu
- **Phone TV-remote:** hold OK/Home/Back/Play/Input/Power sends a real long press (key down, then key up on release).
- **TV artwork:**
  - lib ArtFetch.kt loads media-session picture *links* (redirects, UA, HEIF/AVIF).
  - Tiles background "Focused artwork" (default): the focused item's art, blurred and dimmed.
  - JioHotstar shares only "S4 E9 <episode>", with no picture and no show name:
    - lib/tv/episode_art.dart: Wikidata ("episode of X") → Cinemeta series → exact S/E/name match → episode still.
    - Verified live on Prison Break.
  - Other apps' Watch Next / preview rows are **impossible** for us: ACCESS_ALL_EPG_DATA is signature|privileged (system launchers only).
- **Ratings + reviews:**
  - Launcher, TV and phone:
    - IMDb pill on posters.
    - Title page ratings row: IMDb · Rotten Tomatoes · Metacritic (OMDb).
    - Series: season tabs, episodes with per-episode IMDb.
    - TMDB reviews row and full review.
    - Mockup: docs/mockups/title_page.html.
  - One Stream: same feature committed as **0.11.0** (fac1bc1).
- **Share builds:** a TV APK with no keys and no catalog links. Friends get IMDb only.

## Open / next
1. **One Stream 0.11.0+ install:**
   - Not yet built or installed on phone + TV by this session. Check `git log` (later commits exist), build with its tool/build_release.sh, then install.
   - Look at its ScreenRenders first.
   - Note ~/torrent_app has another session's uncommitted "artmatch" work.
2. **Ratings, untested on devices** with real OMDb/TMDB answers. Ask the user how film and series pages look.
3. **Launcher gaps:**
   - OK on a TV episode card does nothing (no per-episode action exists).
   - TvOneStreamPage (One Stream's page inside the TV launcher) has no ratings or reviews yet.
   - Phone posters show the IMDb pill only for titles opened in the last 7 days.
4. **Phone remote, TV typing:** key-event fallback added earlier; the user never confirmed it works live.
5. **Smart home (parked):** Google Home APIs. The user still has to do the SDK + Cloud OAuth setup (see memory "one-launcher-smart-home-parked").
6. **Uncommitted leftovers:**
   - docs/mockups/ is untracked; commit it or ignore it.
   - Stale worktree: /private/tmp/.../scratchpad/os-release (prunable).

## User preferences (short)
- Responses short, ending with a TL;DR of 2–3 bullets.
- Work autonomously; confirm outward or irreversible actions.
- Mobile-first, 360 dp. Test both Classic and Tiles looks.
- Messages are voice-dictated: "TBD" = TMDB, "Streamio" = Stremio, "key research" = Kill Switch.
