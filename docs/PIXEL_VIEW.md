# Pixel view (`prefs.homeView == 'pixel'`)

Goal: it should feel like the official Pixel Launcher (Android 16), end to end — same layout,
motion and gestures — plus the customisation Pixel users keep asking for. Material You
palette (`DesignLanguage.pixel` uses Classic's palette; `DS.pixel` is true in this view).

## Files (lib/pixel/)

| File | What | Owner |
| --- | --- | --- |
| `pixel_model.dart` | `PixelSettings` (all options, defaults), `PixelLayout` (pages, dock, folders; pure ops), stored in `prefs.pixelSettings` / `prefs.pixelLayout` | shared — change only by adding |
| `pixel_icon.dart` | `PixelIcon` (icon cut to shape, dot, label), `PixelShape` clipper | shared |
| `pixel_home.dart` | `PixelHome`: pages, dock, At a Glance, search pill, page dots, gestures, drag & drop, folders on home, home long-press menu, drawer host | home agent |
| `pixel_folder.dart` | Folder preview icon (2x2) + opened folder (Pixel's morphing card, rename, page grid; big folders) | home agent |
| `pixel_drawer.dart` | `PixelDrawer`: swipe-up all-apps (search on top, suggestions row, A–Z grid, letter scroller, work tab when work apps exist) | drawer agent |
| `pixel_popup.dart` | `showPixelAppPopup`: Pixel's anchored long-press popup (shortcuts, App info, Widgets, Pause/Uninstall/Remove) | drawer agent |
| `pixel_settings.dart` | `showPixelHomeSettings`: "Home settings" page with every `PixelSettings` option | settings agent |

## Pixel Launcher, as it looks
- Home: At a Glance top-left (date · weather/next event), grid of icons with labels, page dots
  above the dock, dock of 5 icons, Google search pill at the bottom (G · mic · Lens).
- Swipe up anywhere → all apps rises from the bottom (scrim follows the finger); search field at
  the top, a row of 5 suggested apps, divider, A–Z grid. Swipe down at the top closes it.
- Swipe down on home → notification shade. Double tap empty space → screen off.
- Long-press empty space → small menu: Wallpaper & style · Widgets · Home settings.
- Long-press an icon → popup anchored at the icon (shortcuts, then small row: App info,
  Widgets, Pause app); start dragging → popup goes, icon follows the finger, targets
  "Remove" / "Uninstall" / "App info" appear at the top. Drop on another app → folder.
- Folder: a rounded icon-shaped back with a 2x2 preview; tap → expands into a card with the
  name (tap to rename) and the apps grid; tap outside closes.
- Swipe right from page 1 → the left panel (we show our Today panel there).

## Extra (the most requested on Pixel)
Grid sizes up to 6x7, icon size, icon shapes, hide labels (home/drawer separately), dock 3–7
icons + scrolling dock, lock home layout, big folders, double-tap to sleep, swipe-up = drawer or
search, drawer sort (A–Z / recent / most used), drawer columns, keyboard on open, letter
scroller, hide apps (existing `prefs.hidden`), App lock (existing `AppLock.of(prefs).gate`),
themed icons (existing `prefs.themedIcons`), notification dots, new apps added to home.

## Reuse (don't rebuild)
`Apps.instance` (list, icon, launch, shortcuts, appInfo, uninstall, openNotifications,
lockScreen, openWallpaperPicker, widgetProviders/addWidget, notifCounts), `AppIcon`,
`AppLock.of(prefs).gate(pkg)` before every launch, `prefs.recordLaunch`, `prefs.hidden`,
`showWidgetPicker`, `showSettingsSheet`, `TodayPanel`, `searchApps`/search sheet, `Perf.lite`.

## Not done yet
Hosted widgets can't be dragged or resized on home; the Lens glyph is a stand-in; drag-reorder
swaps cells (no push-aside); apps inside folders have no long-press popup; no Pause app; the
swipe-right Today panel isn't covered by a test.
