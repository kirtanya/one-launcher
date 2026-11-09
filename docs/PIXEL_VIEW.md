# Pixel view (`prefs.homeView == 'pixel'`)

Goal: it should feel like the official Pixel Launcher (Android 16), end to end — same layout,
motion and gestures — plus the customisation Pixel users keep asking for. Material You
palette (`DesignLanguage.pixel` uses Classic's palette; `DS.pixel` is true in this view).

## Files (lib/pixel/)

| File | What | Owner |
| --- | --- | --- |
| `pixel_model.dart` | `PixelSettings` (all options, defaults), `PixelLayout` (pages, dock, folders; pure ops), stored in `prefs.pixelSettings` / `prefs.pixelLayout` | shared — change only by adding |
| `pixel_icon.dart` | `PixelIcon` (icon cut to shape, dot, label), `PixelShape` clipper | shared |
| `pixel_home.dart` | `PixelHome`: pages, dock, At a Glance, search pill, page dots, gestures, drag & drop, folders on home, home long-press menu, drawer host and swipe-up motion (`_searchMorph` flies the pill into the drawer field; `PixelDrawer.morph` hides its own field until open) | home agent |
| `pixel_folder.dart` | Folder icon (dark back, 1–4 mini icons) + opened folder (compact frosted card anchored to the icon, 2/3/4 columns, name at the bottom, dim without blur) | home agent |
| `pixel_drawer.dart` | `PixelDrawer`: swipe-up all-apps on a blurred translucent sheet (handle, "Search your phone and more" hint, suggestions, Personal/Work pills, A–Z grid, letter scroller) | drawer agent |
| `pixel_popup.dart` | `showPixelAppPopup`: Pixel's vertical long-press card with an arrow (shortcuts, App info, Widgets, Remove or Uninstall) | drawer agent |
| `pixel_settings.dart` | `showPixelHomeSettings`: full-screen, opaque Android settings page (large title, plain rows, radio/slider dialogs, Pixel switches) with every `PixelSettings` option, a Home view row (Classic / Tiles / Real / Pixel) and an Apps list sub-page | settings agent |

## Pixel Launcher, as it looks
- Home: At a Glance top-left (date · weather/next event), grid of icons with labels, page dots
  above the dock, dock of 5 icons, Google search pill at the bottom (G · mic · Lens).
- Swipe up anywhere → all apps rises from the bottom (scrim follows the finger); search field at
  the top, a row of 5 suggested apps, divider, A–Z grid. Swipe down at the top closes it.
- Swipe down on home → notification shade. (Pixel's double tap → screen off is left out on purpose.)
- Long-press empty space → wide frosted menu: Wallpaper and style (+ current wallpaper thumbnail) · Widgets · Apps list · Home settings.
- Long-press an icon → popup anchored at the icon (shortcuts, then small row: App info,
  Widgets, Pause app); once the drag moves → popup goes, icon follows the finger, targets
  "Remove" / "Uninstall" / "App info" appear at the top (not on a bare hold). Drop on another app → folder.
- Folder: a rounded icon-shaped back with a 2x2 preview; tap → expands into a card with the
  name (tap to rename) and the apps grid; tap outside closes.
- Swipe right from page 1 → the left panel (we show our Today panel there).
- Swipe up → the home shrinks (to 92%) and fades while the drawer sheet rises from below
  (from 60% down, fading in), and the search pill flies up into the drawer's search field
  ("Search your phone and more"); 360 ms, follows the finger. Off when the search bar is hidden.

## Extra (the most requested on Pixel)
Grid sizes up to 6x7, icon size, icon shapes, hide labels (home/drawer separately), dock 3–7
icons + scrolling dock, lock home layout, big folders, swipe-up = drawer or
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
swaps cells (no push-aside); apps inside folders have no long-press popup; no Pause app or Bubble
rows; the search pill has no blur; the menu shows one wallpaper thumbnail (only with a photo
wallpaper), not the system list; icons cap at 56dp with a 12dp edge (real: 51dp / 18dp); the folder
back and drawer icons follow the shape setting; no Overview suggestions or Landscape rows; the
swipe-right Today panel isn't covered by a test.
