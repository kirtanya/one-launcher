# One Launcher — agent guide

For coding agents. Dense on purpose; read this before exploring. **Keep it current:** when you
add a feature, file, channel, pref or gotcha, update the matching section in the same change.

## What it is
Flutter Android launcher, two flavours from one codebase:
- **phone** (`lib/main.dart`, package `com.kirtanya.one_launcher`): home screen with 3 home views
  (= 3 design languages), app drawer, search, settings, TV remote, notification centre.
- **tv** (`lib/main_tv.dart`, `lib/tv/*`, Android `src/tv/`): Google TV launcher. Separate UI
  (`TvDS` in `lib/tv/tv_ds.dart`); shares prefs/palette code. Treat as its own app.
  Search (`tv/tv_search.dart`): filter chips (All · One Stream · YouTube · services · Apps); All =
  a row per source, One Stream + YouTube first. YouTube via `tv/youtube_search.dart` (youtubei
  search endpoint, no key; POST through TvActivity "httpGet" with a body); opens in the YouTube TV app.
  **TV Customise = one page per thing** (`tv_settings.dart` tvSections: Background, Clock,
  Continue watching, Quick actions, Your apps, Jump back in, Streaming apps' rows, Cards & focus,
  Remote & behaviour; then Search, System). `tvSectionsFor(view)` keeps each view's own options;
  the home adds rows to a page via `TvExtras` (page name → actions; '' = Customise itself);
  Hold OK → "Customise …" opens that row's page (`showTvSection`).
  **TV focus never scales** (user, 2026-10-31: scaling breaks the layout): show focus with an outline,
  fill or glow only. Backdrop Ken Burns zooms are fine.
  **Spotlight** (`tv/tv_spotlight.dart`, part of tv_home; homeView 'spotlight', shares Classic's
  look/prefs): pure black, focused item's picture full screen, title bottom-left (display only),
  one column on the right (Classic's content rows on their side); ↑↓ in it, ←→ columns, ↑ top bar.
  Debug on the TV (hot reload, data kept): debug builds are signed with the release key, so
  `flutter build apk --debug --flavor tv -t lib/main_tv.dart --build-number=<above installed>` →
  `adb install -r` (never let flutter install: a failed install uninstalls = data wiped) →
  start the app → `flutter attach -d <tv> --app-id com.kirtanya.one_launcher.tv -t lib/main_tv.dart
  --pid-file <f>` (flutter run can't read the TV launcher activity). If attach keeps losing the
  TV, pass `--debug-url` from logcat's "Dart VM service is listening on". SIGUSR1 = hot reload,
  SIGUSR2 = hot restart.
  **TV performance** (Acer R4, Impeller/Vulkan; measured with SurfaceFlinger `--timestats`):
  nothing may animate while idle — the old 26 s Ken Burns drift redrew the full-screen backdrop
  at ~22 fps (26% CPU) idle; now a 1.8 s settle then still (idle ~2 fps, ~8% CPU). Backdrop
  crossfade 350 ms, `FilterQuality.low`, opacity on the Image (no `Opacity` layer), image cache
  48 MB / 80, media updates rebuild the home only when more than the position changed.
  `io.flutter.embedding.android.ImpellerBackend=opengles` had no effect on Flutter 3.47.
  TV build numbers run ahead of the phone's (TV had 5730 when the phone was 5709): check before installing.
Companion apps elsewhere: One Stream (`~/torrent_app`), One Watch (`~/one_watch`).

## Build · install · test (phone)
- Another session may have **uncommitted WIP** in this checkout (recently: `lib/apps.dart`,
  `lib/sheets.dart` showAppSheet hunk, `MainActivity.kt`, `AndroidManifest.xml`,
  `PinnedShortcuts.kt`, `pubspec.yaml`). Never revert or commit their hunks. Build from a clean
  worktree with your files copied in (strip their hunks), or stage only your hunks
  (`git hash-object -w` + `git update-index --cacheinfo`).
- Release build: `flutter build apk --release --flavor phone --split-debug-info=symbols --obfuscate
  --target-platform android-arm64 --build-name=<x> --build-number=<installed>` plus
  `--dart-define=OMDB_KEY/TMDB_TOKEN` from `omdb.key` / `tmdb.key` (gitignored; never print).
  The installed build number must be ≥ the phone's or install fails (downgrade).
- `tool/build_release.sh` makes share APKs (no keys) → `~/Desktop/APKs`.
- Device: `~/Library/Android/sdk/platform-tools/adb`, phone serial contains `47041VDJH00305`
  (wireless: `adb-47041VDJH00305-…_adb-tls-connect._tcp`); TV `192.168.1.128:5555`.
- Check lock first: `dumpsys window | grep mDreamingLockscreen` (true = locked → ask to unlock).
- Visual checks: `adb exec-out screencap -p`, `screenrecord` + frame extraction
  (`/private/tmp/claude-502/rec/frames.swift`, `montage.swift`). screenrecord's t=0 is the
  first changed frame.
- **TV: install only**; never send keys or drive it unless asked. On the phone remote page,
  don't press buttons while a TV is connected.
- Commits: only when the user says so; by path; identity `-c user.name="Kirtanya K"
  -c user.email="kirtanya.k@peepal.co"`.

## Architecture: one system, three languages
`prefs.homeView` ∈ `classic` | `tiles` | `third` (UI name **Real**) → `DesignLanguage`
(`lib/ui/ds.dart`) → `DS.lang`, read through `DS.metro` / `DS.third`.

`OneTheme._apply` (`lib/ui/theme.dart`) runs on every pref change. It sets `DS.lang`,
`DS.palette` (Classic: Material You scheme → `OnePalette.fromSchemes`; Tiles:
`OnePalette.metro(accent)`; Real: `Tactile.palette(...)`) and `forceDark` (Remote tab). The
cache key must include every input, or changes won't apply.

**Rule: screens never hard-code a look.** They ask for a role and the language draws it:
| Layer | Where | Use |
|---|---|---|
| Colour roles | `OnePalette` (`ui/palette.dart`): canvas, sheet, base, card, cardMuted, hero, heroInk, ink, inkMuted, inkFaint, hairline | `DS.card`, `DS.ink`… never raw colours |
| Type | `DS.title/eyebrow/rowTitle/rowSub/meta/pill/iconLabel`, `DS.face` (per-language font), `DS.cased()` (Metro lower / Real UPPER) | Never `fontFamily: DS.font` in shared UI (it's the const Classic font, kept for const/TV code) |
| Surfaces | `RoleSurface(role: raised/key/recessed, color:, shape:)` (`ui/components.dart`), `OneCard` | Instead of `Material(color: …)` |
| Stock widgets | `ThemeData` in `main.dart`: per-language input fields, filled buttons, menus, switches, tooltips, sliders (Real: faders), progress, dividers, snackbars, dialogs; `splashFactory` (Real: none) | Use stock widgets; the theme restyles them |
| Shared components | `widgets.dart` (sheets, `SheetHeader`, `SheetSearchField`, `AppIcon`), `sheets.dart` (`_Group`, `_NavRow`, `_SwitchRow`, `_ChoiceRow`, `_Chip`, `_IconDisc`), `search_dock.dart` (nav + search bar morph), `components.dart` (`OneCard`, `CircleButton`, `Pressable`) | Each branches on `DS.metro` / `DS.third` internally |
Docs: `docs/DESIGN_LANGUAGES.md`, `docs/DESIGN_STYLE.md` (Classic),
`docs/TACTILE_LANGUAGE.md` (Real), `docs/tactile/specimen.html` (interactive Real pattern library).

### Real (Tactile)
- `lib/third/tactile/tactile.dart`: finishes (porcelain/concrete/graphite), lightness, light
  (LED colour), cap; depth recipes (`raised`, `plateShadow`, `proud`); `WellPainter` (inner
  shadows); type (`faces`, `font`, `legendFont`, `monoFont`, `emboss`); `TactileFeel`
  (haptics + click, throttled); `Tactile.palette()` maps roles (theme colour = light only).
- `parts.dart`: `TPlate`, `TWell`, `TTray`, `TKey` (travel on touch-down, latched + LED),
  `TSwitch`, `TLed`, `TLcd`, `DotMatrix` (own 5×7 glyph table; keep every glyph 35 chars),
  `TKnob`, `TKnobRow`, `tactileSliderTheme()`.
- `tactile_settings.dart`: Settings → Look → Real style (finish, type, light, cap, lightness,
  clicks). Prefs: `tactileFinish/Face/Light/Cap/Lightness/Sounds` (global, not per-view).
- Fonts: `assets/fonts/tactile/*` (Barlow Semi Condensed default, Chakra Petch, Space Grotesk,
  IBM Plex Mono, Space Mono for readouts); registered in `pubspec.yaml` as `Tactile*`.
- `lib/third/third_home.dart`: the Real home (hosts Classic's `HomeScreen` layout for now).
- **Real on TV** (`homeView = 'third'` on the TV too; Customise → Home view → Real), an old TV
  set: `lib/tv/tv_real.dart` (`CrtGlass` overlay from `main_tv.dart`'s builder: scanlines,
  vignette, rounded tube; `TvReal.panel/key/paintRing/legend`). `TvDS` text styles are getters
  on `DS.face` with an emboss in Real; `TvDS.surface / surfaceFocused / onLight` switch to key
  colours, so every chip, pill and button follows. Sounds: `TvApps.sound('tick'|'clunk'|'thunk')`
  → `TvActivity` SoundPool (`android/app/src/tv/res/raw/real_*.wav`); focus moves tick, OK
  clunks (`tv_focus.dart`), Back thunks (`main_tv.dart` key handler).
- No glass in Real (`main.dart` `_themedIcons` turns `Glass.classic` off).

## File map (phone)
- `main.dart`: app, `ThemeData` per language, glass/icon settings sync, home router by view.
- `home.dart`: Classic/Real home. Top area + app sheet (`DraggableScrollableSheet`), pull-to-search
  (`_pull`, `_reveal`, `_onPull/_onPullEnd`), search state (`_searching`, `_showResults`),
  tab pages under the nav (`_TabPage`, `_presentPage`, `_openTab`, `_navOrder`), status-bar style.
- `app_drawer.dart`: the sheet's list: hero card (pinned + most used), folders, search results
  (`_SearchResults`, `searchResults()`), pull veil (fade via a sheet-coloured overlay, not
  Opacity), `_PullPill`.
- `search_dock.dart`: bottom nav (`_NavBar`, `_NavButton`), nav→search morph (`_NavSearch`),
  `_surface()`. `search_history.dart`: recent searches (card for top bar; `RecentSearchPills`
  above the bottom bar). `google_suggest.dart`: Google autocomplete (follows "Search Google").
- `sheets.dart`: all Settings. `showSettingsSheet` → `settingsNow()` (`_Setting` list with
  category + group), `_CategoryGrid`, `openCategory`. Editors: `showEditor` (live home preview),
  `_HomeEditor` (Home view tabs), wallpaper, layout, clock style, chips, top widgets, today panel.
  **Add a setting:** add a `_Setting(category, group, …)` in `settingsNow()`; inline switch /
  choice / action, or `open:` a page only for editors and long lists. One home per setting.
- `widgets.dart`: `showOneSheetWith` (sheets, paged sheets via `SheetHost`, **tab pages** via
  `TabPageHost.arm` → rendered in home under the nav), `SheetHeader`, `SheetSearchField`, `AppIcon`.
- `remote_sheet.dart`: TV remote page (setup, groups: now/dpad/nav/media/volume/brightness/apps,
  `_Dial` in Real, `_DPad` else). `tv_remote.dart`: remote protocol (pairing, keys, IME, volume).
- `notifications/`: `notification_center.dart` (model, `NotifTier` priority rules, channel),
  `notifications_page.dart` (centre UI; temporary bell tab). Work-profile notifications are
  blocked by the org's policy (`permittedNotificationListeners=[]`); don't try to bypass it.
- `top/now_page.dart`: the **Now page**, always page 0 of the top carousel (home opens on page 1).
  Reads the system from notifications (music via `Apps.media` for now); `NowStage` in home hides the
  wallpaper edge to edge (the cover art itself, no thumbnail) and dissolves with `nowAway`. Its tune button sets
  darkness/blur (`Prefs.nowDim`/`nowBlur`); phone art is 1024² JPEG (MediaWatcher fetches the full cover when the attached one is small). Future: alarms, events.
- `quick_chips.dart` (chips row + look), `quick_actions.dart`, `folders.dart`, `search.dart`,
  `system_settings.dart`, `photo_wallpaper.dart`, `one_stream*.dart` (One Stream integration),
  `top/` (top carousel pages, clock fonts), `tiles/` (Tiles/Metro home, today panel, landing).
- `prefs.dart`: every setting. `perView` keys are stored per home view (`tiles.<k>`, `third.<k>`).
- `apps.dart`: the main platform channel `one_launcher/apps` (apps, icons, launching,
  shortcuts, widgets, notification counts, settings intents…).

## Android (phone, `android/app/src/main/kotlin/com/kirtanya/one_launcher/`)
`MainActivity.kt` (channel `one_launcher/apps`; also attaches `NotificationFeed`),
`MediaListener.kt` (NotificationListenerService: badges, media, `onAny` → feed),
`NotificationFeed.kt` (channel `one_launcher/notifications`: list/open/action/reply/dismiss/snooze),
`TvRemote.kt`, `RemoteNotification.kt` (remote in shade + QS tile), `NowPlayingServer.kt`,
`WidgetHost.kt`, `QuickActions.kt`, `LockService.kt`, `OneStream.kt`, `BackupFiles.kt`.

## Gotchas (learned the hard way)
- Opacity over a large subtree didn't render its middle frames on the phone. Fade solid content
  with an overlay of the background colour (see `app_drawer.dart` veil).
- `DS.font` must stay const (TV and Tiles use it in const styles); per-language font is `DS.face`.
- Nested `Navigator` in sheets/tab pages: close via `SheetHost.close(context)` (handles tab
  pages), not `Navigator.pop` on the root.
- Sheet height and keyboard: tab pages pad by `_NavInset`; content runs under the nav.
- Haptics: Real parts use `TactileFeel`; elsewhere `HapticFeedback.*`.
- A widget's explicit `style:` / `color:` beats the theme. For stock buttons, pass
  `style: DS.third ? null : …` so Real's theme applies; for surfaces use `RoleSurface`.
- A phone build without `PinShortcutActivity` (CONFIRM_PIN_SHORTCUT, in `AndroidManifest.xml` +
  `PinnedShortcuts.kt`) makes Chrome hide "Add to Home screen" / "Install app" while One Launcher is
  the home app. Never install a build that lacks it.
- Wide `dart format` reformats other sessions' code: format only your own files.
- Work laptop: network goes through a corporate proxy; downloads work (Google Fonts CSS API),
  raw.githubusercontent can 502.
