# Three design languages, one system

One Launcher has three home views. Each one is a complete design language: when you are in a
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
| Today page | Side panel left of home (swipe right; Settings → Today panel turns it off): rounded cards, the first one the hero, Sentence case; list = one card per widget with small-caps headers | Page left of Start: live tiles in the tile look; list = accent headers + accent squares |

## The third view (being designed)

`homeView = 'third'` (shown as "New view") speaks `DesignLanguage.third`. Its look is not
defined yet, so it starts as a copy of Classic: `ThirdHome` (`lib/third/third_home.dart`) hosts
the Classic home, and `DS.third` surfaces read Classic's tokens. Its hooks, ready to fill in:

- **Tokens:** `DS.lang == DesignLanguage.third` / `DS.third` (`ui/ds.dart`) — branch radii,
  type, case and components on it, as Metro does on `DS.metro`.
- **Palette:** `OnePalette.third(base)` (`ui/palette.dart`), applied by `OneTheme._apply`.
- **Per-view settings:** its own copies of the `Prefs.perView` keys (`third.<key>`, starting
  from Classic's values), so its colours, glass and chip look don't change the other views.
- **Home:** `ThirdHome`, routed in `main.dart`; its own screens go in `lib/third/`.

## Shared (all views)

Features and behaviour, search sources (Settings → Search → Search in), quick actions, the
theme's colour (Classic uses it as the palette, Metro derives its accent from it), wallpaper,
glass settings (frost, tint, edge, sheen). the today page's widgets, their order, sizes, layout (tiles/cards or list) and background — one set for both views. **Per view:** layout, components, the Glass on/off
switch, wallpaper framing (Classic frames its top area, Tiles the whole screen).

## How it works

The switch is at the token level, so nothing has to remember which view it is in:

- `OneTheme._apply` sets `DS.lang` (`DesignLanguage.of(prefs.homeView)`; `DS.metro` and
  `DS.third` read it) and swaps `DS.palette` to `OnePalette.metro(accent)` or
  `OnePalette.third(palette)`; `DS.metroRadius` follows the tile corner setting.
- `DS.rCard / rMedia / rSheet`, `DS.title`, `DS.eyebrow` read `DS.metro`; `DS.cased()` gives
  Metro's lowercase.
- Shared components branch on `DS.metro`: the sheet chrome and rows (`widgets.dart`),
  `SheetHeader`, settings `_Group` / `_NavRow` / `_SwitchRow` / `_Chip` / `_IconDisc`, the
  editor frame and its tabs (`sheets.dart`), dialogs / snackbars / text buttons (`main.dart`).
- The today page (`tiles/today_panel.dart`, `day_line.dart`) is one widget in both views: it
  branches on `DS.metro` for its cards, type, case and edit controls. Classic hosts it in
  `home.dart` as page 0 of a pager (home = page 1; the top carousel hands a swipe past its first
  page over to it); Tiles as page 0 left of Start.
- View-only surfaces build their own: Tiles search (`_MetroField`, `_MetroResults`), the app
  list, tiles; Classic search results (`app_drawer.dart`).

**Rule for new screens:** build with the shared components and DS tokens and the language
comes for free; if a screen only exists in one view, build it in that view's language.
