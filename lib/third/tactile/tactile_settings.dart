import 'package:flutter/material.dart';

import '../../prefs.dart';
import '../../sheets.dart' show showEditor;
import 'parts.dart';
import 'tactile.dart';

/// Settings → Look → Real style (the Real view's language, Tactile): the third view's own theming (it doesn't use Material's
/// Colours & style). The plastic (finish, how light), the colour of its light (LEDs, displays),
/// a coloured cap, and whether keys click. Live on the home preview above.
Future<Object?> showTactileStyle(BuildContext context, {required Prefs prefs}) => showEditor(
  context,
  title: 'Real style',
  prefs: prefs,
  view: 'third',
  builder: (ctx) => ListenableBuilder(
    listenable: prefs,
    builder: (ctx, _) {
      Widget legend(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
        child: Text(
          t.toUpperCase(),
          style: TextStyle(fontFamily: Tactile.legendFont, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: Tactile.inkMuted, shadows: Tactile.emboss),
        ),
      );
      Widget keys(List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      );
      Widget label(String t) => Text(
        t.toUpperCase(),
        style: TextStyle(fontFamily: Tactile.legendFont, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Tactile.ink),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          legend('Finish'),
          keys([
            for (final (id, name) in Tactile.finishes)
              TKey(
                height: 40,
                width: null,
                latched: prefs.tactileFinish == id,
                onTap: () => prefs.setTactile(finish: id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [TLed(on: prefs.tactileFinish == id, size: 6), const SizedBox(width: 8), label(name)]),
                ),
              ),
          ]),
          legend('Type'),
          keys([
            for (final (id, name, family) in Tactile.faces)
              TKey(
                height: 44,
                width: null,
                latched: prefs.tactileFace == id,
                led: prefs.tactileFace == id,
                onTap: () => prefs.setTactile(face: id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  // Each in its own face.
                  child: Text(name, style: TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w600, color: Tactile.ink)),
                ),
              ),
          ]),
          legend('Light'),
          keys([
            for (final (id, name) in Tactile.lights)
              TKey(
                height: 40,
                width: null,
                latched: prefs.tactileLight == id,
                onTap: () => prefs.setTactile(light: id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The LED in its own colour, lit when chosen.
                      TLed(on: true, size: 8, color: id == 'theme' ? (prefs.tactileLight == 'theme' ? Tactile.light : Tactile.ledOff) : Color(int.parse(id, radix: 16))),
                      const SizedBox(width: 8),
                      label(name),
                    ],
                  ),
                ),
              ),
          ]),
          legend('Cap'),
          keys([
            for (final (id, name) in Tactile.caps)
              TKey(
                height: 40,
                width: null,
                latched: prefs.tactileCap == id,
                led: prefs.tactileCap == id,
                tint: id == 'none' ? null : Color(int.parse(id, radix: 16)),
                onTap: () => prefs.setTactile(cap: id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    name.toUpperCase(),
                    style: TextStyle(
                      fontFamily: Tactile.legendFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: id == 'none' ? Tactile.ink : Colors.white,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          // Lightness: one for the light finishes, one for Graphite (the same step doesn't suit
          // both); 10 steps darker, 10 lighter.
          _LightnessSlider(
            title: 'Lightness · Porcelain, Concrete',
            value: prefs.tactileLightness,
            onChanged: (v) => prefs.setTactile(lightness: v),
          ),
          _LightnessSlider(
            title: 'Lightness · Graphite',
            value: prefs.tactileLightnessDark,
            onChanged: (v) => prefs.setTactile(lightnessDark: v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 16, 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label('Key clicks'),
                      const SizedBox(height: 2),
                      Text('The phone’s click sound with each press (with Touch sounds on)', style: TextStyle(fontSize: 13, color: Tactile.inkMuted)),
                    ],
                  ),
                ),
                TSwitch(value: prefs.tactileSounds, onChanged: (v) => prefs.setTactile(sounds: v)),
              ],
            ),
          ),
        ],
      );
    },
  ),
);

/// "AS MOULDED", "DARKER 7", "LIGHTER 3" (steps of 1/20).
String _readout(double v) => (v - .5).abs() < .01 ? 'AS MOULDED' : '${v < .5 ? 'DARKER' : 'LIGHTER'} ${((v - .5).abs() * 20).round()}';

/// Lightness as a fader (easier to set than a knob): the legend and its readout above, the
/// slider below — darker to the left, lighter to the right, a tick at each of the 20 steps.
class _LightnessSlider extends StatelessWidget {
  const _LightnessSlider({required this.title, required this.value, required this.onChanged});
  final String title;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: TextStyle(fontFamily: Tactile.legendFont, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: Tactile.inkMuted),
              ),
            ),
            TLcd(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              radius: 8,
              child: DotMatrix(_readout(value), dot: 2, color: TLcd.text),
            ),
          ],
        ),
        Row(
          children: [
            Icon(Icons.dark_mode_outlined, size: 18, color: Tactile.inkMuted),
            Expanded(
              child: Slider(
                value: value,
                divisions: 20,
                onChanged: (v) {
                  if ((v * 20).round() != (value * 20).round()) TactileFeel.tick();
                  onChanged(v);
                },
              ),
            ),
            Icon(Icons.light_mode_outlined, size: 18, color: Tactile.inkMuted),
          ],
        ),
      ],
    ),
  );
}
