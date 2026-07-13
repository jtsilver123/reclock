#!/usr/bin/env python3
"""Generate every visual asset Reclock ships with, reproducibly.

Outputs:
  Reclock/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
  store/screenshots/01–06 …png   (1320×2868 — App Store 6.9", scales to all sizes)
  web/invite/og.png              (1200×630 link preview)

Design language: marigold sun · warm cream · dusk navy ("the sky is the interface").
Everything is drawn 3× supersampled and downscaled for clean edges.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Palette (matches Theme.swift)
MARIGOLD = (252, 184, 18)
MARIGOLD_DEEP = (216, 148, 8)
INK = (51, 42, 16)
CREAM = (245, 242, 236)
NAVY = (24, 30, 66)
NAVY_DEEP = (14, 18, 44)
DUSK = (42, 53, 102)
TEXT = (31, 34, 41)
GRAY = (107, 109, 117)
SLEEP = (64, 79, 168)
AMBER = (240, 148, 26)
EMBER = (214, 92, 44)
ESPRESSO = (125, 90, 60)
SKYBLUE = (46, 116, 210)
GREEN = (52, 168, 83)
WHITE = (255, 255, 255)

DEJAVU = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
DEJAVU_BOOK = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def font(size, bold=True):
    return ImageFont.truetype(DEJAVU if bold else DEJAVU_BOOK, size)


def rr(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def vertical_gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px_color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = px_color
    return img


def diagonal_gradient(size, c1, c2):
    w, h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / max(1, w - 1) + y / max(1, h - 1)) / 2
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img


def centered_text(draw, xy, text, fnt, fill, anchor="mm"):
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor)


# ---------------------------------------------------------------- icon

def make_icon(path, size=1024):
    S = 3
    W = size * S
    img = vertical_gradient((W, W), DUSK, NAVY_DEEP)
    draw = ImageDraw.Draw(img)

    # A few crisp stars, upper sky only.
    import random
    rng = random.Random(7)
    for _ in range(26):
        x = rng.randint(int(W * 0.06), int(W * 0.94))
        y = rng.randint(int(W * 0.06), int(W * 0.40))
        r = rng.choice([S, S, 2 * S])
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(235, 238, 252))

    horizon = int(W * 0.72)
    sun_r = int(W * 0.30)
    cx = W // 2

    # Warm glow behind the sun.
    glow = Image.new("RGB", (W, W), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - int(sun_r * 1.9), horizon - int(sun_r * 1.9),
                cx + int(sun_r * 1.9), horizon + int(sun_r * 1.9)],
               fill=(70, 48, 6))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=W * 0.06))
    img = Image.blend(img, Image.blend(img, glow, 0.0), 0.0)  # keep img
    img = Image.composite(
        Image.blend(img, Image.new("RGB", (W, W), MARIGOLD), 0.10),
        img,
        glow.convert("L").point(lambda v: min(255, v * 3)),
    )
    draw = ImageDraw.Draw(img)

    # Rays: 9 capsules fanned over the top half, rising feel.
    ray_len = int(W * 0.085)
    ray_w = int(W * 0.028)
    for deg in range(180, 361, 24):
        a = math.radians(deg)
        r0 = sun_r + int(W * 0.045)
        r1 = r0 + ray_len
        x0, y0 = cx + r0 * math.cos(a), horizon + r0 * math.sin(a)
        x1, y1 = cx + r1 * math.cos(a), horizon + r1 * math.sin(a)
        if min(y0, y1) < W * 0.10:
            continue
        draw.line([x0, y0, x1, y1], fill=MARIGOLD, width=ray_w)
        for (px_, py_) in [(x0, y0), (x1, y1)]:
            draw.ellipse([px_ - ray_w / 2, py_ - ray_w / 2, px_ + ray_w / 2, py_ + ray_w / 2], fill=MARIGOLD)

    # Sun disc, clipped by the horizon band drawn after.
    draw.ellipse([cx - sun_r, horizon - sun_r, cx + sun_r, horizon + sun_r], fill=MARIGOLD)
    # Clock hands inside the sun: pointing 10:10-ish, thick, ink-on-marigold.
    hand_w = int(W * 0.030)
    hub = int(W * 0.020)
    hcx, hcy = cx, horizon - int(sun_r * 0.32)
    # hour hand (to 10)
    a1 = math.radians(215)
    draw.line([hcx, hcy, hcx + int(sun_r * 0.42) * math.cos(a1), hcy + int(sun_r * 0.42) * math.sin(a1)],
              fill=INK, width=hand_w)
    # minute hand (to 2)
    a2 = math.radians(305)
    draw.line([hcx, hcy, hcx + int(sun_r * 0.62) * math.cos(a2), hcy + int(sun_r * 0.62) * math.sin(a2)],
              fill=INK, width=hand_w)
    for (ex, ey, er) in [
        (hcx + int(sun_r * 0.42) * math.cos(a1), hcy + int(sun_r * 0.42) * math.sin(a1), hand_w / 2),
        (hcx + int(sun_r * 0.62) * math.cos(a2), hcy + int(sun_r * 0.62) * math.sin(a2), hand_w / 2),
        (hcx, hcy, hub),
    ]:
        draw.ellipse([ex - er, ey - er, ex + er, ey + er], fill=INK)

    # Cream ground band with a soft top edge (very slight arc).
    band = Image.new("L", (W, W), 0)
    bd = ImageDraw.Draw(band)
    bd.pieslice([-int(W * 0.6), horizon, W + int(W * 0.6), horizon + int(W * 2.2)], 180, 360, fill=255)
    cream_layer = Image.new("RGB", (W, W), CREAM)
    img = Image.composite(cream_layer, img, band)
    draw = ImageDraw.Draw(img)

    # Dawn blush: warmth rising from the horizon into the night sky.
    blush = Image.new("L", (W, W), 0)
    bd2 = ImageDraw.Draw(blush)
    fade = int(W * 0.26)
    for i in range(fade):
        alpha = int(64 * (1 - i / fade))
        bd2.line([0, horizon - i, W, horizon - i], fill=alpha)
    blush = blush.filter(ImageFilter.GaussianBlur(radius=W * 0.012))
    warm = Image.blend(img, Image.new("RGB", (W, W), (255, 168, 64)), 0.5)
    img = Image.composite(warm, img, blush)

    img = img.resize((size, size), Image.LANCZOS)

    # Film grain, applied at final resolution — printed, not rendered.
    from PIL import ImageChops
    rng_grain = random.Random(11)
    amp = 13
    noise = Image.new("L", (size, size))
    noise.putdata([128 + rng_grain.randint(-amp, amp) for _ in range(size * size)])
    img = ImageChops.soft_light(img, Image.merge("RGB", (noise, noise, noise)))

    img.save(path, "PNG")
    print("icon ->", path)




def gradient_rounded(img, rect, c1, c2, radius):
    """Vertical gradient clipped to a rounded rect, pasted onto img."""
    x0, y0, x1, y1 = [int(v) for v in rect]
    w, h = x1 - x0, y1 - y0
    grad = vertical_gradient((w, h), c1, c2)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    img.paste(grad, (x0, y0), mask)

# ------------------------------------------------------- phone mockups

def phone(canvas, draw, box, screen_painter):
    """Dark-bezel phone with a cream screen; screen_painter(draw, rect) fills it."""
    x0, y0, x1, y1 = box
    rr(draw, box, radius=int((x1 - x0) * 0.16), fill=(24, 25, 31))
    inset = int((x1 - x0) * 0.035)
    sx0, sy0, sx1, sy1 = x0 + inset, y0 + inset, x1 - inset, y1 - inset
    rr(draw, [sx0, sy0, sx1, sy1], radius=int((x1 - x0) * 0.13), fill=CREAM)
    # dynamic island
    iw = int((x1 - x0) * 0.30)
    ih = int((y1 - y0) * 0.022)
    icx = (x0 + x1) // 2
    rr(draw, [icx - iw // 2, sy0 + ih, icx + iw // 2, sy0 + 2 * ih], ih // 2 + 1, fill=(24, 25, 31))
    screen_painter(canvas, draw, (sx0, sy0 + 3 * ih, sx1, sy1))


def sun_glyph(draw, cx, cy, r, color=WHITE, rays=8, ray_frac=0.55):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    for i in range(rays):
        a = math.radians(i * (360 / rays))
        r0, r1 = r * 1.35, r * (1.35 + ray_frac)
        draw.line([cx + r0 * math.cos(a), cy + r0 * math.sin(a),
                   cx + r1 * math.cos(a), cy + r1 * math.sin(a)],
                  fill=color, width=max(2, int(r * 0.22)))


def moon_glyph(draw, cx, cy, r, color=WHITE):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    draw.ellipse([cx - r + int(r * 0.62), cy - r - int(r * 0.25), cx + r + int(r * 0.62), cy + r - int(r * 0.25)],
                 fill=None)


def check_row(draw, x, y, n_done, n_total, r, gap):
    for i in range(n_total):
        cx = x + i * (2 * r + gap) + r
        if i < n_done:
            draw.ellipse([cx - r, y - r, cx + r, y + r], fill=GREEN)
            w = max(2, int(r * 0.28))
            draw.line([cx - r * 0.45, y, cx - r * 0.1, y + r * 0.38], fill=WHITE, width=w)
            draw.line([cx - r * 0.1, y + r * 0.38, cx + r * 0.5, y - r * 0.35], fill=WHITE, width=w)
        else:
            draw.ellipse([cx - r, y - r, cx + r, y + r], outline=(185, 186, 192), width=max(2, int(r * 0.2)))


# ------------------------------------------------- screenshot panels

def panel(path, bg, headline, sub, painter, headline_color=TEXT, sub_color=GRAY):
    S = 2
    W, H = 1320 * S, 2868 * S
    if isinstance(bg, tuple):
        img = Image.new("RGB", (W, H), bg)
    else:
        img = bg((W, H))
    draw = ImageDraw.Draw(img)

    h_font = font(int(150 * S / 2))
    s_font = font(int(62 * S / 2), bold=False)
    y = int(H * 0.075)
    for line in headline.split("\n"):
        centered_text(draw, (W // 2, y), line, h_font, headline_color)
        y += int(170 * S / 2)
    y += int(20 * S / 2)
    for line in sub.split("\n"):
        centered_text(draw, (W // 2, y), line, s_font, sub_color)
        y += int(84 * S / 2)

    ph_w = int(W * 0.66)
    ph_h = int(ph_w * 2.05)
    px0 = (W - ph_w) // 2
    py0 = int(H * 0.235)
    phone(img, ImageDraw.Draw(img), box=(px0, py0, px0 + ph_w, py0 + ph_h), screen_painter=painter)

    img = img.resize((1320, 2868), Image.LANCZOS)
    img.save(path, "PNG")
    print("screenshot ->", path)


def card(draw, rect, fill, radius_frac=0.09):
    x0, y0, x1, y1 = rect
    rr(draw, rect, radius=int((x1 - x0) * radius_frac), fill=fill)


def paint_home(img, draw, rect):
    x0, y0, x1, y1 = rect
    w = x1 - x0
    pad = int(w * 0.05)
    # sunrise hero card
    hero = (x0 + pad, y0 + pad * 2, x1 - pad, y0 + int((y1 - y0) * 0.46))
    hx0, hy0, hx1, hy1 = hero
    gradient_rounded(img, hero, AMBER, EMBER, int(w * 0.06))
    draw = ImageDraw.Draw(img)
    sun_glyph(draw, hx0 + int(w * 0.16), hy0 + int(w * 0.19), int(w * 0.065), WHITE)
    centered_text(draw, ((hx0 + hx1) // 2 + int(w * 0.10), hy0 + int(w * 0.17)), "2h 10m",
                  font(int(w * 0.105)), WHITE)
    draw.text((hx0 + int(w * 0.07), hy0 + int(w * 0.36)), "Chase the daylight",
              font=font(int(w * 0.075)), fill=WHITE)
    draw.text((hx0 + int(w * 0.07), hy0 + int(w * 0.47)), "Real daylight beats indoor light 10-to-1.",
              font=font(int(w * 0.037), bold=False), fill=(255, 245, 228))
    rr(draw, [hx0 + int(w * 0.07), hy1 - int(w * 0.17), hx1 - int(w * 0.40), hy1 - int(w * 0.05)],
       int(w * 0.06), fill=WHITE)
    centered_text(draw, ((hx0 + int(w * 0.07) + hx1 - int(w * 0.40)) // 2, hy1 - int(w * 0.11)),
                  "Done", font(int(w * 0.05)), (30, 30, 30))
    # day ribbon
    ry = hy1 + int(w * 0.10)
    rr(draw, [x0 + pad, ry, x1 - pad, ry + int(w * 0.035)], int(w * 0.0175), fill=(228, 226, 220))
    rr(draw, [x0 + pad + int(w * 0.05), ry, x0 + pad + int(w * 0.32), ry + int(w * 0.035)], int(w * 0.0175), fill=SLEEP)
    rr(draw, [x0 + pad + int(w * 0.42), ry, x0 + pad + int(w * 0.62), ry + int(w * 0.035)], int(w * 0.0175), fill=AMBER)
    rr(draw, [x0 + pad + int(w * 0.68), ry, x0 + pad + int(w * 0.71), ry + int(w * 0.035)], int(w * 0.0175), fill=ESPRESSO)
    dot = int(w * 0.014)
    draw.ellipse([x0 + pad + int(w * 0.5) - dot, ry + int(w * 0.0175) - dot,
                  x0 + pad + int(w * 0.5) + dot, ry + int(w * 0.0175) + dot], fill=(35, 36, 42))
    # tonight rows
    ty = ry + int(w * 0.12)
    for label, value, color in [("Last call for caffeine", "14:30", ESPRESSO), ("Tonight's sleep", "22:00 – 06:30", SLEEP)]:
        card(draw, (x0 + pad, ty, x1 - pad, ty + int(w * 0.17)), WHITE, 0.05)
        draw.ellipse([x0 + pad * 2, ty + int(w * 0.045), x0 + pad * 2 + int(w * 0.08), ty + int(w * 0.045) + int(w * 0.08)], fill=tuple(min(255, c + 90) for c in color))
        draw.text((x0 + pad * 2 + int(w * 0.12), ty + int(w * 0.035)), label, font=font(int(w * 0.042)), fill=TEXT)
        draw.text((x0 + pad * 2 + int(w * 0.12), ty + int(w * 0.095)), value, font=font(int(w * 0.055)), fill=color)
        ty += int(w * 0.21)
    # boarding-pass trip card fills the tail of the screen
    card(draw, (x0 + pad, ty, x1 - pad, ty + int(w * 0.24)), WHITE, 0.05)
    draw.text((x0 + pad * 2, ty + int(w * 0.04)), "JFK", font=font(int(w * 0.075)), fill=TEXT)
    draw.text((x1 - pad * 2 - int(w * 0.15), ty + int(w * 0.04)), "HEL", font=font(int(w * 0.075)), fill=TEXT)
    ly = ty + int(w * 0.17)
    draw.line([x0 + pad * 2, ly, x1 - pad * 2, ly], fill=(226, 224, 218), width=max(3, int(w * 0.01)))
    draw.line([x0 + pad * 2, ly, x0 + pad * 2 + int(w * 0.42), ly], fill=MARIGOLD, width=max(3, int(w * 0.01)))
    pr = int(w * 0.024)
    draw.ellipse([x0 + pad * 2 + int(w * 0.42) - pr, ly - pr, x0 + pad * 2 + int(w * 0.42) + pr, ly + pr], fill=MARIGOLD)


def paint_tracks(img, draw, rect):
    x0, y0, x1, y1 = rect
    w = x1 - x0
    pad = int(w * 0.06)
    rail_x = x0 + pad + int(w * 0.09)
    top = y0 + pad * 2
    bottom = y1 - pad
    hours = ["7am", "9am", "11am", "1pm", "3pm", "5pm", "7pm", "9pm", "11pm"]
    n = len(hours)
    for i, hh in enumerate(hours):
        yy = top + i * (bottom - top) // (n - 1)
        draw.text((x0 + pad, yy - int(w * 0.02)), hh, font=font(int(w * 0.032), bold=False), fill=GRAY)
        draw.line([rail_x, yy, x1 - pad, yy], fill=(226, 224, 218), width=2)
    lane_w = (x1 - pad - rail_x) // 3
    def lane_box(lane, t0, t1):
        lx = rail_x + lane * lane_w + int(lane_w * 0.12)
        return [lx, top + int((bottom - top) * t0), lx + int(lane_w * 0.76), top + int((bottom - top) * t1)]
    # light pill (amber, filled, sun)
    b = lane_box(0, 0.05, 0.38)
    rr(draw, b, radius=(b[2] - b[0]) // 2, fill=AMBER)
    sun_glyph(draw, (b[0] + b[2]) // 2, b[1] + int(lane_w * 0.30), int(lane_w * 0.11), WHITE, rays=8, ray_frac=0.4)
    centered_text(draw, ((b[0] + b[2]) // 2, (b[1] + b[3]) // 2 + int(lane_w * 0.2)), "3 h", font(int(w * 0.038)), WHITE)
    # sleep pill (navy, filled, moon dot)
    b = lane_box(1, 0.62, 0.98)
    rr(draw, b, radius=(b[2] - b[0]) // 2, fill=SLEEP)
    draw.ellipse([(b[0] + b[2]) // 2 - int(lane_w * 0.11), b[1] + int(lane_w * 0.16),
                  (b[0] + b[2]) // 2 + int(lane_w * 0.11), b[1] + int(lane_w * 0.38)], fill=WHITE)
    centered_text(draw, ((b[0] + b[2]) // 2, (b[1] + b[3]) // 2 + int(lane_w * 0.2)), "8.5 h", font(int(w * 0.038)), WHITE)
    # no-coffee pill (outlined espresso with slash)
    b = lane_box(2, 0.30, 0.62)
    rr(draw, b, radius=(b[2] - b[0]) // 2, outline=ESPRESSO, width=max(3, int(w * 0.008)))
    ccx, ccy = (b[0] + b[2]) // 2, b[1] + int(lane_w * 0.28)
    draw.ellipse([ccx - int(lane_w * 0.12), ccy - int(lane_w * 0.12), ccx + int(lane_w * 0.12), ccy + int(lane_w * 0.12)],
                 outline=ESPRESSO, width=max(3, int(w * 0.008)))
    draw.line([ccx - int(lane_w * 0.16), ccy + int(lane_w * 0.16), ccx + int(lane_w * 0.16), ccy - int(lane_w * 0.16)],
              fill=ESPRESSO, width=max(3, int(w * 0.01)))
    # now line
    ny = top + int((bottom - top) * 0.47)
    draw.line([rail_x, ny, x1 - pad, ny], fill=(35, 36, 42), width=max(3, int(w * 0.008)))
    draw.ellipse([rail_x - 7, ny - 7, rail_x + 7, ny + 7], fill=(35, 36, 42))


def paint_chooser(img, draw, rect):
    x0, y0, x1, y1 = rect
    w = x1 - x0
    pad = int(w * 0.05)
    draw.text((x0 + pad, y0 + pad), "Where's your flight?", font=font(int(w * 0.065)), fill=TEXT)
    hero = (x0 + pad, y0 + int(w * 0.2), x1 - pad, y0 + int(w * 0.52))
    hx0, hy0, hx1, hy1 = hero
    gradient_rounded(img, hero, SKYBLUE, NAVY, int(w * 0.06))
    draw = ImageDraw.Draw(img)
    draw.ellipse([hx0 + pad, (hy0 + hy1) // 2 - int(w * 0.07), hx0 + pad + int(w * 0.14), (hy0 + hy1) // 2 + int(w * 0.07)], fill=(255, 255, 255, 60))
    draw.text((hx0 + pad + int(w * 0.18), hy0 + int(w * 0.07)), "From your calendar", font=font(int(w * 0.055)), fill=WHITE)
    draw.text((hx0 + pad + int(w * 0.18), hy0 + int(w * 0.16)), "We spot the flights already\non your phone. No typing.",
              font=font(int(w * 0.035), bold=False), fill=(226, 236, 252))
    yy = hy1 + int(w * 0.06)
    for icon_color, title, subtitle in [
        (AMBER, "By flight number", "AA 8987 — we fill in the rest."),
        (SLEEP, "Type it in", "Two airports, two times."),
        ((90, 150, 120), "Join a friend's trip", "Got an invite code?"),
    ]:
        card(draw, (x0 + pad, yy, x1 - pad, yy + int(w * 0.19)), WHITE, 0.05)
        draw.ellipse([x0 + pad * 2, yy + int(w * 0.045), x0 + pad * 2 + int(w * 0.10), yy + int(w * 0.145)],
                     fill=tuple(min(255, c + 100) for c in icon_color))
        draw.text((x0 + pad * 2 + int(w * 0.14), yy + int(w * 0.035)), title, font=font(int(w * 0.048)), fill=TEXT)
        draw.text((x0 + pad * 2 + int(w * 0.14), yy + int(w * 0.105)), subtitle, font=font(int(w * 0.034), bold=False), fill=GRAY)
        yy += int(w * 0.23)


def paint_delay(img, draw, rect):
    x0, y0, x1, y1 = rect
    w = x1 - x0
    pad = int(w * 0.05)
    draw.text((x0 + pad, y0 + pad), "Flight changed", font=font(int(w * 0.06)), fill=TEXT)
    card(draw, (x0 + pad, y0 + int(w * 0.18), x1 - pad, y0 + int(w * 0.44)), WHITE, 0.05)
    draw.text((x0 + pad * 2, y0 + int(w * 0.22)), "JFK → HEL · AY 16", font=font(int(w * 0.055)), fill=TEXT)
    draw.text((x0 + pad * 2, y0 + int(w * 0.31)), "New departure  18:55 → 20:55", font=font(int(w * 0.04), bold=False), fill=GRAY)
    yy = y0 + int(w * 0.52)
    draw.text((x0 + pad, yy - int(w * 0.02)), "Common delays", font=font(int(w * 0.04)), fill=GRAY)
    xx = x0 + pad
    for chip, active in [("+1h", False), ("+2h", True), ("+4h", False)]:
        cw = int(w * 0.24)
        rr(draw, [xx, yy + int(w * 0.05), xx + cw, yy + int(w * 0.17)], int(w * 0.03),
           fill=MARIGOLD if active else (235, 233, 227))
        centered_text(draw, (xx + cw // 2, yy + int(w * 0.11)), chip, font(int(w * 0.05)),
                      INK if active else TEXT)
        xx += cw + int(w * 0.05)
    rr(draw, [x0 + pad, yy + int(w * 0.24), x1 - pad, yy + int(w * 0.38)], int(w * 0.05), fill=MARIGOLD)
    centered_text(draw, ((x0 + x1) // 2, yy + int(w * 0.31)), "Update plan", font(int(w * 0.055)), INK)
    draw.text((x0 + pad, yy + int(w * 0.46)), "Every reminder reshuffles itself.", font=font(int(w * 0.038), bold=False), fill=GRAY)


def paint_buddies(img, draw, rect):
    x0, y0, x1, y1 = rect
    w = x1 - x0
    pad = int(w * 0.05)
    draw.text((x0 + pad, y0 + pad), "Travel buddies", font=font(int(w * 0.06)), fill=TEXT)
    card(draw, (x0 + pad, y0 + int(w * 0.17), x1 - pad, y0 + int(w * 0.31)), WHITE, 0.05)
    draw.text((x0 + pad * 2, y0 + int(w * 0.21)), "Invite with code", font=font(int(w * 0.045)), fill=TEXT)
    rr(draw, [x1 - pad - int(w * 0.34), y0 + int(w * 0.195), x1 - pad * 2, y0 + int(w * 0.275)], int(w * 0.02), fill=(240, 235, 220))
    centered_text(draw, (x1 - pad - int(w * 0.34) // 2 - pad, y0 + int(w * 0.235)), "Q7MPX2", font(int(w * 0.042)), (60, 70, 130))
    yy = y0 + int(w * 0.38)
    for name, done, total, kudos in [("jake (you)", 4, 6, False), ("ana", 5, 6, True), ("sam", 2, 6, False)]:
        card(draw, (x0 + pad, yy, x1 - pad, yy + int(w * 0.26)), WHITE, 0.05)
        draw.ellipse([x0 + pad * 2, yy + int(w * 0.04), x0 + pad * 2 + int(w * 0.09), yy + int(w * 0.13)], fill=MARIGOLD)
        centered_text(draw, (x0 + pad * 2 + int(w * 0.045), yy + int(w * 0.085)), name[0].upper(), font(int(w * 0.045)), INK)
        draw.text((x0 + pad * 2 + int(w * 0.13), yy + int(w * 0.045)), name, font=font(int(w * 0.045)), fill=TEXT)
        draw.text((x1 - pad * 2 - int(w * 0.22), yy + int(w * 0.05)), f"{done}/{total} today", font=font(int(w * 0.036)), fill=GRAY)
        check_row(draw, x0 + pad * 2, yy + int(w * 0.19), done, total, int(w * 0.025), int(w * 0.025))
        if kudos:
            rr(draw, [x1 - pad * 2 - int(w * 0.18), yy + int(w * 0.15), x1 - pad * 2, yy + int(w * 0.23)], int(w * 0.02), fill=(255, 240, 200))
            centered_text(draw, (x1 - pad * 2 - int(w * 0.09), yy + int(w * 0.19)), "Kudos!", font(int(w * 0.032)), (150, 100, 10))
        yy += int(w * 0.30)


def paint_privacy(img, draw, rect):
    x0, y0, x1, y1 = rect
    w = x1 - x0
    pad = int(w * 0.05)
    # big lock in a marigold circle
    ccx, ccy, r = (x0 + x1) // 2, y0 + int(w * 0.30), int(w * 0.17)
    draw.ellipse([ccx - r, ccy - r, ccx + r, ccy + r], fill=MARIGOLD)
    bw = int(r * 0.72)
    bh = int(r * 0.58)
    rr(draw, [ccx - bw // 2, ccy - int(bh * 0.1), ccx + bw // 2, ccy + bh], int(r * 0.14), fill=INK)
    draw.arc([ccx - int(bw * 0.32), ccy - int(bh * 0.75), ccx + int(bw * 0.32), ccy + int(bh * 0.25)],
             180, 360, fill=INK, width=int(r * 0.14))
    yy = ccy + r + int(w * 0.12)
    for title, sub in [
        ("No account required", "Everything works on-device."),
        ("Works offline", "Plans and reminders fly airplane mode."),
        ("You approve every import", "Calendar scanning stays on your phone."),
    ]:
        card(draw, (x0 + pad, yy, x1 - pad, yy + int(w * 0.2)), WHITE, 0.05)
        draw.ellipse([x0 + pad * 2, yy + int(w * 0.065), x0 + pad * 2 + int(w * 0.07), yy + int(w * 0.135)], fill=(220, 240, 225))
        draw.line([x0 + pad * 2 + int(w * 0.017), yy + int(w * 0.1), x0 + pad * 2 + int(w * 0.032), yy + int(w * 0.118)], fill=GREEN, width=max(3, int(w * 0.009)))
        draw.line([x0 + pad * 2 + int(w * 0.032), yy + int(w * 0.118), x0 + pad * 2 + int(w * 0.055), yy + int(w * 0.078)], fill=GREEN, width=max(3, int(w * 0.009)))
        draw.text((x0 + pad * 2 + int(w * 0.11), yy + int(w * 0.045)), title, font=font(int(w * 0.048)), fill=TEXT)
        draw.text((x0 + pad * 2 + int(w * 0.11), yy + int(w * 0.115)), sub, font=font(int(w * 0.035), bold=False), fill=GRAY)
        yy += int(w * 0.24)


def make_og(path):
    S = 2
    W, H = 1200 * S, 630 * S
    img = vertical_gradient((W, H), DUSK, NAVY_DEEP)
    draw = ImageDraw.Draw(img)
    horizon = int(H * 0.86)
    sun_r = int(H * 0.30)
    cx = int(W * 0.24)
    sun_glyph(draw, cx, horizon, sun_r, MARIGOLD, rays=9, ray_frac=0.35)
    band = Image.new("L", (W, H), 0)
    bd = ImageDraw.Draw(band)
    bd.rectangle([0, horizon, W, H], fill=255)
    img = Image.composite(Image.new("RGB", (W, H), CREAM), img, band)
    draw = ImageDraw.Draw(img)
    draw.text((int(W * 0.45), int(H * 0.28)), "Reclock", font=font(int(H * 0.17)), fill=WHITE)
    draw.text((int(W * 0.45), int(H * 0.5)), "Feel local when you land.", font=font(int(H * 0.065), bold=False), fill=(226, 230, 248))
    img = img.resize((1200, 630), Image.LANCZOS)
    img.save(path, "PNG")
    print("og ->", path)


def main():
    icon_path = os.path.join(ROOT, "Reclock/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
    make_icon(icon_path)

    shots = os.path.join(ROOT, "store/screenshots")
    os.makedirs(shots, exist_ok=True)

    panel(os.path.join(shots, "01-feel-local.png"), CREAM,
          "Feel local\nwhen you land", "Your flights become a plan for\nsleep, light, and caffeine.",
          paint_home)
    panel(os.path.join(shots, "02-day-in-color.png"), MARIGOLD,
          "Your day,\ndrawn in color", "Filled means do. Outlined means avoid.\nA line shows now.",
          paint_tracks, headline_color=INK, sub_color=(120, 90, 10))
    panel(os.path.join(shots, "03-add-in-seconds.png"), NAVY,
          "Add a flight\nin seconds", "Calendar, flight number,\nor two airports typed by hand.",
          paint_chooser, headline_color=WHITE, sub_color=(196, 204, 236))
    panel(os.path.join(shots, "04-adjusts.png"), (222, 106, 50),
          "Flight delayed?\nPlan adapts", "One tap rebuilds every reminder\naround the new times.",
          paint_delay, headline_color=WHITE, sub_color=(255, 226, 208))
    panel(os.path.join(shots, "05-buddies.png"), DUSK,
          "Beat jet lag\ntogether", "Share your plan with an invite code.\nCheckmarks and kudos included.",
          paint_buddies, headline_color=WHITE, sub_color=(200, 208, 240))
    panel(os.path.join(shots, "06-private.png"), CREAM,
          "Private\nby default", "No account required. Sign in only\nif you want backup & buddies.",
          paint_privacy)

    make_og(os.path.join(ROOT, "web/invite/og.png"))


if __name__ == "__main__":
    main()
