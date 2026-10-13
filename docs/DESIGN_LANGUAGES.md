# Two design languages, one system

One Launcher has two home views. Each one is a complete design language: when you are in a
view, **every** screen it opens speaks that language — sheets, menus, search, Settings,
editors, dialogs, snackbars. Features and data are shared; the look and layout are not.

| | **Classic** | **Tiles (Metro)** |
|---|---|---|
| Idea | Soft, card-based, Material You | Lumia / Windows Phone Metro: flat, type-led, content first |
| Canvas | Wallpaper + light/dark cards | Black (or the wallpaper) |
| Surfaces | Rounded cards (28), pills, soft shadows | Flat panels, corners = the tile corner setting (square by default), no shadows |
| Colour | The theme palette (Colours & style) | Black / near-black + white type + **one accent** (derived from the theme colour, `metroAccent`) |
| Type | Medium weights, Sentence case | Light weights, big titles, **lowercase** headers, menus, buttons |
| Section headers | Small caps, muted | Lowercase, accent, light |
| Icons in rows | Accent disc (rounded) | Accent tile (square / tile radius) |
| Choices | Ink pills | Outlined boxes, the accent when chosen |
| Tabs | Pill tab bar | **Pivot**: lowercase words, current bright, others dim |
| Search | Pill + result cards (best match card, app row, card per source) | Flat field + list rows like the app list (best match bigger, accent headers per source) |
| Glass | Home look → Glass (drawer, cards, chips, dock) | Tile look → Glass (tiles, app list, search field, sheets) |

## Shared (both views)

Features and behaviour, search sources (Settings → Search → Search in), quick actions, the
theme's colour (Classic uses it as the palette, Metro derives its accent from it), wallpaper,
glass settings (frost, tint, edge, sheen). **Per view:** layout, components, the Glass on/off
switch, wallpaper framing (Classic frames its top area, Tiles the whole screen).

## How it works

The switch is at the token level, so nothing has to remember which view it is in:

- `OneTheme._apply` sets `DS.metro` from `prefs.homeView` and swaps `DS.palette` to
  `OnePalette.metro(accent)`; `DS.metroRadius` follows the tile corner setting.
- `DS.rCard / rMedia / rSheet`, `DS.title`, `DS.eyebrow` read `DS.metro`; `DS.cased()` gives
  Metro's lowercase.
- Shared components branch on `DS.metro`: the sheet chrome and rows (`widgets.dart`),
  `SheetHeader`, settings `_Group` / `_NavRow` / `_SwitchRow` / `_Chip` / `_IconDisc`, the
  editor frame and its tabs (`sheets.dart`), dialogs / snackbars / text buttons (`main.dart`).
- View-only surfaces build their own: Tiles search (`_MetroField`, `_MetroResults`), the app
  list, tiles; Classic search results (`app_drawer.dart`).

**Rule for new screens:** build with the shared components and DS tokens and the language
comes for free; if a screen only exists in one view, build it in that view's language.
