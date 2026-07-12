"""Reclock app icon: a clock rising like the sun over a dusk horizon.
Rendered 4x supersampled, downscaled with Lanczos for clean edges."""
from PIL import Image, ImageDraw, ImageFilter
import math

S = 4096  # supersample canvas
OUT = 1024

img = Image.new("RGB", (S, S))
draw = ImageDraw.Draw(img)

# --- Background: night -> dusk -> warm horizon gradient
stops = [
    (0.00, (16, 20, 52)),
    (0.42, (44, 48, 106)),
    (0.62, (94, 74, 130)),
    (0.72, (214, 122, 70)),
    (0.80, (240, 168, 88)),
    (1.00, (247, 195, 110)),
]
def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

for y in range(S):
    t = y / (S - 1)
    for i in range(len(stops) - 1):
        t0, c0 = stops[i]
        t1, c1 = stops[i + 1]
        if t0 <= t <= t1:
            draw.line([(0, y), (S, y)], fill=lerp(c0, c1, (t - t0) / (t1 - t0)))
            break

# --- Stars (deterministic scatter, upper sky only)
rng_state = 42

def rng():
    global rng_state
    rng_state = (rng_state * 1103515245 + 12345) % (2**31)
    return rng_state / (2**31)

for _ in range(90):
    x, y = rng() * S, rng() * S * 0.42
    r = S * (0.0008 + rng() * 0.0016)
    alpha = 0.35 + rng() * 0.45
    star = Image.new("L", (int(r * 6) + 2, int(r * 6) + 2), 0)
    sd = ImageDraw.Draw(star)
    sd.ellipse([r * 2, r * 2, r * 4, r * 4], fill=int(255 * alpha))
    star = star.filter(ImageFilter.GaussianBlur(r * 0.7))
    img.paste((255, 249, 235), (int(x), int(y)), star)

HORIZON = 0.755 * S

# --- Sun glow behind the clock
glow = Image.new("L", (S, S), 0)
gd = ImageDraw.Draw(glow)
cx, cy, R = S * 0.5, S * 0.50, S * 0.315
gd.ellipse([cx - R * 1.55, cy - R * 1.55, cx + R * 1.55, cy + R * 1.55], fill=110)
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.06))
img.paste((255, 214, 150), (0, 0), glow)

# --- Clock ring (ivory), hour ticks, hands
IVORY = (255, 247, 232)
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(ring)
stroke = S * 0.030
rd.ellipse(
    [cx - R, cy - R, cx + R, cy + R],
    outline=IVORY + (255,),
    width=int(stroke),
)
# Hour ticks
for h in range(12):
    ang = math.radians(h * 30 - 90)
    r_out = R - stroke * 1.7
    r_in = R - stroke * (3.4 if h % 3 == 0 else 2.7)
    x1, y1 = cx + r_out * math.cos(ang), cy + r_out * math.sin(ang)
    x2, y2 = cx + r_in * math.cos(ang), cy + r_in * math.sin(ang)
    rd.line([x1, y1, x2, y2], fill=IVORY + (235,), width=int(stroke * (0.75 if h % 3 == 0 else 0.5)))

def hand(angle_deg, length, width):
    ang = math.radians(angle_deg - 90)
    x2, y2 = cx + length * math.cos(ang), cy + length * math.sin(ang)
    rd.line([cx, cy, x2, y2], fill=IVORY + (255,), width=int(width))
    rd.ellipse([x2 - width / 2, y2 - width / 2, x2 + width / 2, y2 + width / 2], fill=IVORY + (255,))

# 10:09 — classic, upward, optimistic
hand(305, R * 0.52, stroke * 1.05)   # hour
hand(54, R * 0.74, stroke * 0.8)     # minute
rd.ellipse([cx - stroke * 0.9, cy - stroke * 0.9, cx + stroke * 0.9, cy + stroke * 0.9], fill=IVORY + (255,))

# Fade the ring where it sinks below the horizon
fade = Image.new("L", (S, S), 255)
fd = ImageDraw.Draw(fade)
band = S * 0.10
for y in range(int(HORIZON - band), S):
    t = min(1.0, max(0.0, (y - (HORIZON - band)) / (band * 1.6)))
    fd.line([(0, y), (S, y)], fill=int(255 * (1 - t) ** 1.6))
ring.putalpha(Image.composite(ring.split()[3], Image.new("L", (S, S), 0), fade.point(lambda v: v)))
# Apply per-pixel: multiply ring alpha by fade
r_, g_, b_, a_ = ring.split()
from PIL import ImageChops
a_ = ImageChops.multiply(a_, fade)
ring = Image.merge("RGBA", (r_, g_, b_, a_))
img.paste(ring, (0, 0), ring)

# --- Horizon glow line
hl = Image.new("L", (S, S), 0)
hd = ImageDraw.Draw(hl)
hd.line([(0, HORIZON), (S, HORIZON)], fill=200, width=int(S * 0.006))
hl = hl.filter(ImageFilter.GaussianBlur(S * 0.008))
img.paste((255, 231, 178), (0, 0), hl)

img = img.resize((OUT, OUT), Image.LANCZOS)
img.save("/home/user/reclock/Reclock/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png", optimize=True)
print("icon written", img.size)
