# One Launcher — design style

Extracted from the "HabitsJournal" reference screen (dark frame, stacked pastel + white cards).
Values were sampled from the image's pixels and converted from its 752px width to a 375pt phone.
Code lives in `lib/ui/ds.dart` (tokens, class `DS`) and `lib/ui/components.dart` (building blocks).
**Screens never use raw colours or sizes. Always use `DS.*` or a component.**

## 1. The idea

A **dark canvas with a stack of rounded cards**. Each card is one topic. Every screen has
**one pastel "hero" card** at the top, white cards below it, and a soft grey card for
whatever is least important. Actions sit in **circle buttons** at a card's top-right.
The main one is a black (ink) circle, and secondary ones are soft or outlined.

## 2. Colour

| Token | Hex | Used for |
|---|---|---|
| `canvas` | `#1F1F1F` | Screen background (the dark frame) |
| `onCanvas` | `#FFFFFF` | Greeting text on canvas |
| `onCanvasMuted` | `#FFFFFF` 55% | Secondary text on canvas |
| `card` | `#FFFFFF` | Default card |
| `cardMuted` | `#F6F5F8` | Least-important card (last in the stack) |
| `hero` | `#CFE9BC` | The ONE pastel card per screen |
| `heroSoft` | `#DFF2D1` | Soft circle button on the hero card |
| `heroInk` | `#0D1F00` | Text on hero (green-tinted black) |
| `heroMuted` | `#7E956D` | Meta text and tags on hero |
| `heroDivider` | `#B4C99E` | Hairline on hero |
| `ink` | `#1F1F1F` | Text on white, ink buttons, date pill |
| `inkMuted` | `#8F8F8F` | Subtitles |
| `inkFaint` | `#B8B8B8` | "by …" meta, links |
| `hairline` | `#E6E6E6` | Outline buttons, dividers on white |
| `alert` | `#E0624A` | Small urgent pill text ("High", "2 new") |
| `dot` | `#EF7389` | Notification dot |

## 3. Type: Instrument Sans (400 / 500 / 600)

| Token | Size / weight / line | Example |
|---|---|---|
| `greeting` | 22 / 400 / 1.15 | "Hi 👋 Daniel! Welcome back" (on canvas) |
| `display` | 26 / 500 / 1.15, −0.5 tracking | "You have 3 tasks for today" |
| `title` | 24 / 500 / 1.15 | "Productive routine." |
| `eyebrow` | 14 / 500 | "Current tasks", "Community" |
| `rowTitle` | 16 / 600 | "Webinar" |
| `rowSub` | 14 / 400, inkMuted | "Implementation of habits." |
| `meta` | 14 / 400, muted | "10 Thu", "by HabitsJournal", hashtags |
| `pill` | 12 / 600 | "High ↗" |
| `iconLabel` | 12 / 500 | App name under an icon |

## 4. Shape & space

- Screen gutter (canvas → card): **8**. Gap between stacked cards: **4**. The cards nearly touch.
- Card radius **28**, inner padding **20**. Inner media radius **20**.
- Circle button **44** (48 tap area): `ink` (black fill, white icon), `soft` (tinted fill), `outline` (1px hairline).
- Date pill: a **44 × 64 stadium**, ink fill, big number over a small word ("11 / Fri").
- Inline pill: white, full radius, 8×3 padding, sits inside a headline.
- Hero has a hairline divider above a row of tags at its bottom.

## 5. Patterns

- **Hero card** (pastel): meta row (icon + date) and circle buttons → eyebrow → display headline (an inline pill is allowed) → divider → tag row.
- **Row card** (white): date pill · title + subtitle · circle buttons. Used for folders.
- **Feature card** (white): "by …" meta · eyebrow · title · link · media.
- **Muted card** (grey): goes last.

## 6. Rules

1. One hero card per screen, and one ink circle per card.
2. Cards stack with a 4pt gap and never float with big gaps.
3. Text on hero uses the hero-tinted inks, not plain black or grey.
4. Touch targets are at least 48pt even when the visual is 44.
