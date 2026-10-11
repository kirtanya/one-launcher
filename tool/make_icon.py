"""Generates every app icon from the design tokens (docs/DESIGN_STYLE.md).
Run: python3 tool/make_icon.py
Look: dark canvas, pastel-green circle, ink "1", pink notification dot."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CANVAS, HERO, HERO_INK, DOT = (0x1F, 0x1F, 0x1F), (0xCF, 0xE9, 0xBC), (0x0D, 0x1F, 0x00), (0xEF, 0x73, 0x89)
FONT = ROOT / 'assets/fonts/InstrumentSans-600.ttf'
S = 4  # supersample


def mark(size, circle_frac, bg=CANVAS, mono=False):
    """Square image: optional background, centred circle with '1' and dot."""
    n = size * S
    im = Image.new('RGBA', (n, n), bg + (255,) if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = n * circle_frac / 2
    c = n / 2
    fill = (255, 255, 255, 255) if mono else HERO + (255,)
    d.ellipse([c - r, c - r, c + r, c + r], fill=fill)
    font = ImageFont.truetype(str(FONT), int(r * 1.25))
    ink = (0, 0, 0, 0) if mono else HERO_INK + (255,)
    # Optical centre: measure the glyph box and centre it.
    l, t, rr, b = d.textbbox((0, 0), '1', font=font)
    d.text((c - (l + rr) / 2 - r * 0.03, c - (t + b) / 2), '1', font=font, fill=ink)
    # Notification dot at ~45° on the circle edge, ringed in the background colour.
    dr = r * 0.2
    dx, dy = c + r * 0.70, c - r * 0.70
    ring = dr * 1.45
    if mono:
        d.ellipse([dx - ring, dy - ring, dx + ring, dy + ring], fill=(0, 0, 0, 0))
        d.ellipse([dx - dr, dy - dr, dx + dr, dy + dr], fill=(255, 255, 255, 255))
    else:
        d.ellipse([dx - ring, dy - ring, dx + ring, dy + ring], fill=(bg or CANVAS) + (255,))
        d.ellipse([dx - dr, dy - dr, dx + dr, dy + dr], fill=DOT + (255,))
    return im.resize((size, size), Image.LANCZOS)


def rounded(im, radius_frac=0.225):
    n = im.size[0]
    m = Image.new('L', (n * S, n * S), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, n * S - 1, n * S - 1], radius=n * S * radius_frac, fill=255)
    out = im.copy()
    out.putalpha(m.resize((n, n), Image.LANCZOS))
    return out


res = ROOT / 'android/app/src/main/res'
dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, k in dens.items():
    folder = res / f'mipmap-{name}'
    folder.mkdir(exist_ok=True)
    # Legacy (pre-Android 8) icon: rounded square.
    rounded(mark(int(48 * k), 0.62)).save(folder / 'ic_launcher.png')
    # Adaptive layers are 108dp; the visible safe zone is the middle 66dp.
    mark(int(108 * k), 0.40, bg=None).save(folder / 'ic_launcher_foreground.png')
    mark(int(108 * k), 0.40, bg=None, mono=True).save(folder / 'ic_launcher_monochrome.png')

(res / 'mipmap-anydpi-v26').mkdir(exist_ok=True)
(res / 'mipmap-anydpi-v26/ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
''')
(res / 'values/colors.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#1F1F1F</color>
</resources>
''')

web = ROOT / 'web'
rounded(mark(512, 0.62)).save(ROOT / 'docs/app_icon.png')
mark(192, 0.62).save(web / 'icons/Icon-192.png')
mark(512, 0.62).save(web / 'icons/Icon-512.png')
mark(192, 0.45).save(web / 'icons/Icon-maskable-192.png')
mark(512, 0.45).save(web / 'icons/Icon-maskable-512.png')
rounded(mark(64, 0.7)).save(web / 'favicon.png')
print('icons written')
