import 'package:flutter/material.dart';

import '../prefs.dart';
import 'tv_apps.dart';
import 'tv_parts.dart';

/// One TV setting: a key in [Prefs.tvSettings], its choices (value → label) and default.
/// On/off settings are just two choices.
class TvOption {
  const TvOption(this.key, this.label, this.choices, this.fallback);
  final String key, label;
  final List<(Object, String)> choices;
  final Object fallback;

  static TvOption onOff(String key, String label, {bool on = true}) => TvOption(key, label, const [(true, 'On'), (false, 'Off')], on);
}

/// Everything the user can change, by section (Customise). Order = menu order.
const tvSections = <(String, IconData, List<TvOption>)>[
  (
    'Home screen',
    Icons.dashboard_outlined,
    [
      TvOption('hints', 'Remote hints (OK · Hold OK)', [(true, 'On'), (false, 'Off')], true),
      TvOption('hero', 'Title & details', [(true, 'On'), (false, 'Off')], true),
      TvOption('backdrop', 'Background picture', [('art', 'Artwork'), ('glow', 'Soft glow'), ('off', 'Off')], 'art'),
      TvOption('dim', 'Background darkness', [(.7, 'Light'), (1.0, 'Medium'), (1.25, 'Strong')], 1.0),
      TvOption('rowsAt', 'Rows start', [(.45, 'Higher'), (.55, 'Middle'), (.65, 'Lower')], .55),
      TvOption('clock', 'Clock', [(true, 'On'), (false, 'Off')], true),
      TvOption('clock24', 'Clock format', [('auto', 'Like the TV'), ('12', '12-hour'), ('24', '24-hour')], 'auto'),
      TvOption('date', 'Date', [(true, 'On'), (false, 'Off')], true),
    ],
  ),
  (
    'Cards & motion',
    Icons.view_carousel_outlined,
    [
      TvOption('cardScale', 'Card size', [(.85, 'Small'), (1.0, 'Medium'), (1.15, 'Large')], 1.0),
      TvOption('focus', 'Focused card', [('glow', 'Grow + glow'), ('grow', 'Grow'), ('outline', 'Outline only')], 'glow'),
      TvOption('motion', 'Animations', [('full', 'Full'), ('reduced', 'Reduced')], 'full'),
      TvOption('rowTitles', 'Row titles', [(true, 'On'), (false, 'Off')], true),
    ],
  ),
  (
    'Rows',
    Icons.table_rows_outlined,
    [
      TvOption('rowContinue', 'Continue watching', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('rowFav', 'Your apps', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('rowRecent', 'Jump back in', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('rowChannels', 'Streaming apps’ rows', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('rowFolders', 'Smart folder rows', [(true, 'Show'), (false, 'Hide')], true),
    ],
  ),
  (
    'Resume & quick actions',
    Icons.play_circle_outline_rounded,
    [
      TvOption('resume', 'Resume button', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('controls', 'Player controls ⏮ ⏯ ⏭', [(true, 'Show'), (false, 'Hide')], true),
      TvOption('quick', 'Quick actions', [(true, 'Show'), (false, 'Hide')], true),
    ],
  ),
  (
    'Remote & behaviour',
    Icons.settings_remote_outlined,
    [
      TvOption('landing', 'Start on', [('quick', 'First quick action'), ('resume', 'Resume'), ('app', 'First app'), ('search', 'Search')], 'quick'),
      TvOption('back', 'Back button', [('home', 'Go to start'), ('search', 'Go to Search'), ('none', 'Do nothing')], 'home'),
      TvOption('history', 'Remember what I watch', [(true, 'On'), (false, 'Off')], true),
    ],
  ),
];

/// The settings as the home screen reads them (refreshed from prefs on every build).
class TvLook {
  static Map<String, dynamic> _s = const {};

  static void read(Prefs p) => _s = p.tvSettings;

  static T get<T>(String key) {
    final v = _s[key];
    if (v is T) return v;
    if (T == double && v is num) return v.toDouble() as T;
    for (final (_, _, opts) in tvSections) {
      for (final o in opts) {
        if (o.key == key) return o.fallback as T;
      }
    }
    throw ArgumentError('unknown TV setting $key');
  }

  static bool on(String key) => get<bool>(key);
  static double number(String key) => get<double>(key);
  static String str(String key) => get<String>(key);

  /// Reduced motion: every transition snaps (or nearly).
  static Duration anim(Duration d) => str('motion') == 'reduced' ? const Duration(milliseconds: 1) : d;
}

/// Customise: sections → options (each OK steps to the next choice; the home screen behind
/// the panel updates as you go). [extras] adds the sections that live in the home screen
/// (quick actions editor, colours, apps).
void showTvCustomise(BuildContext context, {required Prefs prefs, required List<TvAction> extras}) {
  showTvPanel(
    context,
    title: 'Customise',
    actions: [
      for (final (name, icon, opts) in tvSections) TvAction(icon, name, () => _section(context, prefs, name, opts, extras)),
      ...extras,
      TvAction(Icons.restart_alt_rounded, 'Reset everything', () async {
        await prefs.resetTvSettings();
        await TvApps.instance.setHistoryEnabled(true);
      }, danger: true),
    ],
  );
}

void _section(BuildContext context, Prefs prefs, String name, List<TvOption> opts, List<TvAction> extras) {
  showTvPanel(
    context,
    title: name,
    refresh: prefs,
    build: () {
      TvLook.read(prefs);
      return [
        TvAction(Icons.arrow_back_rounded, 'Back', () => showTvCustomise(context, prefs: prefs, extras: extras)),
        for (final o in opts) _optionRow(prefs, o),
        if (name == 'Remote & behaviour') TvAction(Icons.delete_sweep_outlined, 'Clear watch history', TvApps.instance.clearHistory, keepOpen: true),
      ];
    },
  );
}

/// A setting row: label, its current choice on the right; OK moves to the next choice.
TvAction _optionRow(Prefs prefs, TvOption o) {
  final current = TvLook.get<Object>(o.key);
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
      await prefs.setTvSetting(o.key, next);
      if (o.key == 'history') await TvApps.instance.setHistoryEnabled(next == true);
    },
    keepOpen: true,
    value: label,
  );
}
