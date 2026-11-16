"""Generate Baquiano's small textures (32x32, uncompressed 32-bit TGA):

  dot.tga           white disc, tinted by the game (edit-mode points)
  chevron_gold.tga  route arrow: gold chevron with a dark outline, pointing up
  chevron_white.tga the same in white, for flights
  chevron_faint.tga orange, half see-through: a stretch with no recorded path
  dest.tga          destination: gold disc with a dark rim
  trail.tga         breadcrumb of the trail walked this session: green disc

The chevrons and the destination carry their own colour, so they look the
same on every map without tinting. Usage: python3 tools/make_textures.py
"""
import math
import os
import struct

SIZE = 32
SAMPLES = 4  # edge smoothing: 4x4 samples per pixel
OUT = os.path.join(os.path.dirname(__file__), "..", "Baquiano")

GOLD = (255, 209, 0)
ORANGE = (255, 140, 30)  # stretches with no recorded path
TRAIL = (90, 235, 110)  # breadcrumbs of what was walked this session
WHITE = (255, 255, 255)
DARK = (20, 14, 0)
OUTLINE = 1.8  # pixels of dark outline around the chevrons

# Chevron pointing up, y down.
CHEVRON = [(16, 5), (28, 17), (28, 25), (16, 13), (4, 25), (4, 17)]


def inside(poly, px, py):
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def edge_dist(poly, px, py):
    best = float("inf")
    for i in range(len(poly)):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % len(poly)]
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(px - ax - dx * t, py - ay - dy * t))
    return best


def chevron(fill, opacity=1.0):
    def sample(x, y):
        if inside(CHEVRON, x, y):
            return fill + (round(255 * opacity),)
        if edge_dist(CHEVRON, x, y) <= OUTLINE:
            return DARK + (round(230 * opacity),)
        return None
    return sample


def disc(fill, radius, rim):
    def sample(x, y):
        d = math.hypot(x - SIZE / 2, y - SIZE / 2)
        if d <= radius - rim:
            return fill + (255,)
        if d <= radius:
            return DARK + (230,)
        return None
    return sample


def write(name, sample):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    rows = bytearray()
    for y in range(SIZE - 1, -1, -1):  # rows go bottom to top
        for x in range(SIZE):
            r = g = b = a = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    s = sample(x + (sx + 0.5) / SAMPLES, y + (sy + 0.5) / SAMPLES)
                    if s:
                        # Colour weighted by alpha, so edges do not darken.
                        r, g, b, a = r + s[0] * s[3], g + s[1] * s[3], b + s[2] * s[3], a + s[3]
            n = SAMPLES * SAMPLES
            if a:
                rows += bytes((round(b / a), round(g / a), round(r / a), round(a / n)))
            else:
                rows += bytes((0, 0, 0, 0))
    path = os.path.join(OUT, name)
    with open(path, "wb") as f:
        f.write(header + rows)
    print("wrote", os.path.normpath(path))


def main():
    write("dot.tga", disc(WHITE, SIZE / 2 - 1, 0))
    write("chevron_gold.tga", chevron(GOLD))
    write("chevron_white.tga", chevron(WHITE))
    write("chevron_faint.tga", chevron(ORANGE, 0.55))
    write("dest.tga", disc(GOLD, SIZE / 2 - 2, 4))
    write("trail.tga", disc(TRAIL, SIZE / 2 - 2, 5))


if __name__ == "__main__":
    main()
