import 'package:flutter/material.dart';

import '../prefs.dart';
import '../tiles/landing.dart' show landingStyles;
import '../top/header_fonts.dart' show clockPresets;
import 'art_quality.dart';
import 'catalog.dart';
import 'tv_apps.dart';
import 'tv_catalog_settings.dart';
import 'tv_parts.dart';

/// One TV setting: a key in [Prefs.tvSettings], its choices (value → label) and default.
/// On/off settings are just two choices.
class TvOption {
  const TvOption(this.key, this.label, this.choices, this.fallback, {this.read, this.write});
  final String key, label;
  final List<(Object, String)> choices;
  final Object fallback;

  /// Settings shared with the phone's Tiles (their own prefs keys) read / write through these
  /// instead of the TV settings map.
  final Object Function(Prefs p)? read;
  final Future<void> Function(Prefs p, Object v)? write;

  static TvOption onOff(String key, String label, {bool on = true}) => TvOption(key, label, const [(true, 'On'), (false, 'Off')], on);
}

const _spotStyles = [('big', 'Big cards'), ('small', 'Small cards')];

/// Spotlight-only options: left out of the other views' Customise.
const _spotlightOnly = {'spotCardContinue', 'spotCardFav', 'spotCardRecent', 'spotCardOther'};

/// Everything the user can change, by section (Customise). Order = menu order.
const tvSections = <(String, IconData, List<TvOption>)>[
  // One page per thing on the home screen: everything about it in one place. Rows/columns the
  // home adds actions to (Edit quick actions, All apps…) get them at the end (TvExtras).
  (
    'Background',
    Icons.wallpaper_rounded,
    [
      TvOption('backdrop', 'Background picture', [('art', 'Artwork'), ('glow', 'Soft glow'), ('off', 'Off')], 'art'),
      TvOption('dim', 'Background darkness', [(.7, 'Light'), (1.0, 'Medium'), (1.25, 'Strong')], 1.0),
      // How sharp the full-screen picture is (art_quality.dart): sharper = heavier to fetch and decode.
      TvOption('artQuality', 'Picture quality', ArtQuality.levels, 'high'),
      TvOption('hero', 'Title & details', [(true, 'On'), (false, 'Off')], true),
      TvOption('hints', 'Remote hints (OK · Hold OK)', [(true, 'On'), (false, 'Off')], true),
    ],
  ),
  (
    'Clock',
    Icons.schedule_rounded,
    [
      TvOption('clock', 'Clock', [(true, 'On'), (false, 'Off')], true),
      TvOption('clock24', 'Clock format', [('auto', 'Like the TV'), ('12', '12-hour'), ('24', '24-hour')], 'auto'),
      TvOption('date', 'Date', [(true, 'On'), (false, 'Off')], true),
    ],
  ),
  (
    'Continue watching',
    Icons.play_circle_outline_rounded,
    [
      TvOption('rowContinue', 'Continue watching', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('spotCardContinue', 'Cards', _spotStyles, 'big'),
      TvOption('resume', 'Resume button', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('controls', 'Player controls ⏮ ⏯ ⏭', [(true, 'Show'), (false, 'Hide')], true),
    ],
  ),
  (
    'Quick actions',
    Icons.bolt_rounded,
    [
      TvOption('quick', 'Quick actions', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('quickLabels', 'Labels', [('always', 'Always'), ('focus', 'Only when focused'), ('never', 'Never (icons only)')], 'always'),
      TvOption('quickSize', 'Chip size', [(.8, 'Small'), (1.0, 'Medium'), (1.2, 'Large')], 1.0),
    ],
  ),
  (
    'Your apps',
    Icons.apps_rounded,
    [
      TvOption('rowFav', 'Your apps', [(true, 'Show'), (false, 'Hide')], true),
      // Circles keep apps apart from shows and films at a glance.
      TvOption('appCards', 'App cards', [('round', 'Circle (app icon)'), ('banner', 'Big card (banner)')], 'round'),
      TvOption('spotCardFav', 'Cards', _spotStyles, 'big'),
    ],
  ),
  (
    'Jump back in',
    Icons.history_rounded,
    [
      TvOption('rowRecent', 'Jump back in', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('spotCardRecent', 'Cards', _spotStyles, 'big'),
    ],
  ),
  (
    'Streaming apps’ rows',
    Icons.view_stream_outlined,
    [
      TvOption('rowChannels', 'Streaming apps’ rows', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('rowFolders', 'Smart folder rows', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('spotCardOther', 'Cards', _spotStyles, 'big'),
    ],
  ),
  (
    'Cards & focus',
    Icons.view_carousel_outlined,
    [
      TvOption('cardScale', 'Card size', [(.7, 'Extra small'), (.85, 'Small'), (1.0, 'Medium'), (1.15, 'Large')], 1.0),
      TvOption('focus', 'Focused card', [('glow', 'Outline + glow'), ('outline', 'Outline only')], 'outline'), // never scales; glow = 2 blurs per move (GPU)
      TvOption('rowTitles', 'Row titles', [(true, 'On'), (false, 'Off')], true),
      TvOption('rowsAt', 'Rows start', [(.45, 'Higher'), (.55, 'Middle'), (.65, 'Lower')], .55),
      TvOption('motion', 'Animations', [('full', 'Full'), ('reduced', 'Reduced')], 'full'),
    ],
  ),
  (
    'Remote & behaviour',
    Icons.settings_remote_outlined,
    [
      TvOption('landing', 'Start on', [('quick', 'First quick action'), ('resume', 'Resume'), ('app', 'First app'), ('search', 'Search')], 'quick'),
      TvOption('back', 'Back button', [('home', 'Go to start'), ('search', 'Go to Search'), ('none', 'Do nothing')], 'home'),
      TvOption('history', 'Remember what I watch', [(true, 'On'), (false, 'Off')], true),
      // ShowNameService reads Google's results page and hands the words over (needs "Read show names" on).
      TvOption('remoteMic', 'Remote’s mic searches in', [('ours', 'One Launcher'), ('google', 'Google')], 'ours'),
    ],
  ),
];

/// Customise → Search: how often the shows & films catalog updates itself (the rest of that
/// section — update now, sources — is in tv_catalog_settings.dart).
const tvSearchOptions = <TvOption>[
  TvOption('catalogAuto', 'Auto-update', [('daily', 'Daily'), ('weekly', 'Weekly'), ('off', 'Off')], 'daily'),
];

/// Customise → Tiles: the Tiles design language on TV, in groups (Layout, Tiles look, Names &
/// icons, Focus & motion, Clock tile). Many are the phone's own Tiles settings (same prefs keys:
/// tile look, glass, corners, colours, animation, interactions, clock); the rest are TV-only
/// (Prefs.tvSettings). Everything shows live on Start behind the panel.
final tvTilesHomeView = TvOption(
  'homeView',
  'Home view',
  const [('classic', 'Cinematic'), ('spotlight', 'Spotlight'), ('tiles', 'Tiles'), ('third', 'Real')],
  'classic',
  read: (p) => p.homeView,
  write: (p, v) => p.setHomeView(v as String),
);

final tvTilesGroups = <(String, IconData, List<TvOption>)>[
  (
    'Layout',
    Icons.dashboard_customize_outlined,
    [
      const TvOption('tileRows', 'Rows of tiles', [(3.0, '3 (big)'), (4.0, '4'), (5.0, '5'), (6.0, '6 (small)')], 4.0),
      const TvOption('tileGap', 'Tile spacing', [(4.0, 'Tight'), (8.0, 'Normal'), (14.0, 'Wide')], 8.0),
      const TvOption('tileTitle', 'Title', [('start', '“start”'), ('home', '“home”'), ('greeting', 'Greeting'), ('off', 'Hidden')], 'start'),
      const TvOption('tileBg', 'Background', [
        ('black', 'Black'),
        ('glow', 'Accent glow'),
        ('gradient', 'Accent gradient'),
        ('accent', 'Solid accent'),
        ('focus', 'Focused artwork'),
        ('art', 'What you’re watching'),
      ], 'focus'),
      const TvOption('tileQuickRow', 'Quick actions row', [(true, 'Show'), (false, 'Hide')], true),
      const TvOption('tileResumeRow', 'Resume row', [(true, 'Show'), (false, 'Hide')], true),
      const TvOption('tileResumeSize', 'Resume cards', [(120.0, 'Small'), (150.0, 'Medium'), (180.0, 'Large')], 150.0),
      const TvOption('tileHeadings', 'Row headings', [('off', 'Off'), ('accent', 'Accent'), ('white', 'White')], 'off'),
      const TvOption('tileNewSize', 'New tiles', [('s', 'Small'), ('m', 'Medium'), ('w', 'Wide')], 'm'),
    ],
  ),
  (
    'Tiles look',
    Icons.palette_outlined,
    [
      TvOption(
        'tileColours',
        'Tile colours',
        const [('accent', 'Accent'), ('colourful', 'Each app’s colour'), ('rainbow', 'Rainbow'), ('dark', 'Dark')],
        'accent',
        read: (p) => p.tileColours,
        write: (p, v) => p.setTileColours(v as String),
      ),
      TvOption(
        'tileOpacity',
        'Tile transparency',
        const [(1.0, 'None'), (.85, '15%'), (.7, '30%'), (.55, '45%'), (.4, '60%')],
        1.0,
        read: (p) => p.tileOpacity,
        write: (p, v) => p.setTileLook(opacity: v as double),
      ),
      TvOption(
        'tileRadius',
        'Corner roundness',
        const [(0.0, 'Square'), (4.0, 'Slight'), (8.0, 'Soft'), (16.0, 'Round'), (24.0, 'Very round')],
        0.0,
        read: (p) => p.tileRadius,
        write: (p, v) => p.setTileLook(radius: v as double),
      ),
      const TvOption('tileShadow', 'Tile shadow', [(false, 'Off'), (true, 'On')], false),
      TvOption(
        'tileStyle',
        'Tile look',
        const [('solid', 'Solid'), ('glass', 'Glass')],
        'solid',
        read: (p) => p.tileStyle,
        write: (p, v) => p.setGlass(style: v as String),
      ),
      TvOption(
        'glassBlur',
        'Glass frost',
        const [(0.0, 'Off'), (10.0, 'Light'), (18.0, 'Medium'), (30.0, 'Heavy')],
        18.0,
        read: (p) => p.glassBlur,
        write: (p, v) => p.setGlass(blur: v as double),
      ),
      TvOption(
        'glassTint',
        'Glass tint',
        const [(.15, 'Clear'), (.25, 'Light'), (.4, 'Medium'), (.55, 'Strong')],
        .25,
        read: (p) => p.glassTint,
        write: (p, v) => p.setGlass(tint: v as double),
      ),
      TvOption(
        'glassEdge',
        'Glass bright edge',
        const [(true, 'On'), (false, 'Off')],
        true,
        read: (p) => p.glassEdge,
        write: (p, v) => p.setGlass(edge: v as bool),
      ),
      TvOption(
        'glassSheen',
        'Glass sheen',
        const [(true, 'On'), (false, 'Off')],
        true,
        read: (p) => p.glassSheen,
        write: (p, v) => p.setGlass(sheen: v as bool),
      ),
    ],
  ),
  (
    'Names & icons',
    Icons.text_fields_rounded,
    [
      TvOption(
        'tileLabels',
        'Names on tiles',
        const [(true, 'On'), (false, 'Off')],
        true,
        read: (p) => p.tileLabels,
        write: (p, v) => p.setTileLook(labels: v as bool),
      ),
      const TvOption('tileLabelPos', 'Name position', [('bottom', 'Bottom'), ('top', 'Top')], 'bottom'),
      const TvOption('tileLabelSize', 'Name size', [(11.0, 'Small'), (13.0, 'Medium'), (16.0, 'Large')], 13.0),
      const TvOption('tileCase', 'Text case', [('lower', 'lowercase'), ('as', 'As named')], 'lower'),
      const TvOption('tileFace', 'App tiles show', [('icon', 'Icon'), ('banner', 'TV banner')], 'icon'),
      const TvOption('tileIconStyle', 'App icons', [('colour', 'Full colour'), ('white', 'White glyph')], 'colour'),
      const TvOption('tileIconSize', 'Icon size', [(.75, 'Small'), (1.0, 'Medium'), (1.3, 'Large')], 1.0),
      const TvOption('tileQuickStyle', 'Quick action tiles', [('text', 'Icon + name'), ('icon', 'Icon only')], 'text'),
    ],
  ),
  (
    'Focus & motion',
    Icons.center_focus_strong_outlined,
    [
      const TvOption('tileFocus', 'Focus', [('frame', 'Frame'), ('glow', 'Frame + glow'), ('lift', 'Lift only')], 'frame'),
      const TvOption('tileFocusColour', 'Focus colour', [('white', 'White'), ('accent', 'Accent')], 'white'),
      TvOption('fx.tilt', 'Tilt on focus', const [(true, 'On'), (false, 'Off')], true, read: (p) => p.fx('tilt'), write: (p, v) => p.setFx('tilt', v as bool)),
      TvOption(
        'tileAnim',
        'Start animation',
        [for (final (id, label) in landingStyles) (id, label)],
        'turnstile',
        read: (p) => p.tileAnim,
        write: (p, v) => p.setLandingAnims(tiles: v as String),
      ),
      TvOption(
        'fx.turnstile',
        'Turnstile on launch',
        const [(true, 'On'), (false, 'Off')],
        true,
        read: (p) => p.fx('turnstile'),
        write: (p, v) => p.setFx('turnstile', v as bool),
      ),
      TvOption('fx.live', 'Live tiles', const [(true, 'On'), (false, 'Off')], true, read: (p) => p.fx('live'), write: (p, v) => p.setFx('live', v as bool)),
      const TvOption('tileFlip', 'Live tile speed', [(3.0, 'Fast'), (5.2, 'Normal'), (9.0, 'Slow')], 5.2),
    ],
  ),
  (
    'Clock tile',
    Icons.schedule_rounded,
    [
      TvOption(
        'tileClock',
        'Clock tile style',
        [for (final c in clockPresets) (c.$1, c.$1)],
        'Classic',
        read: (p) {
          for (final (name, w, wd, sl, r) in clockPresets) {
            if ((p.tileClockWeight - w).abs() < 1 &&
                (p.tileClockWidth - wd).abs() < 1 &&
                (p.tileClockSlant - sl).abs() < .1 &&
                (p.tileClockRound - r).abs() < 1) {
              return name;
            }
          }
          return 'Custom';
        },
        write: (p, v) {
          final c = clockPresets.firstWhere((c) => c.$1 == v);
          return p.setTileClockStyle(weight: c.$2, width: c.$3, slant: c.$4, round: c.$5);
        },
      ),
      const TvOption('clock24', 'Clock format', [('auto', 'Like the TV'), ('12', '12-hour'), ('24', '24-hour')], 'auto'),
      const TvOption('tileClockDate', 'Date on the clock tile', [('auto', 'Bigger tiles'), ('on', 'Always'), ('off', 'Never')], 'auto'),
    ],
  ),
];

/// Every Tiles option (Home view first), for lookups.
final tvTilesOptions = <TvOption>[tvTilesHomeView, for (final (_, _, opts) in tvTilesGroups) ...opts];

/// The settings as the home screen reads them (refreshed from prefs on every build).
class TvLook {
  static Map<String, dynamic> _s = const {};

  static void read(Prefs p) => _s = p.tvSettings;

  static T get<T>(String key) {
    final v = _s[key];
    if (v is T) return v;
    if (T == double && v is num) return v.toDouble() as T;
    for (final o in [for (final (_, _, opts) in tvSections) ...opts, ...tvTilesOptions, ...tvSearchOptions]) {
      if (o.key == key) return o.fallback as T;
    }
    throw ArgumentError('unknown TV setting $key');
  }

  static bool on(String key) => get<bool>(key);
  static double number(String key) => get<double>(key);
  static String str(String key) => get<String>(key);

  /// Reduced motion: every transition snaps (or nearly).
  static Duration anim(Duration d) => str('motion') == 'reduced' ? const Duration(milliseconds: 1) : d;
}

/// What the home screen adds to Customise, by page (its Cinematic name): 'Quick actions' →
/// Edit quick actions, 'Your apps' → All apps / unhide, 'System' → home-screen setup; '' → rows
/// on Customise itself (Colours).
typedef TvExtras = Map<String, List<TvAction>>;

/// Customise: the home view, then one page per thing on the home screen (each OK steps to the
/// next choice; the home screen behind the panel updates as you go), Search, System.
void showTvCustomise(BuildContext context, {required Prefs prefs, required TvExtras extras}) {
  final view = prefs.homeView;
  showTvPanel(
    context,
    title: 'Customise',
    actions: [
      _optionRow(prefs, tvTilesHomeView), // Home view: Cinematic / Spotlight / Tiles / Real
      // Only what the home view in use reads (Tiles has its own groups).
      for (final (name, icon, opts) in tvSectionsFor(view)) TvAction(icon, name, () => _section(context, prefs, name, opts, extras)),
      if (view == 'tiles') TvAction(Icons.grid_view_rounded, 'Tiles', () => _tilesSection(context, prefs, extras)),
      ...?extras[''],
      TvAction(Icons.search_rounded, 'Search', () => _section(context, prefs, 'Search', tvSearchOptions, extras)),
      TvAction(Icons.settings_outlined, 'System', () => _system(context, prefs, extras)),
    ],
  );
}

/// Customise → System: home-screen setup and Reset everything.
void _system(BuildContext context, Prefs prefs, TvExtras extras) {
  showTvPanel(
    context,
    title: 'System',
    actions: [
      TvAction(Icons.arrow_back_rounded, 'Back', () => showTvCustomise(context, prefs: prefs, extras: extras)),
      ...?extras['System'],
      TvAction(
        Icons.restart_alt_rounded,
        'Reset everything',
        () => tvConfirm(
          context,
          title: 'Reset every setting?',
          action: 'Reset everything (look, rows, quick actions, colours)',
          onConfirm: () async {
            await prefs.resetTvSettings();
            await TvApps.instance.setHistoryEnabled(true);
          },
          back: () => _system(context, prefs, extras),
        ),
        danger: true,
      ),
    ],
  );
}

/// Customise's pages for a home view, each with only the options that view reads.
/// Spotlight names them its own way (its rows are columns).
List<(String, IconData, List<TvOption>)> tvSectionsFor(String view) {
  if (view == 'tiles') {
    final remote = tvSections.firstWhere((s) => s.$1 == 'Remote & behaviour');
    return [
      (
        remote.$1,
        remote.$2,
        [
          for (final o in remote.$3)
            if (o.key != 'landing') o,
        ],
      ),
    ];
  }
  final skip = view == 'spotlight' ? const {'rowsAt', 'appCards', 'rowTitles', 'resume', 'controls', 'quickLabels', 'quickSize', 'landing'} : _spotlightOnly;
  return [
    for (final (name, icon, opts) in tvSections)
      if (opts.any((o) => !skip.contains(o.key)))
        (
          view == 'spotlight' ? (_spotlightNames[name] ?? name) : name,
          icon,
          [
            for (final o in opts)
              if (!skip.contains(o.key)) o,
          ],
        ),
  ];
}

const _spotlightNames = {'Streaming apps’ rows': 'Streaming apps’ columns'};

/// A page's Cinematic name (the key of its extras) from the name the view shows.
String _baseName(String name) => _spotlightNames.entries.where((e) => e.value == name).firstOrNull?.key ?? name;

/// Straight to one Customise page (Hold OK → "Customise …" on a row): [section] is its
/// Cinematic name ('Your apps', 'Quick actions'…); the home view's own name and options are
/// used. Back returns to Customise.
void showTvSection(BuildContext context, {required Prefs prefs, required String section, required TvExtras extras}) {
  final view = prefs.homeView;
  final name = view == 'spotlight' ? (_spotlightNames[section] ?? section) : section;
  final match = tvSectionsFor(view).where((s) => s.$1 == name).firstOrNull;
  if (match == null) return showTvCustomise(context, prefs: prefs, extras: extras);
  _section(context, prefs, match.$1, match.$3, extras);
}

/// Extra rows at the end of Customise → Tiles (Add a tile, Reset Start), set by the home screen.
List<TvAction> tilesExtras = const [];

/// Customise → Tiles: its groups, then Add a tile / Reset Start.
void _tilesSection(BuildContext context, Prefs prefs, TvExtras extras) {
  showTvPanel(
    context,
    title: 'Tiles',
    refresh: prefs,
    build: () => [
      TvAction(Icons.arrow_back_rounded, 'Back', () => showTvCustomise(context, prefs: prefs, extras: extras)),
      for (final (name, icon, opts) in tvTilesGroups)
        TvAction(icon, name, () => _section(context, prefs, name, opts, extras, back: () => _tilesSection(context, prefs, extras))),
      ...tilesExtras,
    ],
  );
}

void _section(BuildContext context, Prefs prefs, String name, List<TvOption> opts, TvExtras extras, {VoidCallback? back}) {
  showTvPanel(
    context,
    title: name,
    // Search also follows the catalog (updating…, titles, last updated).
    // Remote & behaviour: Read show names turns On once switched on in Accessibility settings.
    refresh: name == 'Search'
        ? Listenable.merge([prefs, Catalog.instance])
        : (name == 'Remote & behaviour' ? Listenable.merge([prefs, TvApps.instance.shows]) : prefs),
    build: () {
      TvLook.read(prefs);
      return [
        TvAction(Icons.arrow_back_rounded, 'Back', back ?? () => showTvCustomise(context, prefs: prefs, extras: extras)),
        if (name == 'Search') ...catalogRows(context, prefs, reopen: () => _section(context, prefs, name, opts, extras)),
        for (final o in opts) _optionRow(prefs, o),
        // The home screen's own rows for this thing (Edit quick actions, All apps, unhide…).
        ...?extras[_baseName(name)],
        if (name == 'Remote & behaviour')
          // JioHotstar & co. share only "S1 E5 Firewall": the show is read off their player (text
          // only) so the episode gets its picture. Android asks for this in Accessibility.
          TvAction(
            Icons.subtitles_outlined,
            'Read show names (for episode pictures)',
            TvApps.instance.openAccessibility,
            value: TvApps.instance.shows.value.on ? 'On' : 'Off · turn on in Accessibility',
          ),
        if (name == 'Remote & behaviour')
          TvAction(
            Icons.delete_sweep_outlined,
            'Clear watch history',
            () => tvConfirm(
              context,
              title: 'Clear watch history?',
              action: 'Clear (Resume forgets what you watched)',
              onConfirm: TvApps.instance.clearHistory,
              back: () => _section(context, prefs, name, opts, extras, back: back),
            ),
          ),
      ];
    },
  );
}

/// A setting row: label, its current choice on the right; OK moves to the next choice.
TvAction _optionRow(Prefs prefs, TvOption o) {
  final current = o.read?.call(prefs) ?? TvLook.get<Object>(o.key);
  final i = o.choices.indexWhere((c) => c.$1 == current || (c.$1 is num && current is num && (c.$1 as num) == current));
  final label = i < 0 ? o.choices.first.$2 : o.choices[i].$2;
  final icon = o.choices.length == 2 && o.choices.first.$1 is bool
      ? (current == true ? Icons.toggle_on_rounded : Icons.toggle_off_outlined)
      : Icons.unfold_more_rounded;
  return TvAction(
    icon,
    o.label,
    () async {
      final next = o.choices[(i + 1) % o.choices.length].$1;
      if (o.write != null) {
        await o.write!(prefs, next);
      } else {
        await prefs.setTvSetting(o.key, next);
      }
      if (o.key == 'history') await TvApps.instance.setHistoryEnabled(next == true);
      if (o.key == 'catalogAuto') Catalog.instance.maybeUpdate(); // e.g. Off → Daily: update if it's due
    },
    keepOpen: true,
    value: label,
  );
}
