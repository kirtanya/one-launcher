"""Play Store graphics → store/: 512 px icon, 1024×500 feature graphic, framed screenshots.
Screenshots come from the app itself: `flutter test --update-goldens test/store_shots_test.dart`
writes store/raw/*.png (1080×2160), this frames them as 1080×1920 with a headline.
Run: python3 tool/store_assets.py"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'store'
# The icon drawing (mark) is shared with tool/make_icon.py; load just its functions.
src = (ROOT / 'tool/make_icon.py').read_text().split('\nres = ')[0]
icon_ns = {'__file__': str(ROOT / 'tool/make_icon.py')}
exec(src, icon_ns)
mark, CANVAS, HERO, HERO_INK = icon_ns['mark'], icon_ns['CANVAS'], icon_ns['HERO'], icon_ns['HERO_INK']

F600 = str(ROOT / 'assets/fonts/InstrumentSans-600.ttf')
F400 = str(ROOT / 'assets/fonts/InstrumentSans-400.ttf')
WHITE, MUTED = (255, 255, 255), (0xB4, 0xB4, 0xB4)


def font(path, size):
    return ImageFont.truetype(path, size)


def rounded_shot(im, radius):
    m = Image.new('L', im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1], radius=radius, fill=255)
    out = im.convert('RGBA')
    out.putalpha(m)
    return out


def phone(shot_path, height):
    """Screenshot scaled to [height] with rounded corners, a thin rim and a soft shadow."""
    im = Image.open(shot_path).convert('RGB')
    w = round(im.size[0] * height / im.size[1])
    im = rounded_shot(im.resize((w, height), Image.LANCZOS), radius=int(height * .045))
    pad = 60
    framed = Image.new('RGBA', (w + pad * 2, height + pad * 2), (0, 0, 0, 0))
    shadow = Image.new('RGBA', framed.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([pad, pad + 18, pad + w, pad + height + 18], radius=int(height * .045), fill=(0, 0, 0, 150))
    framed = Image.alpha_composite(framed, shadow.filter(ImageFilter.GaussianBlur(28)))
    rim = Image.new('RGBA', framed.size, (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([pad - 6, pad - 6, pad + w + 5, pad + height + 5], radius=int(height * .045) + 6, fill=(0x3A, 0x3A, 0x3A, 255))
    framed = Image.alpha_composite(framed, rim)
    framed.alpha_composite(im, (pad, pad))
    return framed


def centered(d, y, text, f, fill, width):
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    d.text(((width - (r - l)) / 2 - l, y), text, font=f, fill=fill)


SHOTS = [
    ('1_home', 'One calm screen', 'Clock on top, all your apps below'),
    ('2_screen_time', 'Glance, then go', 'Screen time, battery, plans and music up top'),
    ('3_folder', 'Apps sort themselves', 'Smart folders open right where you look'),
    ('4_search', 'Find any app fast', 'Search sits right under your thumb'),
    ('5_settings', 'Make it yours', 'Layout, wallpaper, quick actions and more'),
    ('6_colours', 'Your colours', 'Follows your wallpaper, or pick your own'),
]


def screenshots():
    W, H = 1080, 1920
    for name, title, sub in SHOTS:
        c = Image.new('RGBA', (W, H), CANVAS + (255,))
        d = ImageDraw.Draw(c)
        # A soft green glow behind the phone, in the app's hero colour.
        glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse([W * .1, H * .38, W * .9, H * 1.05], fill=HERO + (70,))
        c = Image.alpha_composite(c, glow.filter(ImageFilter.GaussianBlur(120)))
        d = ImageDraw.Draw(c)
        centered(d, 120, title, font(F600, 78), WHITE, W)
        centered(d, 228, sub, font(F400, 38), MUTED, W)
        p = phone(ROOT / f'store/raw/{name}.png', 1480)
        c.alpha_composite(p, ((W - p.size[0]) // 2, 330))
        c.convert('RGB').save(OUT / f'screenshots/{name}.png', optimize=True)


def feature_graphic():
    W, H = 1024, 500
    c = Image.new('RGBA', (W, H), CANVAS + (255,))
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([560, 40, 1100, 620], fill=HERO + (90,))
    c = Image.alpha_composite(c, glow.filter(ImageFilter.GaussianBlur(90)))
    ic = mark(150, 0.92, bg=None)
    c.alpha_composite(ic, (64, 96))
    d = ImageDraw.Draw(c)
    d.text((64, 268), 'One Launcher', font=font(F600, 66), fill=WHITE)
    d.text((66, 352), 'Your whole phone on one calm screen', font=font(F400, 30), fill=MUTED)
    p = phone(ROOT / 'store/raw/1_home.png', 640)
    c.alpha_composite(p, (W - p.size[0] + 40, 30))
    c.convert('RGB').save(OUT / 'feature-graphic.png', optimize=True)


def icon():
    # Full square (Play rounds it), no transparency.
    mark(512, 0.62).convert('RGB').save(OUT / 'icon-512.png', optimize=True)


icon()
feature_graphic()
screenshots()
print('store/: icon-512.png, feature-graphic.png, screenshots/*.png')
