# Tactile — the third design language

> Working name for `DesignLanguage.third` ("New view"). A launcher that feels like a piece of
> well-made hardware: injection-moulded panels, keys that travel, knobs with detents, LEDs that
> carry state, printed legends. Layout follows Classic; every surface, control and motion is
> Tactile. Read with docs/DESIGN_LANGUAGES.md.

## 1. What the references say

| Ref | What it is | What we take |
|---|---|---|
| 1 · grey console | Braun / Teenage Engineering-style panel: knobs in bezel rings, a dark tray of keys (mono/stereo, transport), cyan LEDs, speaker grille | Bezel rings, **trays** that hold keys, **LED = state**, glyph legends under keys, one loud key (record red) |
| 2 · white plug-in | Porcelain panels, knobs with dotted scale, recessed LCD with a graph, thin faders, pill segmented control, ADV toggle | **Panels** with big soft shadow, **inset screen**, faders, segmented track, uppercase tracked labels |
| 3 · warm audio unit | Knobs with orange pointer, min/max marks, bracket lines grouping controls, rotary selector with leader lines, small rectangular keys, orange LEDs, dot-matrix type | **Bracket + leader lines** for grouping, **dot-matrix legends**, pressed key = sunken + darker, orange LED |
| 4 · BUTTON. D. | A deep debossed well with a soft rounded thumb, mono blue label | **The switch**: a real well and a cap that slides and lands; mono label in an accent ink |
| 5 · graphite dial | Charcoal plate, big dial with recessed centre button, round keys with fine rim highlights, hairline icons | **Dark material**, concentric dial (→ the TV remote's d-pad), rim highlight, hairline icons |

Common thread: **objects, not drawings.** Every element is a part you could manufacture — it has a
material, a thickness, a way it moves, and a sound.

## 2. Principles

1. **One light, top.** A single light from above (slightly left). Highlights on top edges, shadows
   below. Never mix directions; a recess is lit on its *lower* inner wall.
2. **Things have depth levels** (see §4). Interactive parts sit *above* the panel (raised) or *in*
   it (keys in a tray, a thumb in a well). Flat = not interactive. This fixes neumorphism's
   "is this a button?" problem.
3. **Light means state.** On / selected / unread / connected is shown by a lit LED or a lit legend,
   not by recolouring the whole control. Colour is mostly *emitted*.
4. **Motion is mechanical.** Keys travel down and spring back; switches slide and latch; knobs
   turn in detents; nothing fades in from nowhere — it slides out of a slot, rises from a well,
   or lights up.
5. **Feel it and hear it.** Every physical action has a matching haptic and (optional) sound, timed
   to the moment of contact, not the end of the animation.
6. **Printed, not typed.** Labels are legends printed on the panel: small, uppercase, tracked;
   numbers and status in a dot-matrix or mono face.
7. **Group with hardware.** Trays, plates, bracket lines and leader lines group controls — not
   generic cards and dividers.
8. **Contrast is not optional.** Every control has a visible edge (≥3:1 against its neighbour) — a
   rim, a darker tray or an outline — and every state has a label or LED, not shadow alone.

## 3. Colour

The references are greyscale; Tactile is not. Colour lives in three places:

| Role | Where | From |
|---|---|---|
| **Material** (the plastic) | Panels, plates, key caps | A neutral **finish**, very slightly tinted toward the theme hue (4–8 %) so it belongs to the wallpaper |
| **Accent caps** | One or two special keys (Search, Call, Record-type actions), a selected segment | The theme's primary/tertiary as a **coloured plastic** (painted cap, still shaded like the others) |
| **Light** | LEDs, lit legends, LCD backlight, the knob pointer | The theme's primary as an **emitter**, plus fixed signal lights (see below) |

**Finishes** (pick in Colours & style; light/dark/auto maps to Porcelain/Graphite):

| Finish | Panel | Plate (raised) | Tray (sunken) | Ink | Ref |
|---|---|---|---|---|---|
| Porcelain | `#ECEDEF` | `#F6F7F8` | `#DCDEE1` | `#2A2C30` | 2, 3, 4 |
| Concrete | `#B7B8BA` | `#C9CACC` | `#2E2F31` (dark tray) | `#2A2B2D` | 1 |
| Graphite | `#2B2A2D` | `#343337` | `#1E1D20` | `#E6E4E8` | 5 |

**Coloured plastics** (Material You): a cap colour is the theme's `primaryContainer` (light) /
`primary` (dark), shaded with the *same* gradient and shadow recipes as neutral caps — colour never
removes the material. Allowed per screen: **one** coloured cap family + LEDs.

**Signal lights** (fixed, readable on all finishes): on = theme primary LED · alert `#FF4D4D` ·
warning `#FF9F1A` · ok `#2BD9A0` · info `#3D7BFF`. An LED is a glowing dot: core colour, a 6–10 dp
bloom at 50 %, a white specular pip; *off* = dark glass `#3A3A3D` with a faint rim.

## 4. Depth — the five levels

Light from the top. Values for Porcelain; Graphite uses the same geometry with darker highlights.

| Level | Name | Used for | Recipe |
|---|---|---|---|
| −2 | **Well** | Switch well, LCD, search field, tray floor | Inner shadow top `0 3 6 #0000004D`; inner highlight bottom `0 −1 0 #FFFFFFB3`; floor 3 % darker than panel |
| −1 | **Inset** | Fader track, segmented track, page-dot holes | Inner shadow `0 1 2 #00000033`; bottom rim highlight `0 1 0 #FFFFFF99` |
| 0 | **Panel** | The canvas, sheets, big plates | Flat finish; edge chamfer = 1 dp highlight on top edge |
| +1 | **Raised** | Keys, chips, cards you can press, toggle thumb | Face gradient top +4 % → bottom −3 %; top rim `inset 0 1 0 #FFFFFFCC`; drop `0 1 1 #00000033` + `0 4 8 #00000026` |
| +2 | **Proud** | Knobs, dial, the floating nav, FAB-type keys | Bezel ring (gradient dark top → light bottom = a lip around a hole) + domed cap (radial gradient, specular top-left) + drop `0 10 20 #00000038`, `0 2 4 #00000033` |

**Pressed** = the part moves down one level: its drop shadow shrinks to ~25 %, its face darkens
4 %, and a faint inner shadow appears at the top. **Latched** (a toggle key that stays down) keeps
the pressed geometry and lights its LED.

Radii: keys 12 · plates 24 · panels 28 · wells match their content's radius + their wall (4).
Hairline: 1 dp rim on every control (`#0000001F` light finishes, `#FFFFFF14` dark).

## 5. Type

| Use | Face | Style |
|---|---|---|
| Legend (labels on panels, section names) | App sans (Inter-like) | 11 sp, w600, UPPERCASE, +1.2 tracking, ink 60 % |
| Readout (values, counters, LCD text, status) | Dot-matrix (e.g. **Doto**) or mono (**Space Mono**) | 12–14 sp, uppercase, tracked |
| Titles / app names | App sans | Sentence case, w500 — the only "normal" text |
| Clock | Dot-matrix or 7-segment on an LCD; or printed numerals on the panel | Per clock style |

## 6. Interaction feel (the important part)

Every control is modelled as a **physical mechanism** with: travel, a contact point, a detent or
latch, a spring, a haptic and a sound. Haptics use Android's predefined effects (`CLICK`,
`TICK`, `HEAVY_CLICK`, `DOUBLE_CLICK`) through `HapticFeedback` / a small native bridge; sounds are
short (<60 ms) samples, played on contact, ducked to 30 % volume, off when the phone is silent,
and switchable (Settings → Look → Sounds).

| Mechanism | Travel / motion | Contact moment | Haptic | Sound |
|---|---|---|---|---|
| **Key** (momentary) | Down 2 dp over 60 ms on touch-down (not on tap-up); spring back 140 ms with slight overshoot | Bottoming out | `CLICK` on down, light `TICK` on release | "tk" down, softer "tk" up |
| **Latching key** | Down 2 dp, stays at 1.5 dp, LED fades on 120 ms | Latch | `HEAVY_CLICK` | deeper "clack" |
| **Switch** (ref 4) | Thumb follows the finger in the well; past 50 % it snaps to the end with spring (240 ms); dragging back past centre reverses. Over-drag compresses the thumb 3 % (rubber) | Thumb hitting the end wall | `HEAVY_CLICK` at the wall; a faint `TICK` at the centre crossing | two-part "click-clunk" |
| **Knob** | Rotates with the finger (circular drag) or vertical drag; **detents** every step (e.g. 5 %); inertia off | Each detent | `TICK` per detent, `CLICK` at min/max stop | soft ratchet tick per detent |
| **Fader** | Cap slides in the track; optional detent at centre / defaults | Detents | `TICK` at detents | low "shhk" while moving (very quiet) |
| **Segmented selector** | Selected segment is a raised cap that slides to the tapped slot (220 ms, spring) | Arriving | `CLICK` | "tk" |
| **Dial** (remote d-pad) | Ring tilts 2° toward the pressed side; centre key travels 2 dp | Press | `CLICK`; long-press repeats with `TICK` | key click |
| **LED** | Fades on 120 ms with bloom; off 200 ms (glass cools) | — | — | — |
| **Drawers / sheets** | Slide out of a slot in the panel (not fade); land with a 1 dp settle | Landing | light `TICK` | soft "thud" (optional) |

Rules: feedback on **touch-down** (that's when a real key moves); never haptic on a mere scroll;
throttle ticks to ≥35 ms apart; respect system "touch feedback" and Lighter effects (Lighter →
no sounds, single haptic, simpler shadows).

## 7. Pattern library

| Component | Anatomy | States | Launcher uses |
|---|---|---|---|
| **Panel** | Level 0 finish, 28 radius, top chamfer | — | Screen canvas, app sheet, settings pages |
| **Plate** | Level +1 big rounded slab, 24 radius, large soft shadow (ref 2) | — | Folders, the pinned/most-used block, settings groups, notification cards |
| **Tray** | Level −2 dark/darker well holding a row of keys, 12 radius, 4 dp gutters (ref 1) | — | Bottom nav, quick chips row, segmented choices, remote transport row |
| **Key** | Raised cap in a tray or on a plate; square/rect; concave dish (radial) or flat; legend below or on cap; optional LED | rest · pressed · latched · disabled · coloured cap | Nav tabs, quick chips, app keys, remote buttons, dialog buttons |
| **Knob** | Bezel ring + domed cap + pointer (line or LED dot) + scale (dots/ticks, min/max legends) (refs 1–3) | rest · turning · at stop · disabled | Settings values (size, dim, padding, chip size), remote volume / brightness |
| **Selector knob** | Knob + leader lines to labelled positions (ref 3) | position N | Small 3–5 option choices (Light / Dark / Auto, effects) |
| **Switch** | Debossed well + soft thumb + mono legend (ref 4); LED optional | off · on · dragging · disabled | All toggles |
| **Fader** | Inset track + pill cap + tick scale + legend (ref 2) | rest · moving | Long ranges (top size, opacity) |
| **Segmented** | Inset pill track + sliding raised segment (ref 2) | — | 2–4 short choices (search position, layout) |
| **LED** | Glass dot, off/on/blink, colour = signal | off · on · blink · pulse | Selected tab, unread, connected TV, page indicator, recording |
| **LCD** | Well with backlit screen, dot-matrix text, faint pixel grid & scanline, optional graph (ref 2) | off · on · alert | Clock & date, search field, now playing, notifications count, remote status |
| **Dial** | Big concentric dial + recessed centre key (ref 5) | rest · pressed side · centre pressed | TV remote d-pad |
| **Grille** | Hex/round dot perforation (ref 1) | — | Decoration: empty states, the remote's speaker/mic zone, drawer handle |
| **Bracket & leader lines** | 1 dp printed lines with corner + arrow notch (ref 3) | — | Group headers in settings, pointing legends to controls |
| **Power key** | Small round recessed key with ⏻ glyph (ref 2) | off · on (LED ring) | TV power, a section's on/off |
| **Glyph legend** | Hairline icons 1.5 dp, printed in ink (ref 5) | — | Icons on keys, transport ▶ ❚❚ ■ ● |

## 8. Mapping to the launcher (layout = Classic)

| Classic part | Tactile version |
|---|---|
| Wallpaper top area | A **window** in the panel: the wallpaper seen through a bezelled cut-out, or a plain finish (setting) |
| Clock + date | An **LCD** (dot-matrix numerals, backlit in the theme colour) or printed numerals; date as a readout |
| Quick chips | A **tray of keys** with legends; tapping lights the key's LED briefly |
| App sheet | A big **plate** that slides up out of the panel |
| Pinned / most used | A plate of **app keys** (icon on a concave cap) |
| Folders | Plates with a bracket-line header; opening slides a sub-plate out |
| Search | An **LCD strip** with a blinking block cursor; results are printed rows on a plate |
| Bottom nav | A **transport tray**: 4–5 keys, the current one latched with its LED on (ref 1's bottom row) |
| Pull-to-search | The plate is pushed down into the panel; the tray's keys sink one after another and the LCD rises |
| Settings | Panels with plates; switches, knobs, faders, selectors; bracket-line group headers |
| TV remote | Graphite finish: dial d-pad, transport tray, knobs for volume/brightness, power key, LEDs for connection |
| Notifications | Plates like printed slips; LED for unread; calls on an LCD with Answer (green cap) / Decline (red cap) |

## 9. Building it (Flutter)

- `lib/third/tactile/`: tokens (`TactileFinish`, depth recipes, signal colours, type), and the
  parts: `TPanel`, `TPlate`, `TTray`, `TKey`, `TKnob`, `TSelectorKnob`, `TSwitch`, `TFader`,
  `TSegmented`, `TLed`, `TLcd`, `TDial`, `TGrille`, `TBracket`.
- Inner shadows (Flutter has none): one `InnerShadow` painter (save layer, inverted path, blurred
  shadow, clip) shared by every well; domes and dishes are `RadialGradient`s; all recipes cached
  per size with `RepaintBoundary`.
- Feel: a `TactileFeedback` service (haptic effect + sound per event, throttled, respects
  settings); sounds via a tiny native `SoundPool` (no new package needed).
- Shared components (`_Group`, `_SwitchRow`, `_Chip`, sheets, `SheetHeader`) branch on `DS.third`
  to these parts, as they do on `DS.metro`.
- Lighter effects: no inner shadows (flat wells with a rim), single drop shadow, no sounds.

## Sources

- Skeuomorphism style notes (light source, layered shadows): superdesign.dev/styles/skeuomorphism,
  bighuman.com/blog/guide-to-skeuomorphic-design-style, uiverse.io (skeuomorphic minimalism 2025)
- Accessibility of soft / neumorphic UI (contrast, affordance): uxdesign.cc "Neumorphism, visual
  accessibility, and empathy", setproduct.com/blog/neumorphism-design-guide, LogRocket
  "Neumorphism UI design"
