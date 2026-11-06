# One Launcher — agent guide

For coding agents. Dense on purpose; read this before exploring. **Keep it current:** when you
add a feature, file, channel, pref or gotcha, update the matching section in the same change.

## What it is
Flutter Android launcher, two flavours from one codebase:
- **phone** (`lib/main.dart`, package `com.kirtanya.one_launcher`): home screen with 3 home views
  (= 3 design languages), app drawer, search, settings, TV remote, notification centre.
- **tv** (`lib/main_tv.dart`, `lib/tv/*`, Android `src/tv/`): Google TV launcher. Separate UI
  (`TvDS` in `lib/tv/tv_ds.dart`); shares prefs/palette code. Treat as its own app.
  Search (`tv/tv_search.dart`): left icon sidebar (All · One Stream · YouTube · Netflix · Prime Video · JioHotstar · Crunchyroll, installed ones only); All =
  a row per source, One Stream + YouTube first. YouTube via `tv/youtube_search.dart` (youtubei
  search endpoint, no key; POST through TvActivity "httpGet" with a body); opens in the YouTube TV app.
  **TV Customise = one page per thing** (`tv_settings.dart` tvSections: Background, Clock,
  Continue watching, Quick actions, Your apps, Jump back in, Streaming apps' rows, Cards & focus,
  Remote & behaviour; then Search, System). `tvSectionsFor(view)` keeps each view's own options;
  the home adds rows to a page via `TvExtras` (page name → actions; '' = Customise itself);
  Hold OK → "Customise …" opens that row's page (`showTvSection`).
  **Show details** (`tv/tv_title.dart`): pure black; backdrop faded by a page-local `_BlackFade`; ONE
  horizontal options line: One Stream logo first (+ "More in One Stream" pill), each other app as just
  its round logo (white ring on focus, RENT/BUY tag when WatchHub lists it only as rent/buy), then
  Trailer + Search everywhere pills; seasons/episodes, reviews, cast right below.
  **TV focus never scales** (user, 2026-10-31: scaling breaks the layout): show focus with an outline,
  fill or glow only. Backdrop Ken Burns zooms are fine.
  **Spotlight** (`tv/tv_spotlight.dart`, part of tv_home; homeView 'spotlight', shares Classic's
  look/prefs): pure black, focused item's picture full screen, title bottom-left (display only),
  one column on the right (Classic's content rows on their side; Your apps first, then Continue
  watching); ↑↓ in it, ←→ columns, ↑ top bar.
  **Google TV** (`tv/tv_google.dart`, part of tv_home; homeView 'googletv', own Customise pages via
  `tvSectionsFor` → `_googleReads`; reference scan in docs/GOOGLE_TV_VIEW.md + docs/google_tv_scan/):
  top bar = pill tabs (Home · Apps · One Stream) + Search / Settings icons + clock; hero carousel =
  Continue watching (max 2) + `Catalog.trending` (≤5 in all, auto-advance 12 s, not in the grid / reduced
  motion); focused it grows (description + "Watch on <app>" pill) and the apps slide down; "Your apps"
  = 5-col grid of 16:9 banners (no banner → icon/letter on a tvTint card), label under the focused
  tile only; in the grid the top bar hides and the grid moves row by row (200 ms). Focus = TvRing
  outline + glow, never scale (test checks the size). Focus labels 'gtv top <id>' / 'gtv hero' / 'gtv app <i>'.
  **Quick settings** (`tv/tv_quick_settings.dart` + `QuickSettings.kt`, Sony-style bottom band; OK
  grows a picker up out of the item, Back closes the picker, then the panel): opens from the Google TV
  Settings icon and from the remote's Settings key (KEYCODE_SETTINGS, caught in
  `TvActivity.dispatchKeyEvent` → channel "quickSettings": only while our activity is in front; no
  global hook). Only real things: volume/mute (STREAM_MUSIC; "Fixed" when CEC owns it), our sleep timer
  (AlarmManager → `SleepTimerReceiver`: screen off via `ShowNameService.sleep()` when that service is on,
  else the screensaver), screensaver now, inputs (TvInputManager passthrough), network, Bluetooth, and
  links shown only when they resolve to an exported, non-chooser activity (Display, Sound,
  Accessibility, Sony's SmartSettings). No brightness/picture mode (not settable by apps). Channel:
  qsState / qsVolume / qsMute / qsSleep / qsOpen; Menu stays "options" (OK-hold).
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
  **Backdrop picture** (`_Wide`, Cinematic + Spotlight): the whole picture, its own shape, as big as fits
  in 75% × 75% (top-left; posters / 4:3 / 21:9 never cropped) + flipped copies tiled out to fill; `_MirrorShade` darkens them 35%, clear at the picture's edge and
  full 7% of the width out; Spotlight's own shading at 95% (one layer, so the corner isn't darker). Mockup the user tuned:
  claude.ai/artifact/SJRv1UZt2X55XkkvCNqEs6.
  `io.flutter.embedding.android.ImpellerBackend=opengles` had no effect on Flutter 3.47.
  **Alexa** ("Alexa, ask One TV to search … / to open …"): skill in `alexa/` (Alexa-hosted; setup
  in alexa/README.md) posts to a secret ntfy.sh topic (`./alexa.topic`, gitignored, Gradle →
  `R.string.alexa_topic`; empty = off); `AlexaRelay.kt` streams that topic (started by TvActivity
  and ShowNameService, which keeps the process up) → search via TvActivity EXTRA_SEARCH, open =
  best label match (+ ALIASES). Search goes inside the named app ("… on YouTube") or the app on
  screen (`ShowNameService.onScreen`) when it really takes searches: only YouTube (search link) on
  this TV — Netflix closes on links, Prime ignores them, JioHotstar's ACTION_SEARCH drops the words
  (`IGNORES_WORDS`); those land in our search. Cold start: TvActivity holds EXTRA_SEARCH for Dart's `takeSearch` (the channel
  exists before Dart listens). Incoming searches hide the keyboard.
  **Remote's mic → our search** (`ShowNameService.takeVoiceSearch`, setting `remoteMic` ours|google):
  the mic still goes to Google; on any com.google.android.katniss event the service reads the results
  page's headline (`id/super_header` = what was said; a single title's page: `entity_row_header_title`) and opens our search on top (never Back: it
  hit our search on slow starts). Can't disable Google's search app: it does the speech-to-text.
  Hands off while Google's VoicePlateActivity listens. Missed presses (2026-10-31 logs) are the TV's:
  one press starts Google's voice twice — key 219 via the vendor's RtkKeyInterceptService and the
  remote's BLE PTT via AtvRemote. Same interactionId → works; two ids → the second closes the
  first's audio pipe ("Pipe was closed by the consumer") → "no recognized speech". Firmware race;
  batteries fine; no app can catch 219 (it never reaches accessibility key filters).
  `googleUntil` (set by TvActivity "searchEverywhere") leaves Google alone when we sent the user there.
  **TV voice key** (tested 2026-10-31, RC710): the remote's mic button never reaches apps — an
  accessibility key filter saw every other key but no 219/231/84; com.google.android.tv.remote.service
  opens Google search itself. In-app mic on the TV = phone-as-mic. Gboard's voice typing crashes that
  remote service ("Failed to register audio policy").
  TV build numbers run ahead of the phone's (TV had 5730 when the phone was 5709): check before installing.
  **TV keyboard** (1.47.0, `android/app/src/tv/kotlin/.../keyboard/`): a system keyboard (IME) for every
  app, chosen by the user in Settings → System → Keyboard. Native Canvas view, own process `:keyboard`
  (no Flutter engine: every app's text field binds it). A small solid panel (#21242C, keys #353641) flush in the
  bottom-right corner; it reports no insets, so the app keeps its full screen. `KeyGrid` = alphabetical 6×5 square keys (123/abc
  ends the bottom row); right column = Delete over the top two rows, Space over the bottom three, so
  Left/Right off any row's edge reach one; below, a full-width Done bar (icon + the app's label, "Search"). No Shift (lowercase only). Focus starts on "o", all
  four directions wrap (through the strip). `Suggest` = strip above: typed history (prefs "keyboard",
  never from password fields) → One Stream continue/watchlist titles → popular films + shows (Cinemeta
  "top", ~700, prefs, refetched daily) → One Stream `/search` (2+ letters, 300 ms debounce) → app names;
  ranked exact title → starts with → word starts with. A suggestion replaces the whole field. The same
  candidates outline the 3 likeliest next keys (`Suggest.nextKeys`).
  Netflix / YouTube / Prime draw their own keyboards, so it never shows there.
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

## Architecture: one system, four languages
`prefs.homeView` ∈ `classic` | `tiles` | `third` (UI name **Real**) | `pixel` → `DesignLanguage`
(`lib/ui/ds.dart`) → `DS.lang`, read through `DS.metro` / `DS.third` / `DS.pixel`.

**Pixel view** (`lib/pixel/`, spec + file map in `docs/PIXEL_VIEW.md`): Pixel Launcher end to end
(grid pages, dock, At a Glance, search pill, swipe-up drawer, anchored icon popup, drag-to-folder)
plus more settings. Uses Classic's Material You palette (`DesignLanguage.pixel`); no glass setting (its
frosted drawer/menu/folder surfaces copy Pixel's). Its Home settings page also switches the home view. Its
own data: `prefs.pixelSettings` / `prefs.pixelLayout` (JSON; `PixelSettings` / `PixelLayout` in
`pixel_model.dart`); icons through `PixelIcon` (shape clip). Shared features (hidden apps, App
lock gate, themed icons, Today panel, search) are reused, not copied.

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
  Nav order: Now · Home · Smart home · Search (no Settings or Notifications tab: long-press Home opens Settings,
  which rises from the bottom with Back at the top: `_openTab(rise: true)` → `TabPageHost.rise`). Now = the top
  Today panel (`_openNow` → `_toPanel(0)`; only with the panel on; `_syncNowTab` lights Now/Home as the pager moves).
  Home ↔ Smart home is one pager: `_HomePagerPhysics` hands a drag past home's last page to `_pullNext`, which
  presents Smart home held (`_holding`/`_held`) and sets its motion + `_backdrop` from the finger; `_letGo` settles.
  Tab pages and home's content slide a full width (`_homeSide`, `_homeAway`); controllers animate with curves and
  their values are positions, so a finger can take over mid-way. The backdrop darkens with `_homeAway`.
  The dock sits above the Today pager (not in home's page), so the nav shows on the panel too; the panel gets its height as bottom padding.
  `_onPagesScroll` (around the home pager): vertical scrolling sets `SearchDock.shrunk` (tabs 56 → 48, icons
  unchanged; back at the top / on tab change). Horizontal swipes walk `_swipeOrder` (Today ← Home ↔ Smart home ↔
  Search; Settings counts as Home, the remote as Smart home) via `_swipeNav`: the Today pager takes them on home,
  elsewhere `_onDragUpdate`/`_onDragEnd` (the open page follows the finger via `_dragX`, rubber-bands at the ends).
  Backdrops stay still and fade while content slides (like NowStage): `_backdrop` (DS.base under tab pages, whose
  `_TabPageBody` is transparent) and the Today panel's (`todayBackdrop`, `TodayPanel(backdrop: false)`, follows `_panel.page`).
- `app_drawer.dart`: the sheet's list: hero card (pinned + most used), folders, search results
  (`_SearchResults`, `searchResults()`), pull veil (fade via a sheet-coloured overlay, not
  Opacity), `_PullPill`.
- `search_dock.dart`: bottom nav (`_NavBar`, `_NavButton`; dock 64, tabs `big` 56 / `small` 48), nav→search morph (`_NavSearch`),
  `_surface()`. `search_history.dart`: recent searches (card for top bar; `RecentSearchPills`
  above the bottom bar). Once something is typed, `SearchFilterPills` (same file;
  `SearchFilter` All · Apps · Movies & shows · Web/Google · Other = shortcuts + phone settings) take the recent pills' place (home.dart
  draws them above the bar; the drawer draws them under a top bar); single-select, **Apps by default**, reset to Apps whenever the
  query empties (`_syncPills`); `_filter` lives in home.dart, flows via `AppDrawer.filter/onFilter` into `_SearchResults.filter`
  (`searchResults()` for Tiles stays All). Tests: `test/search_filter_test.dart`; tests that need the web rows / long list tap
  `filter:all` first. `google_suggest.dart`: Google autocomplete (follows "Search Google").
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
  Its player matches the Now playing card: app badge + output button on top, title + tonal play pill (colours from
  `coverScheme` in pages.dart; `SteadyPlaying` holds "playing" through the brief pause between tracks), ⏮ `WavySeekBar` ⏭ + the app's actions (`h >= 190`, by height only so it never blinks between tracks; shorter folds ⏮ ⏭ beside the pill).
  The quick chips slide down under the sheet's edge on the Now page (`nowAway`, clipped there) and `_TopArea` hands their room to the carousel.
- `top/pages.dart` **NowPlayingPage** (the Now playing top card) follows Android's media controls: the cover under a
  tint of its own `ColorScheme.fromImageProvider` colours, app badge + output button (`Apps.mediaOutput`) on top when
  `h >= 172`, title + a tonal play pill, and ⏮ `WavySeekBar` ⏭ plus up to 2 of the app's custom actions (`mediaAction`)
  when `h >= 100`; shorter collapses to one row. `WavySeekBar`'s wave moves while playing (never settles; tests pump time,
  not `pumpAndSettle`) and seeks via `mediaSeek` when the state's `canSeek`. MediaWatcher adds `canSeek`/`actions` to the state.
- **Caffeine** chip `b:caffeine` (`caffeine.dart`; also Tiles' chips row / action tile via `runQuickAction`): tap switches
  Off ↔ the chosen level (`Caffeine.choice`, prefs `caffeineChoice`: 5 min / 10 min / Keep awake = `Integer.MAX_VALUE`, default
  Keep awake) by writing `Settings.System.SCREEN_OFF_TIMEOUT`; long-press (home chips only) = menu to pick the level (turns it on).
  While on, the icon is `Caffeine.glyph`: the minutes ("5"/"10") or an eye for Keep awake, in every chip look incl. icon-only. Needs WRITE_SETTINGS ("Modify system settings"; snackbar → `openWriteSettings`). The phone's own timeout is
  saved in prefs `caffeineOriginal` on first turn-on and put back on Off; a timeout changed elsewhere counts as Off.
  Channel methods (in `QuickActions.kt`): `caffeineState` {canWrite, timeout}, `setScreenTimeout` {ms}, `openWriteSettings`.
- `quick_chips.dart` (chips row + look), `quick_actions.dart`, `folders.dart`, `search.dart`,
  `system_settings.dart`, `photo_wallpaper.dart`, `one_stream*.dart` (One Stream integration),
  `top/` (top carousel pages, clock fonts), `tiles/` (Tiles/Metro home, today panel, landing).
- `smart_home.dart` (model + `SmartHome` service, channel `one_launcher/home`, contract in its header) · `smart_home_sheet.dart` (sheet, detail, room, home picker, setup card) · `quick_lights.dart` · `top/smart_home_page.dart`.
  Entry points: the nav's Smart home tab (id `smart`, took the Remote tab's place, same `remoteButton` pref; the TV remote is
  its first tile, and the bulb stays lit on the remote), chip `b:home` (also Tiles `qa:b:home`), top page `smart_home`.
  Lights: colour (Google `ExtendedColorControl.moveToColorHsv`, fallback Matter hue/sat), warmth (Matter mireds ↔ K),
  sleep/wake (`LightEffects`); rooms have All on/off, and tapping a room name opens its lights as one (`SmartDetail.room`).
  Homes: bridge `homes` + device `homeId`; the sheet's home chips pick one (saved `smartHome.home`), "Add a home" = `connect(force: true)`
  (re-opens Google's share screen). `quick_lights.dart` (`QuickLights`): chips All / each light (its dot = on/off) / each room, power,
  brightness bar (tinted with the lights' colour; not a `Slider`), colour. `full: null` = fits its height (full / compact: colour and
  brightness buttons swap in for the chips / header only). Used on the top page (dark card, auto), the side panel kind `smart`,
  the top of the Smart home sheet (`_QuickLightsCard`) and search's empty state above the recent pills (gone at once on typing).
  Commands: one per device+trait in flight, only the newest waits (`SmartHome.set`); sent values stay on top of device updates
  until 4 s after they finish, so stale echoes don't snap the UI back. Bridge logs `set <trait> took N ms` (tag SmartHome). The SDK needs coroutines ≥ 1.11.0 (calls static `Mutex.unlock$default`; 1.8.0 crash-loops), pinned for phone.
  Kotlin bridge: `android/app/src/phone/kotlin/.../SmartHomeBridge.kt` (+ `HomeConnectActivity`, runs the permission flow; manifest in `src/phone/`), phone flavour only, Google Home APIs SDK 17.1.0
  from the local maven repo `android/home-sdk/` (190 MB, gitignored; repo + `phoneImplementation` deps only added when it exists, else the phone builds without the bridge → status unavailable).
  MainActivity attaches it reflectively (`Class.forName(...SmartHomeBridge).attach`; keep rule in `app/proguard-rules.pro`). Matter units: setpoints 0.01 °C, level 0..254. Debug: long-press the setup card = fake devices.
  Reachability: the bridge sends `reach` (offline when the device OR its OnOff/Thermostat trait's `metadata.sourceConnectivity`
  is OFFLINE; `unknown` when neither knows) and `online = reach != "offline"` → "Offline", dimmed, cloud-off mark, controls off.
  A command that throws or gets no answer in `SmartHome.answerIn` (10 s) marks the device `noReply` → "Not responding" in the
  error colour with an alert mark, controls stay on; cleared by the next command that goes through, or after 3 min.
- **App long-press menu** (`showAppActions` in sheets.dart, both views): main actions are horizontal pills (icon + label),
  two per row, an odd last one full width; then shortcuts (first 4 + Show all).
- **App lock** (`app_lock.dart` gate, `app_lock_ui.dart` PIN pad + settings page): prefs `lockedApps`, `lockTaps` (2|3), `lockPinHash`
  (`salt:sha256`, own SHA-256, no package:crypto). `AppLock.of(prefs).gate(pkg)` is called FIRST in `home.dart _launch` (sheet, search,
  folders, dock, favourites), `tiles_home.dart _launch`/`_launchFromStart`, `SmartHome.openGoogleHome`; a locked app's taps are swallowed
  (light haptic, `clearLaunchFrom`, toast "App not supported" via channel `toast`, no animation / recordLaunch) until the Nth tap within 350 ms, then `lockAllow` + launch.
  Channel (native half): `setLockedApps {packages}` (startup in main + every change), `lockAllow {package}`, `lockServiceOn`.
  Payment apps (bank/UPI; Paytm's NPCI PIN pad) refuse while ANY sideloaded accessibility service is on (even one
  listening to no events — tried in 1.47.58), so (1.47.59) App lock uses NO accessibility: `LockService.kt` is a
  foreground service (type specialUse, MIN-importance "App lock is on" notification) started by `LockService.sync`
  (AppLockGuard.setLocked + MainActivity.onStart) while apps are locked AND Usage access is granted. It polls
  `UsageStatsManager.queryEvents` every 500 ms (screen on only) for the last ACTIVITY_RESUMED and sends a locked,
  un-allowed app home with a HOME intent (background start allowed: we are the home app) + toast "App not supported"
  (deliberately vague). `lockServiceOn` = Usage access granted. Native: `AppLockGuard.kt` (locked set in prefs
  `app_lock`/`packages`, 5 s allowance after `lockAllow`).
  "Reopen without lock" (prefs `lockGrace` 0|5|10 s, phone-only, PIN to change, `AppLock.setGrace`): channel
  `setLockGrace {seconds}` (also sent by `sync`) → `AppLockGuard.graceMs` (prefs `app_lock`/`graceMs`). When an
  allowed app's allowance ends (user left it), `left[pkg]` is stamped; within graceMs `isAllowed` re-allows it
  (recents / notification) and Dart `gate` asks `lockRecent {package}` so one tap opens it.
  UI: only Settings → Apps → App lock (`showAppLockPage`; Usage access row, double/triple, Reopen without lock Off/5 s/10 s, change PIN, app switches); NOT in the
  long-press menu (user's call). Unlock / off / tap-count change ask the PIN (`askPin`); first lock sets it (`ensurePin`).
  `lockedApps` + `lockPinHash` are phone-only: not exported, kept across a backup restore. Tests: `test/app_lock_test.dart`.
- `prefs.dart`: every setting. `perView` keys are stored per home view (`tiles.<k>`, `third.<k>`).
- `apps.dart`: the main platform channel `one_launcher/apps` (apps, icons, launching,
  shortcuts, widgets, notification counts, settings intents…).

## Android (phone, `android/app/src/main/kotlin/com/kirtanya/one_launcher/`)
`MainActivity.kt` (channel `one_launcher/apps`; also attaches `NotificationFeed`),
`MediaListener.kt` (NotificationListenerService: badges, media, `onAny` → feed),
`NotificationFeed.kt` (channel `one_launcher/notifications`: list/open/action/reply/dismiss/snooze),
`TvRemote.kt`, `RemoteNotification.kt` (remote in shade + QS tile), `NowPlayingServer.kt`,
`WidgetHost.kt`, `QuickActions.kt`, `LockService.kt`, `OneStream.kt`, `BackupFiles.kt`.
**App icon** = the shared "One" family, "Glass O, centred" (green, 2×2 grid): source `~/one-logos`
(`make.sh` regenerates). Adaptive layers are bitmaps in `res/mipmap-*` (`ic_launcher_bg` / `_foreground` /
`_monochrome`, plus legacy `ic_launcher`), TV banner `src/tv/res/drawable-xhdpi/tv_banner.png` (640×360),
`docs/app_icon.png`. `tool/make_icon.py` (old "1" mark) is retired; don't run it.

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
