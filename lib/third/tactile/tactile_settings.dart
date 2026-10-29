import 'package:flutter/material.dart';

import '../../prefs.dart';
import '../../sheets.dart' show showEditor;
import 'parts.dart';
import 'tactile.dart';

/// Settings → Look → Tactile style: the third view's own theming (it doesn't use Material's
/// Colours & style). The plastic (finish, how light), the colour of its light (LEDs, displays),
/// a coloured cap, and whether keys click. Live on the home preview above.
Future<Object?> showTactileStyle(BuildContext context, {required Prefs prefs}) => showEditor(
  context,
  title: 'Tactile style',
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
          TKnobRow(
            title: 'Lightness',
            readout: prefs.tactileLightness == .5 ? 'AS MOULDED' : '${prefs.tactileLightness < .5 ? 'DARKER' : 'LIGHTER'} ${((prefs.tactileLightness - .5).abs() * 10).round()}',
            value: prefs.tactileLightness,
            steps: 10,
            onChanged: (v) => prefs.setTactile(lightness: v),
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
