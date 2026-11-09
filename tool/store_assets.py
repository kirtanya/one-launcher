"""Play Store graphics → store/: framed screenshots (1080×1920) and the 1024×500 feature graphic.
Inputs:
- store/raw/*.png (1080×2160): `python3 tool/store_icons.py`, then
  `flutter test --update-goldens --dart-define=PLAY_BUILD=true test/store_shots_test.dart`
- the app icon from ~/one-logos (the "Glass O" family): store/icon-512.png is its full-bleed square
  (render svg/one-launcher.svg without the tile's rx with `swift render.swift … 512`; Play rounds it).
Run: python3 tool/store_assets.py  (needs Pillow)"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'store'
RAW = Path(__import__('os').environ.get('STORE_RAW', ROOT / 'store/raw'))
LOGO = Path.home() / 'one-logos/png/one-launcher-1024.png'  # rounded tile, transparent corners

F600 = str(ROOT / 'assets/fonts/InstrumentSans-600.ttf')
F500 = str(ROOT / 'assets/fonts/InstrumentSans-500.ttf')
F400 = str(ROOT / 'assets/fonts/InstrumentSans-400.ttf')
# The icon's greens (one-logos HUES['green']) and the app's light canvas.
G_TOP, G_BOTTOM, G_DEEP = (0x2F, 0xD0, 0x8A), (0x0E, 0x9A, 0x62), (0x06, 0x2E, 0x20)
INK, MUTED, PAPER, MINT = (0x10, 0x20, 0x1A), (0x55, 0x66, 0x5E), (0xF5, 0xF7, 0xF2), (0xD9, 0xF2, 0xE4)
WHITE = (255, 255, 255)
S = 2  # supersample for shapes


def font(path, size):
    return ImageFont.truetype(path, size)


def vgrad(w, h, top, bottom):
    g = Image.new('RGB', (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((w, h), Image.BICUBIC).convert('RGBA')


def glow(size, box, colour, alpha, blur):
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=colour + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def rrect_mask(w, h, r):
    m = Image.new('L', (w * S, h * S), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * S - 1, h * S - 1], radius=r * S, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def phone(shot_path, height, shadow=110):
    """Screenshot in a slim black phone body: 2.6% bezel, rounded screen, light rim, soft shadow."""
    im = Image.open(shot_path).convert('RGBA')
    sw = round(im.size[0] * height / im.size[1])
    screen = im.resize((sw, height), Image.LANCZOS)
    b = max(8, round(sw * .026))  # bezel
    w, h = sw + b * 2, height + b * 2
    r_out, r_in = round(w * .12), round(sw * .10)
    pad = round(h * .06)
    out = Image.new('RGBA', (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    sh = Image.new('RGBA', out.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([pad + w * .04, pad + h * .03, pad + w * .96, pad + h * 1.01], radius=r_out, fill=(8, 30, 20, shadow))
    out = Image.alpha_composite(out, sh.filter(ImageFilter.GaussianBlur(pad * .45)))
    body = Image.new('RGBA', (w, h), (0x14, 0x16, 0x15, 255))
    rim = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([1, 1, w - 2, h - 2], radius=r_out - 1, outline=(0x5A, 0x60, 0x5C, 255), width=2)
    body = Image.alpha_composite(body, rim)
    body.putalpha(rrect_mask(w, h, r_out))
    screen.putalpha(rrect_mask(sw, height, r_in))
    body.alpha_composite(screen, (b, b))
    out.alpha_composite(body, (pad, pad))
    return out, pad


def centered(d, y, text, f, fill, width):
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    d.text(((width - (r - l)) / 2 - l, y), text, font=f, fill=fill)


def pill(c, x_center, y, text, f, fg, bg):
    d = ImageDraw.Draw(c)
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    px, h = 26, 54
    w = r - l + px * 2
    box = Image.new('RGBA', (w, h), bg + (255,))
    box.putalpha(rrect_mask(w, h, h // 2))
    x = round(x_center - w / 2)
    c.alpha_composite(box, (x, y))
    d.text((x + px - l, y + (h - (b - t)) / 2 - t), text, font=f, fill=fg)


SHOTS = [  # raw name, tag, headline, line
    ('1_home', 'Home', 'One calm screen', 'Clock, quick actions and your apps together'),
    ('2_screen_time', 'Screen time', 'Know your day at a glance', 'Today’s screen time and top apps, right on home'),
    ('3_folder', 'Smart folders', 'Apps sort themselves', 'Folders group apps by what they do'),
    ('4_search', 'Search', 'Find any app in a tap', 'Type a letter, open what you need'),
    ('5_settings', 'Settings', 'Make it yours', 'Layout, look, search and more, in plain words'),
    ('6_colours', 'Colours', 'Your colours, your style', 'Match your wallpaper or pick your own'),
]


def screenshots():
    W, H = 1080, 1920
    (OUT / 'screenshots').mkdir(exist_ok=True)
    for name, tag, title, line in SHOTS:
        c = vgrad(W, H, PAPER, MINT)
        c = Image.alpha_composite(c, glow((W, H), [W * .08, H * .42, W * .92, H * 1.1], G_TOP, 120, 140))
        pill(c, W / 2, 112, tag, font(F600, 30), G_DEEP, (0xC4, 0xEC, 0xD5))
        d = ImageDraw.Draw(c)
        centered(d, 196, title, font(F600, 76), INK, W)
        centered(d, 298, line, font(F400, 36), MUTED, W)
        p, pad = phone(RAW / f'{name}.png', 1400)
        c.alpha_composite(p, ((W - p.size[0]) // 2, 410 - pad))
        c.convert('RGB').save(OUT / f'screenshots/{name}.png', optimize=True)


def feature_graphic():
    W, H = 1024, 500
    c = vgrad(W, H, (0x0B, 0x4D, 0x35), G_DEEP)
    c = Image.alpha_composite(c, glow((W, H), [560, -120, 1160, 560], G_TOP, 150, 110))
    c = Image.alpha_composite(c, glow((W, H), [-200, 300, 420, 760], G_BOTTOM, 90, 120))
    logo = Image.open(LOGO).convert('RGBA').resize((104, 104), Image.LANCZOS)
    c.alpha_composite(logo, (64, 104))
    d = ImageDraw.Draw(c)
    d.text((62, 232), 'One Launcher', font=font(F600, 60), fill=WHITE)
    sub = (0xCF, 0xEE, 0xDE)
    d.text((64, 314), 'A calm home screen for Android', font=font(F400, 27), fill=sub)
    d.text((64, 350), 'Smart folders, screen time, your colours', font=font(F400, 27), fill=sub)
    # Two phones on the right, running off the bottom edge: home in front, a folder behind.
    back, pb = phone(RAW / '3_folder.png', 540, shadow=150)
    front, pf = phone(RAW / '1_home.png', 600, shadow=170)
    c.alpha_composite(back, (800 - pb, 52 - pb))
    c.alpha_composite(front, (588 - pf, 84 - pf))
    c.convert('RGB').save(OUT / 'feature-graphic.png', optimize=True)


feature_graphic()
screenshots()
print('store/: feature-graphic.png, screenshots/*.png (icon-512.png comes from ~/one-logos)')
