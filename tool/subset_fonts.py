"""Builds the clock font: Google Sans Flex (variable, OFL) cut down to what the big figures
need — the four axes the user can adjust (weight, width, slant, roundness), optical size pinned
for large display digits, and basic Latin characters only. Licence: assets/fonts/GoogleSansFlex-OFL.txt. The UI font (Instrument Sans)
stays complete. Source in tool/font_sources/. Run: python3 tool/subset_fonts.py"""
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'tool/font_sources/GoogleSansFlex-VF.ttf'
OUT = ROOT / 'assets/fonts/ClockFlex.ttf'
KEEP = list(range(0x20, 0x7F)) + [0xB7, 0x2013, 0x2014, 0x2026]  # ASCII, ·, – — …

font = TTFont(str(SRC))
# Keep wght / wdth / slnt / ROND adjustable; pin everything else.
pins = {a.axisTag: a.defaultValue for a in font['fvar'].axes if a.axisTag not in ('wght', 'wdth', 'slnt', 'ROND')}
pins['opsz'] = 144  # display optical size: tuned for huge digits
font = instancer.instantiateVariableFont(font, pins)

opts = subset.Options()
opts.hinting = False
opts.layout_features = ['kern', 'liga', 'tnum', 'lnum']
opts.name_IDs = [1, 2, 4, 6]
s = subset.Subsetter(opts)
s.populate(unicodes=KEEP)
s.subset(font)
font.save(str(OUT))
print(f'{SRC.name}: {SRC.stat().st_size // 1024} KB -> {OUT.name}: {OUT.stat().st_size // 1024} KB, axes',
      [(a.axisTag, a.minValue, a.maxValue) for a in TTFont(str(OUT))['fvar'].axes])
