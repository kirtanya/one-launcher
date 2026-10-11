"""Shrinks the big-figure fonts (clock, screen time, battery %, event time) to the characters
they can ever show: basic Latin + a few symbols. The UI font (Instrument Sans) stays complete.
Originals live in tool/font_sources/. Run: python3 tool/subset_fonts.py"""
from pathlib import Path
from fontTools import subset

ROOT = Path(__file__).resolve().parent.parent
SRC, OUT = ROOT / 'tool/font_sources', ROOT / 'assets/fonts'
KEEP = list(range(0x20, 0x7F)) + [0xB7, 0x2013, 0x2014, 0x2026]  # ASCII, ·, – — …

for src in sorted(SRC.glob('*.ttf')):
    opts = subset.Options()
    opts.hinting = False  # screens are high-DPI; hinting is unused weight
    opts.layout_features = ['kern', 'liga', 'tnum', 'lnum']
    opts.name_IDs = [1, 2, 4, 6]  # keep only the basic names
    font = subset.load_font(str(src), opts)
    s = subset.Subsetter(opts)
    s.populate(unicodes=KEEP)
    s.subset(font)
    out = OUT / src.name
    subset.save_font(font, str(out), opts)
    print(f'{src.name}: {src.stat().st_size // 1024} KB -> {out.stat().st_size // 1024} KB')
