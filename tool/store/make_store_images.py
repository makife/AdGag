"""Google Play listing images for AdGag: 8 phone screenshots (1080x1920) per
language + the 1024x500 feature graphic.

    python tool/store/make_store_images.py                 # mock screens
    python tool/store/make_store_images.py --screens DIR   # real screenshots

The phone screens are MOCKUPS drawn in the app's real design (colours,
Roboto, Material icons, the SOLD / REVIEWS / AD THIS / GAG! rail, the editor
timeline). Google wants listing images to show the actual app, so before
publishing, take real screenshots on a phone, name them 01.png..08.png (one
per slide, same order as SLIDES below), and pass --screens: each replaces
that slide's mock inside the same frame, with the same headline.

Output: build/app/outputs/flutter-apk/play-store/<lang>/NN.png and
feature-graphic.png.
"""
import argparse
import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FONTS = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'assets', 'fonts')
MAT = r'C:/flutter/bin/cache/artifacts/material_fonts'
OUT = os.path.join(ROOT, 'build', 'app', 'outputs', 'flutter-apk', 'play-store')

W, H = 1080, 1920
BG = (7, 16, 15)
TURQ = (22, 197, 192)
DEEP = (43, 108, 230)
OCEAN = (31, 163, 201)
MINT = (62, 230, 168)
WHITE = (245, 245, 247)
MUTED = (160, 160, 168)
SURF = (18, 18, 20)
SURF2 = (28, 28, 31)
OCEAN_BAR = (31, 163, 201)


def font(name, size):
    path = {
        'head': os.path.join(FONTS, 'Poppins-Bold.ttf'),
        'ad': os.path.join(FONTS, 'Anton-Regular.ttf'),
        'ui': os.path.join(MAT, 'roboto-regular.ttf'),
        'uim': os.path.join(MAT, 'roboto-medium.ttf'),
        'uib': os.path.join(MAT, 'roboto-bold.ttf'),
        'icon': os.path.join(MAT, 'materialicons-regular.otf'),
    }[name]
    return ImageFont.truetype(path, size)


ICON = {
    'sell': 0xe570, 'sell_o': 0xf353, 'chat': 0xe155, 'bolt': 0xe0ee, 'bolt_o': 0xeedd, 'reply': 0xe528,
    'more': 0xe404, 'home': 0xe318, 'store': 0xf3ef, 'person_o': 0xe497, 'volume': 0xe6c5, 'eq': 0xe2e3,
    'text': 0xe649, 'slowmo': 0xe5c1, 'music': 0xe415, 'emoji': 0xe22b, 'fx': 0xe0bb, 'rotate': 0xe540,
    'play': 0xe4cb, 'add': 0xe047, 'search': 0xe567, 'fire': 0xe392, 'menu': 0xe3dc, 'sparkle': 0xe0b7,
    'tune': 0xe683,
}


def icon(d, name, xy, size, fill, anchor='mm'):
    d.text(xy, chr(ICON[name]), font=font('icon', size), fill=fill, anchor=anchor)


def grad(size, stops, horizontal=True):
    """Linear gradient image through the given colour stops."""
    w, h = size
    img = Image.new('RGB', size)
    px = img.load()
    n = len(stops) - 1
    length = w if horizontal else h
    for i in range(length):
        t = i / max(length - 1, 1) * n
        k = min(int(t), n - 1)
        f = t - k
        c = tuple(int(stops[k][j] + (stops[k + 1][j] - stops[k][j]) * f) for j in range(3))
        if horizontal:
            for y in range(h):
                px[i, y] = c
        else:
            for x in range(w):
                px[x, i] = c
    return img


BRAND = [DEEP, OCEAN, TURQ, MINT]


def rounded_mask(size, r):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], r, fill=255)
    return m


def sticker(code, size):
    """First frame of a bundled Noto animated emoji (CC BY 4.0)."""
    meta = {s['id']: s for s in json.load(open(os.path.join(ROOT, 'android/app/src/main/assets/stickers/stickers.json'), encoding='utf-8'))}[code]
    sheet = Image.open(os.path.join(ROOT, 'android/app/src/main/assets/stickers', meta['file'])).convert('RGBA')
    cell = meta['size']
    return sheet.crop((0, 0, cell, cell)).resize((size, size), Image.LANCZOS)


def ad_title(d, xy, text, size, **kw):
    """Anton title with a small Roboto (TM) mark: Anton's own glyph reads as 'TM'."""
    base = text.replace('™', '')
    f = font('ad', size)
    w_ = d.textlength(base, font=f)
    x, y = xy
    left = x - (w_ + size * 0.3) / 2
    d.text((left, y), base, font=f, anchor='lm', **kw)
    if base != text:
        d.text((left + w_ + 4, y - size * 0.32), '™', font=font('uib', int(size * 0.3)), anchor='lm', **kw)


def wrap(d, text, fnt, width):
    words, lines, cur = text.split(), [], ''
    for w_ in words:
        t = (cur + ' ' + w_).strip()
        if d.textlength(t, font=fnt) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = w_
    if cur:
        lines.append(cur)
    return lines


# ------------------------------------------------------------------ screens
SW, SH = 780, 1690  # phone screen


def status_bar(d, dark=True):
    c = WHITE if dark else (20, 20, 20)
    d.text((40, 30), '9:41', font=font('uim', 30), fill=c)
    d.rounded_rectangle([SW - 110, 36, SW - 50, 62], 6, outline=c, width=3)
    d.rectangle([SW - 105, 41, SW - 70, 57], fill=c)


NAV = ['Home', 'Market', 'Activity', 'Profile']


def nav_bar(img, d, active=0):
    y0 = SH - 150
    d.rectangle([0, y0, SW, SH], fill=(10, 10, 12))
    d.line([0, y0, SW, y0], fill=(40, 40, 44), width=2)
    items = [('home', NAV[0]), ('store', NAV[1]), (None, 'AD'), ('bolt_o', NAV[2]), ('person_o', NAV[3])]
    for i, (ic, label) in enumerate(items):
        cx = int(SW * (i + 0.5) / 5)
        if ic is None:
            pill = grad((120, 62), BRAND)
            img.paste(pill, (cx - 60, y0 + 30), rounded_mask((120, 62), 20))
            d.text((cx, y0 + 61), 'AD', font=font('uib', 30), fill=WHITE, anchor='mm')
            continue
        col = TURQ if i == active else MUTED
        icon(d, ic, (cx, y0 + 52), 46, col)
        d.text((cx, y0 + 98), label, font=font('ui', 22), fill=col, anchor='mm')


def rail_button(img, d, cx, cy, ic, label, color=WHITE, glow=False):
    if glow:
        halo = Image.new('RGBA', (160, 160), (0, 0, 0, 0))
        ImageDraw.Draw(halo).ellipse([20, 20, 140, 140], fill=TURQ + (150,))
        halo = halo.filter(ImageFilter.GaussianBlur(18))
        img.paste(halo, (cx - 80, cy - 80), halo)
    d.ellipse([cx - 40, cy - 40, cx + 40, cy + 40], fill=(0, 0, 0, 110))
    icon(d, ic, (cx, cy), 46, color)
    d.text((cx, cy + 62), label, font=font('uib', 22), fill=WHITE, anchor='mm')


def feed_screen(title, tagline, user, emoji, colors, sold='12.8K', burst=False, highlight_adthis=False,
                reviews='342', gag='1.2K', caption=''):
    img = grad((SW, SH), colors, horizontal=False).convert('RGBA')
    # soft vignette
    vig = Image.new('RGBA', (SW, SH), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vig)
    vd.rectangle([0, SH - 700, SW, SH], fill=(0, 0, 0, 120))
    vig = vig.filter(ImageFilter.GaussianBlur(120))
    img = Image.alpha_composite(img, vig)
    d = ImageDraw.Draw(img)
    # the "ad" itself: product + big title + tagline, like an in-video caption
    s = sticker(emoji, 380)
    img.paste(s, ((SW - 380) // 2, 250), s)
    ad_title(d, (SW // 2, 720), title, 128, fill=WHITE, stroke_width=4, stroke_fill=(0, 0, 0))
    d.text((SW // 2, 820), tagline, font=font('uib', 40), fill=WHITE, anchor='mm', stroke_width=3, stroke_fill=(0, 0, 0))
    status_bar(d)
    # right rail
    x = SW - 70
    rail_button(img, d, x, 880 + 60, 'sell', sold, color=TURQ if burst else WHITE)
    rail_button(img, d, x, 1030 + 60, 'chat', reviews)
    rail_button(img, d, x, 1180 + 60, 'bolt', 'AD THIS', color=MINT, glow=highlight_adthis)
    rail_button(img, d, x, 1330 + 60, 'reply', gag)
    if burst:
        d.text((x - 70, 940), 'Sold!', font=font('head', 44), fill=TURQ, anchor='rm', stroke_width=3, stroke_fill=(0, 0, 0))
    # bottom-left overlay: subject chip, creator, caption
    chip_w = int(d.textlength(title, font=font('uib', 30))) + 70
    d.rounded_rectangle([30, 1300, 30 + chip_w, 1356], 28, fill=(0, 0, 0, 150))
    d.ellipse([48, 1320, 64, 1336], fill=TURQ)
    d.text((76, 1328), title, font=font('uib', 30), fill=WHITE, anchor='lm')
    d.ellipse([30, 1378, 74, 1422], fill=OCEAN)
    d.text((52, 1400), user[1].upper(), font=font('uib', 24), fill=WHITE, anchor='mm')
    d.text((88, 1400), user, font=font('uim', 28), fill=(220, 220, 225), anchor='lm')
    if caption:
        d.text((30, 1450), caption, font=font('ui', 28), fill=WHITE)
    # scrubber
    d.rectangle([0, SH - 158, SW, SH - 154], fill=(255, 255, 255, 80))
    d.rectangle([0, SH - 158, int(SW * 0.42), SH - 154], fill=WHITE)
    nav_bar(img, d, 0)
    return img


def picker_screen(l):
    img = Image.new('RGBA', (SW, SH), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    status_bar(d)
    d.text((40, 150), l['pick_title'], font=font('uim', 40), fill=WHITE)
    d.rounded_rectangle([40, 250, SW - 40, 350], 18, outline=TURQ, width=3)
    d.text((70, 300), 'Monday', font=font('ui', 38), fill=WHITE, anchor='lm')
    d.rectangle([228, 272, 231, 328], fill=TURQ)
    d.text((40, 400), l['pick_hint'], font=font('ui', 28), fill=MUTED)
    chips = ['ROCK™', 'COFFEE™', 'MONDAY™', 'ME™', 'SOCK™', 'SLEEP™', 'RAIN™', 'MY CAT™']
    x, y = 40, 470
    for c in chips:
        w_ = int(d.textlength(c, font=font('uib', 32))) + 60
        if x + w_ > SW - 40:
            x, y = 40, y + 100
        d.rounded_rectangle([x, y, x + w_, y + 76], 38, fill=SURF2)
        d.text((x + w_ // 2, y + 38), c, font=font('uib', 32), fill=WHITE, anchor='mm')
        x += w_ + 20
    # big emoji row of "anything"
    for i, e in enumerate(['1f634', '1f37f', '1f48e', '1f451']):
        s = sticker(e, 150)
        img.paste(s, (70 + i * 170, 820), s)
    btn = grad((SW - 80, 110), BRAND)
    img.paste(btn, (40, SH - 360), rounded_mask((SW - 80, 110), 55))
    d.text((SW // 2, SH - 305), l['next'], font=font('uib', 38), fill=WHITE, anchor='mm')
    nav_bar(img, d, 2)
    return img


def editor_screen(l):
    img = Image.new('RGBA', (SW, SH), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    status_bar(d)
    d.rounded_rectangle([30, 90, 190, 150], 30, fill=(40, 40, 44))
    d.text((110, 120), l['cancel'], font=font('uim', 28), fill=WHITE, anchor='mm')
    nb = grad((150, 60), BRAND)
    img.paste(nb, (SW - 180, 90), rounded_mask((150, 60), 30))
    d.text((SW - 105, 120), l['next'], font=font('uib', 28), fill=WHITE, anchor='mm')
    # preview
    pv = grad((420, 746), [(255, 176, 70), (255, 111, 97)], horizontal=False).convert('RGBA')
    s = sticker('1f37f', 260)
    pv.paste(s, (80, 200), s)
    pd = ImageDraw.Draw(pv)
    ad_title(pd, (210, 560), 'POPCORN™', 76, fill=WHITE, stroke_width=3, stroke_fill=(0, 0, 0))
    pd.text((210, 640), l['ed_caption'], font=font('uib', 28), fill=(255, 245, 160), anchor='mm', stroke_width=2, stroke_fill=(0, 0, 0))
    img.paste(pv, ((SW - 420) // 2, 180), rounded_mask((420, 746), 16))
    # panel
    y = 960
    d.rounded_rectangle([0, y, SW, SH], 32, fill=SURF2)
    d.rounded_rectangle([SW // 2 - 40, y + 14, SW // 2 + 40, y + 22], 4, fill=(90, 90, 96))
    d.text((40, y + 50), l['ed_clips'], font=font('uim', 24), fill=MUTED)
    d.text((SW - 40, y + 50), '0:12 / 0:30', font=font('uim', 24), fill=MUTED, anchor='ra')
    # clip strip with thumbs
    strip = [(255, 176, 70), (255, 140, 80), (240, 110, 110), (120, 190, 255), (90, 160, 240), (70, 130, 220)]
    x0, w_ = 40, (SW - 170) // 6
    for i, c in enumerate(strip):
        d.rounded_rectangle([x0 + i * w_, y + 90, x0 + (i + 1) * w_ - 4, y + 170], 8, fill=c)
    d.ellipse([x0 + 3 * w_ - 22, y + 108, x0 + 3 * w_ + 22, y + 152], fill=TURQ)
    icon(d, 'sparkle', (x0 + 3 * w_, y + 130), 26, WHITE)
    d.rectangle([x0 + int(w_ * 2.3), y + 84, x0 + int(w_ * 2.3) + 4, y + 176], fill=WHITE)
    d.rounded_rectangle([SW - 118, y + 90, SW - 40, y + 170], 10, fill=TURQ)
    icon(d, 'add', (SW - 79, y + 130), 40, WHITE)
    # slow-mo row
    d.text((40, y + 200), l['ed_slowmo'], font=font('uim', 24), fill=MUTED)
    d.rounded_rectangle([40, y + 240, SW - 130, y + 290], 8, fill=SURF)
    d.rounded_rectangle([40 + 190, y + 243, 40 + 360, y + 287], 8, fill=OCEAN_BAR, outline=TURQ, width=3)
    d.text((40 + 275, y + 265), '0.5x', font=font('uib', 24), fill=WHITE, anchor='mm')
    # overlays row: text, sticker, sound
    d.text((40, y + 320), l['ed_row'], font=font('uim', 24), fill=MUTED)
    d.rounded_rectangle([40, y + 360, SW - 130, y + 410], 8, fill=SURF)
    for x1, x2, c, t in ((50, 260, (230, 230, 120), 'POPCORN™'), (300, 420, (255, 179, 0), '🔥'), (450, 600, (140, 155, 255), 'Cha-ching')):
        d.rounded_rectangle([x1, y + 365, x2, y + 405], 8, fill=c + (170,))
        d.text((x1 + 12, y + 385), t if t != '🔥' else 'Fire', font=font('uim', 22), fill=WHITE, anchor='lm')
    # tools
    tools = [('text', 'Text'), ('emoji', 'Stickers'), ('eq', 'Sound FX'), ('slowmo', 'Slow-mo'), ('fx', 'Effects'), ('music', 'Music')]
    for i, (ic, t) in enumerate(tools):
        cx = 70 + i * 128
        active = ic in ('slowmo', 'eq')
        d.ellipse([cx - 44, y + 470, cx + 44, y + 558], fill=(TURQ[0], TURQ[1], TURQ[2], 60) if active else SURF)
        icon(d, ic, (cx, y + 514), 44, TURQ if active else WHITE)
        d.text((cx, y + 590), l['tool_' + ic], font=font('ui', 22), fill=MUTED, anchor='mm')
    return img


def sounds_screen(l):
    img = editor_screen(l)
    d = ImageDraw.Draw(img)
    y = 960
    d.rounded_rectangle([0, y, SW, SH], 32, fill=SURF2)
    d.rounded_rectangle([SW // 2 - 40, y + 14, SW // 2 + 40, y + 22], 4, fill=(90, 90, 96))
    d.text((40, y + 60), 'Sound FX', font=font('uib', 34), fill=WHITE, anchor='lm')
    d.text((SW - 40, y + 60), l['done'], font=font('uib', 30), fill=TURQ, anchor='rm')
    cats = [l['all'], 'Reactions', 'Comedy', 'Sale', 'Jingles']
    x = 40
    for i, c in enumerate(cats):
        w_ = int(d.textlength(c, font=font('uim', 26))) + 44
        d.rounded_rectangle([x, y + 110, x + w_, y + 160], 25, fill=(TURQ + (90,)) if i == 0 else SURF)
        d.text((x + w_ // 2, y + 135), c, font=font('uim', 26), fill=WHITE if i == 0 else MUTED, anchor='mm')
        x += w_ + 14
    cards = [('Applause', '6.0s'), ('Ba dum tss', '0.9s'), ('Cha-ching', '1.6s'), ('Air horn', '1.6s'),
             ('Sad trombone', '4.7s'), ('Scratch', '1.3s'), ('Drum roll', '6.0s'), ('Ta-da', '1.5s'),
             ('Laugh', '3.4s'), ('Boing', '0.9s'), ('Whoosh', '0.4s'), ('Wow', '1.4s')]
    cw, ch = (SW - 80 - 2 * 16) // 3, 96
    for i, (name, dur) in enumerate(cards):
        r, c = divmod(i, 3)
        cx, cy = 40 + c * (cw + 16), y + 190 + r * (ch + 16)
        sel = name == 'Ba dum tss'
        d.rounded_rectangle([cx, cy, cx + cw, cy + ch], 12, fill=(TURQ + (70,)) if sel else SURF, outline=TURQ if sel else None, width=3)
        icon(d, 'play', (cx + 26, cy + ch // 2), 26, MUTED)
        d.text((cx + 46, cy + 32), name, font=font('uim', 24), fill=WHITE)
        d.text((cx + 46, cy + 62), dur, font=font('ui', 20), fill=MUTED)
        icon(d, 'add', (cx + cw - 30, cy + ch // 2), 34, WHITE)
    return img


def market_screen(l):
    img = Image.new('RGBA', (SW, SH), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    status_bar(d)
    d.text((40, 130), l['market'], font=font('uib', 44), fill=WHITE)
    icon(d, 'search', (SW - 60, 160), 48, WHITE)
    # daily ad banner
    b = grad((SW - 80, 250), BRAND)
    img.paste(b, (40, 240), rounded_mask((SW - 80, 250), 28))
    d.text((80, 285), l['todays_ad'], font=font('uib', 26), fill=WHITE)
    d.text((80, 330), 'MONDAY', font=font('ad', 86), fill=WHITE)
    d.text((80 + d.textlength('MONDAY', font=font('ad', 86)) + 6, 345), '™', font=font('uib', 28), fill=WHITE)
    d.text((80, 440), l['participating'], font=font('uim', 26), fill=WHITE)
    d.rounded_rectangle([SW - 230, 400, SW - 70, 460], 30, fill=WHITE)
    d.text((SW - 150, 430), l['join'], font=font('uib', 28), fill=DEEP, anchor='mm')
    s = sticker('1f634', 150)
    img.paste(s, (SW - 220, 250), s)
    # fresh ads row
    d.text((40, 530), l['fresh'], font=font('uib', 32), fill=WHITE)
    tiles = [('1f525', [(255, 120, 60), (200, 40, 60)]), ('1f48e', [(80, 200, 255), (40, 90, 200)]),
             ('1f451', [(255, 210, 90), (230, 140, 40)]), ('1f680', [(90, 90, 220), (30, 20, 80)])]
    for i, (e, cols) in enumerate(tiles):
        t = grad((190, 330), cols, horizontal=False).convert('RGBA')
        st = sticker(e, 130)
        t.paste(st, (30, 90), st)
        img.paste(t, (40 + i * 205, 590), rounded_mask((190, 330), 14))
    # trending subjects
    d.text((40, 960), l['trending'], font=font('uib', 32), fill=WHITE)
    subs = [('ROCK™', '84.2K'), ('SOCK™', '51.9K'), ('COFFEE™', '38.4K'), ('ME™', '27.0K')]
    for i, (s_, n) in enumerate(subs):
        yy = 1030 + i * 110
        d.rounded_rectangle([40, yy, SW - 40, yy + 92], 16, fill=SURF)
        icon(d, 'fire', (86, yy + 46), 40, TURQ)
        d.text((130, yy + 46), s_, font=font('uib', 32), fill=WHITE, anchor='lm')
        d.text((SW - 70, yy + 46), l['ads_count'].format(n=n), font=font('ui', 26), fill=MUTED, anchor='rm')
    nav_bar(img, d, 1)
    return img


def subject_screen(l):
    img = Image.new('RGBA', (SW, SH), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    status_bar(d)
    d.text((SW // 2, 150), 'SOCK™', font=font('uib', 40), fill=WHITE, anchor='mm')
    d.text((40, 230), l['ads_count'].format(n='84.2K'), font=font('ui', 30), fill=MUTED)
    btn = grad((SW - 80, 96), BRAND)
    img.paste(btn, (40, 290), rounded_mask((SW - 80, 96), 48))
    d.text((SW // 2, 338), l['ad_this_subject'], font=font('uib', 32), fill=WHITE, anchor='mm')
    tabs = [l['tab_trending'], l['tab_top'], l['tab_new']]
    for i, t in enumerate(tabs):
        cx = int(SW * (i + 0.5) / 3)
        d.text((cx, 450), t, font=font('uim', 30), fill=WHITE if i == 0 else MUTED, anchor='mm')
    d.rectangle([int(SW / 6) - 60, 486, int(SW / 6) + 60, 491], fill=TURQ)
    tiles = ['1f602', '1f92f', '1f60e', '1f921', '1f440', '1f4af', '1f631', '1f911', '1f644']
    palettes = [[(255, 150, 90), (220, 70, 90)], [(90, 180, 255), (50, 80, 200)], [(120, 230, 170), (30, 140, 120)]]
    tw, th = (SW - 80 - 8) // 3, 400
    for i, e in enumerate(tiles):
        r, c = divmod(i, 3)
        t = grad((tw, th), palettes[(i + r) % 3], horizontal=False).convert('RGBA')
        st = sticker(e, 150)
        t.paste(st, ((tw - 150) // 2, 110), st)
        td = ImageDraw.Draw(t)
        icon(td, 'sell', (26, th - 30), 26, WHITE)
        td.text((46, th - 30), ['12.8K', '9.1K', '7.4K', '6.9K', '5.5K', '4.2K', '3.8K', '2.9K', '2.1K'][i], font=font('uib', 22), fill=WHITE, anchor='lm')
        img.paste(t, (40 + c * (tw + 4), 520 + r * (th + 4)), rounded_mask((tw, th), 6))
    return img


# ------------------------------------------------------------------ slides
LANG = {
    'en': dict(
        pick_title='What are you selling today?', pick_hint='Anything works: an object, a feeling, a day.', next='Next',
        cancel='Cancel', ed_caption='Now with extra crunch.', ed_clips='Clips', ed_slowmo='Slow motion · 0.5x',
        ed_row='Text, stickers & sounds', tool_text='Text', tool_emoji='Stickers', tool_eq='Sound FX',
        tool_slowmo='Slow-mo', tool_fx='Effects', tool_music='Music', done='Done', all='All', market='Market',
        todays_ad="TODAY'S AD", participating='2,418 participating', join='Join', fresh='Fresh Ads',
        trending='Trending Subjects', ads_count='{n} Ads', ad_this_subject='AD THIS SUBJECT', tab_trending='Trending',
        tab_top='Top', tab_new='New', nav=['Home', 'Market', 'Activity', 'Profile'],
        slides=[
            ('Everything is an ad.', 'The social network where everything is an ad.'),
            ('Pick anything. Sell it.', 'A rock, your coffee, yourself, Monday.'),
            ('Tap SOLD when an ad sells you.', 'Like a like — but for ads that actually convince you.'),
            ('See it. AD THIS. Do it better.', 'One tap to make your own version of any ad.'),
            ('A real video editor in your pocket', 'Trim, slow motion, text, stickers and effects.'),
            ('Ba-dum-tss. 39 sound effects.', 'Applause, cha-ching, air horn, drum roll and more.'),
            ('A new challenge every day', "Today's Ad: one subject, everyone's take."),
            ('Every subject has a stage', 'Browse every ad ever made for SOCK™.'),
        ],
        feature='The social network where everything is an ad.',
    ),
    'tr': dict(
        pick_title='Bugün ne satıyorsun?', pick_hint='Her şey olur: bir eşya, bir his, bir gün.', next='İleri',
        cancel='Vazgeç', ed_caption='Şimdi daha çıtır.', ed_clips='Klipler', ed_slowmo='Ağır çekim · 0.5x',
        ed_row='Yazı, çıkartma ve sesler', tool_text='Yazı', tool_emoji='Çıkartma', tool_eq='Sound FX',
        tool_slowmo='Ağır çekim', tool_fx='Efektler', tool_music='Müzik', done='Tamam', all='Tümü', market='Pazar',
        todays_ad='GÜNÜN REKLAMI', participating='2.418 katılımcı', join='Katıl', fresh='Yeni reklamlar',
        trending='Trend konular', ads_count='{n} reklam', ad_this_subject='BU KONUYA REKLAM YAP', tab_trending='Trend',
        tab_top='En iyi', tab_new='Yeni', nav=['Ana sayfa', 'Pazar', 'Aktivite', 'Profil'],
        slides=[
            ('Her şey bir reklam.', 'Her şeyin reklam olduğu sosyal ağ.'),
            ('Bir şey seç. Sat.', 'Bir taş, kahven, kendin, pazartesi.'),
            ('Reklam seni ikna ettiyse SOLD.', 'Beğeni gibi — ama seni gerçekten ikna eden reklamlar için.'),
            ('Gör. AD THIS. Daha iyisini yap.', 'Tek dokunuşla her reklamın kendi versiyonunu çek.'),
            ('Cebinde gerçek bir video editörü', 'Kırpma, ağır çekim, yazı, çıkartma ve efektler.'),
            ('Ba-dum-tss. 39 ses efekti.', 'Alkış, kasa sesi, korna, davul ve fazlası.'),
            ('Her gün yeni bir meydan okuma', 'Günün reklamı: tek konu, herkesin yorumu.'),
            ('Her konunun bir sahnesi var', 'SOCK™ için çekilmiş tüm reklamlara göz at.'),
        ],
        feature='Her şeyin reklam olduğu sosyal ağ.',
    ),
}


def screen_for(i, l):
    if i == 0:
        return feed_screen('ROCKET™', 'Faster than your Monday.', '@nora.ads', '1f680', [(70, 70, 210), (20, 16, 60)],
                           caption='My brother, the mechanic. 10/10.')
    if i == 1:
        return picker_screen(l)
    if i == 2:
        return feed_screen('MONDAY™', 'Nobody asked. We made it anyway.', '@sleepyhead', '1f634',
                           [(120, 190, 255), (30, 60, 140)], sold='24.1K', burst=True)
    if i == 3:
        return feed_screen('DIAMOND™', "Shinier than your ex's excuses.", '@gem_lord', '1f48e',
                           [(90, 220, 255), (20, 90, 160)], highlight_adthis=True)
    if i == 4:
        return editor_screen(l)
    if i == 5:
        return sounds_screen(l)
    if i == 6:
        return market_screen(l)
    return subject_screen(l)


def phone(screen):
    """Screen inside a phone body; the phone runs off the bottom edge."""
    body = Image.new('RGBA', (SW + 36, SH + 36), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle([0, 0, SW + 35, SH + 35], 86, fill=(24, 26, 28))
    bd.rounded_rectangle([3, 3, SW + 32, SH + 32], 83, outline=(60, 64, 68), width=2)
    body.paste(screen.convert('RGBA'), (18, 18), rounded_mask((SW, SH), 70))
    bd.ellipse([(SW + 36) // 2 - 16, 40, (SW + 36) // 2 + 16, 72], fill=(8, 8, 8))
    return body


def background():
    bg = Image.new('RGBA', (W, H), BG + (255,))
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-300, 900, 1380, 2500], fill=TURQ + (90,))
    gd.ellipse([500, -300, 1500, 600], fill=DEEP + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    return Image.alpha_composite(bg, glow)


def slide(i, l, real=None):
    img = background()
    d = ImageDraw.Draw(img)
    head, sub = l['slides'][i]
    hf = font('head', 76)
    lines = wrap(d, head, hf, W - 140)
    y = 120
    for ln in lines:
        d.text((W // 2, y), ln, font=hf, fill=WHITE, anchor='ma')
        y += 96
    sf = font('uim', 38)
    for ln in wrap(d, sub, sf, W - 180):
        d.text((W // 2, y + 18), ln, font=sf, fill=(170, 220, 216), anchor='ma')
        y += 52
    scr = real if real is not None else screen_for(i, l)
    ph = phone(scr)
    top = y + 70
    # the whole phone fits: nav bar and editor tools must be visible
    scale = min(1.0, (H - top - 50) / ph.height)
    ph = ph.resize((int(ph.width * scale), int(ph.height * scale)), Image.LANCZOS)
    # shadow
    sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([(W - ph.width) // 2 + 10, top + 30, (W + ph.width) // 2 - 10, top + ph.height + 20], 90, fill=(0, 0, 0, 160))
    sh = sh.filter(ImageFilter.GaussianBlur(40))
    img = Image.alpha_composite(img, sh)
    img.alpha_composite(ph, ((W - ph.width) // 2, top))
    return img.convert('RGB')


def feature_graphic(l):
    img = Image.new('RGBA', (1024, 500), BG + (255,))
    glow = Image.new('RGBA', (1024, 500), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-200, 100, 700, 800], fill=TURQ + (110,))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(140)))
    logo = Image.open(os.path.join(ROOT, 'assets', 'branding', 'AdGagLogo.png')).convert('RGBA')
    lh = 360
    logo = logo.resize((int(logo.width * lh / logo.height), lh), Image.LANCZOS)
    img.alpha_composite(logo, (60, (500 - lh) // 2))
    d = ImageDraw.Draw(img)
    f = font('head', 48)
    y = 150
    for ln in wrap(d, l['feature'], f, 480):
        d.text((500, y), ln, font=f, fill=WHITE)
        y += 64
    return img.convert('RGB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--screens', help='folder with real screenshots 01.png..08.png')
    ap.add_argument('--langs', default='en,tr')
    a = ap.parse_args()
    for lang in a.langs.split(','):
        l = LANG[lang]
        NAV[:] = l['nav']
        out = os.path.join(OUT, lang)
        os.makedirs(out, exist_ok=True)
        for i in range(8):
            real = None
            if a.screens:
                p = os.path.join(a.screens, f'{i + 1:02d}.png')
                if os.path.exists(p):
                    real = Image.open(p).convert('RGB').resize((SW, SH), Image.LANCZOS)
            slide(i, l, real).save(os.path.join(out, f'{i + 1:02d}.png'), optimize=True)
        feature_graphic(l).save(os.path.join(out, 'feature-graphic.png'), optimize=True)
        print(lang, 'done ->', out)


if __name__ == '__main__':
    main()
