# Google TV view + Quick settings panel — scan and spec

Scanned 2026-11-06 on the user's home TV: Sony BRAVIA VU3, Google TV launcher
(`com.google.android.apps.tv.launcherx`), **Apps only mode** on, 1920×1080 logical (3840×2160 panel).
Screenshots (1000 px wide): `docs/google_tv_scan/s_*.png`; layout dumps with exact bounds: `docs/google_tv_scan/*.xml`.
Full-size PNGs and screen recordings (`nav.mp4` = home navigation, `panel.mp4` = settings panel):
`~/Desktop/Claude/google_tv_scan/` (not in git; 37 MB).

The user likes: the clean home, the interactions and how the tiles move. Wants it as a NEW TV home view
(next to Classic / Spotlight / Real / Tiles …) plus our own **Quick settings panel** that works on any TV.

## Home (1920×1080 px; all numbers px in that space)

**Top bar** (y 68–148, left inset 116):
- Profile avatar circle 80 px. Then a pill tab group (Home | Sony): pill bg white ~12 %, the selected tab
  a lighter pill (light blue-grey bg, dark text when focused; when not focused the selected tab is just
  brighter text). Then a second pill with two round icon buttons 64 px (Screensaver, Notifications with a
  red badge).
- Right: "2:06 | Google TV" — clock + divider + wordmark, grey ~70 %, ~34 px.
- In our version: avatar → nothing or our logo; tabs → our pages (e.g. Home | Apps | One Stream);
  icons → Search, Notifications, Settings (opens the Quick settings panel).

**Hero carousel** (`s_home.png`, `s_focus_app1.png`): full-bleed backdrop picture of the current item,
dark gradient from the left and bottom so text reads. Left column at x 116:
provider logo (small, white), title (~72 px, light weight), "Just added • Reality game show" (~30 px),
5 page dots at right (x ≈ 1750, y ≈ 545). Auto-advances; ←→ moves when the hero is focused.
- Rest state (focus in top bar): hero text block sits mid-screen, "Your apps" row at y 655.
- Hero focused (`s_focus_app1.png`): hero grows — description (2 lines) + a white pill button
  "Watch on Zee5" appear, the apps row slides down to y 989 (only its top peeks out).
- Our data: One Stream / catalog items (TMDB backdrops) we already have — "Watch on <app>" opens it.

**Your apps grid** (`s_row2.png`): 5 columns, tile 300×247 incl. label space; the card itself
300×~150 (16:9 app **banner**, `PackageManager.getApplicationBanner`, fallback icon + label on a tinted
card like "My BRAVIA"/"TV" tiles), corner radius ~16, column gap 45, row gap 22.
- Focus: the grid scrolls so "Your apps" becomes a large title (~56 px) at the top and the hero is gone;
  focused tile gets a white outline + soft white glow and its **label appears under it** (only the
  focused one has a label). NOTE: Google TV also scales the focused tile ~1.1× — our rule is
  **TV focus never scales** (AGENTS.md); confirm with the user before scaling (default: outline + glow only).
- Movement: everything slides with a short ease (~200 ms); the page scrolls row by row keeping the
  focused row near the top third. A small "^" chevron at top centre when scrolled down.

## Quick settings panel (Sony "Quick Settings", `s_panel1/3/4.png`, `panel.mp4`)

Opens from the remote's Settings key (Sony scan code 596 → keycode 197 →
`com.sony.dtv.smartui/.settings.SmartSettingsActivity`). Over the current screen (not full screen):
- A dark band across the bottom ~25 % of the screen (bg ~#1A1A1A 95 %), "Quick Settings" title above it
  at left (x 38 @1000 w).
- One horizontal row of items, each a column: icon (~32 px) / name / current value in blue
  (e.g. Picture mode → Custom, Brightness → 15, Speakers → TV speakers, Network → Minato) or a blue
  "open" arrow for items that open a full page.
- First item "Settings" (gear + round blue button) opens full Settings.
- Focus = a lighter grey column. OK on a value item opens a small vertical **picker that grows up out
  of the column** (e.g. Wide mode: Full / Full pixel / Zoom / 14:9), ↑↓ changes it live. Disabled
  items are dimmed (toast "Feature not available.").
- Sony's items in order: Settings · Picture settings · Picture mode · Brightness · Auto picture mode ·
  Wide mode · Sound settings · Speakers · Network · Bluetooth · Sleep timer · Timer · Alarm ·
  Power on behavior · Audio system · Eco Dashboard · Picture Off.
- BACK closes it.

### What we can do on ANY Android TV (no vendor APIs)
- Works: Volume (AudioManager, live), Mute, Sleep timer (our own timer; at the end go home + screen off
  via the existing accessibility service `ShowNameService` GLOBAL_ACTION_LOCK_SCREEN, or a "Sleep"
  intent), Screensaver now (`Intent("android.intent.action.MAIN").setClassName("com.android.systemui",
  "com.android.systemui.Somnambulator")`), Inputs / HDMI (TvInputManager list → open), Network name
  (Wi-Fi SSID needs location permission; else just "Connected"), Bluetooth on/off state + open pairing
  page, Clock/Date, open: Settings, Wi-Fi, Bluetooth, Display & sound, Apps, Accessibility pages
  (standard `android.settings.*` intents; TV Settings handles most).
- Brightness: `Settings.System.SCREEN_BRIGHTNESS` needs WRITE_SETTINGS (grant once via adb
  `appops set com.kirtanya.one_launcher WRITE_SETTINGS allow` if the TV has no UI) — many TVs ignore it;
  show it only when it takes effect.
- Vendor-only (picture mode, wide mode, speakers, auto picture): NOT available generically; on Sony,
  "Picture settings" etc. can deep-link to Sony's pages if their activities are exported — probe per TV,
  show only what resolves. Never fake a value.
- Opening it: from our home (Settings icon in the top bar / Menu key), and globally via the remote's
  Settings key only when the launcher is in front (Sony's SmartUI eats key 197 elsewhere). A global
  hook would need the accessibility key filter in `ShowNameService` — ask the user first.
