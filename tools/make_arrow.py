"""Generate Baquiano/arrow.tga: the 64x64 guide arrow, pointing up.

A dart with a dark outline and a soft bevel (the left half lighter than the
right), in greys: the game tints it (green, yellow, red) and the outline
stays dark, so it reads on any background. The game also rotates it.
Usage: python3 tools/make_arrow.py
"""
import math
import os
import struct

SIZE = 64
SAMPLES = 4  # edge smoothing: 4x4 samples per pixel
OUTLINE = 2.6  # pixels of dark outline

# Dart pointing up, y down: tip, right wing, notch, left wing.
POLY = [(32, 5), (56, 55), (32, 43), (8, 55)]


def inside(px, py):
    hit = False
    j = len(POLY) - 1
    for i in range(len(POLY)):
        xi, yi = POLY[i]
        xj, yj = POLY[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def edge_dist(px, py):
    best = float("inf")
    for i in range(len(POLY)):
        ax, ay = POLY[i]
        bx, by = POLY[(i + 1) % len(POLY)]
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(px - ax - dx * t, py - ay - dy * t))
    return best


def sample(x, y):
    if inside(x, y):
        # Bevel: light on the left half, a bit darker on the right, and a
        # touch lighter towards the tip.
        shade = 255 if x < 32 else 205
        shade = min(255, shade + int(max(0, 30 - y) * 0.6))
        return (shade, shade, shade, 255)
    if edge_dist(x, y) <= OUTLINE:
        return (15, 15, 15, 235)
    return None


def main():
    out = os.path.join(os.path.dirname(__file__), "..", "Baquiano", "arrow.tga")
    # Uncompressed 32-bit TGA; rows go bottom to top.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    rows = bytearray()
    for y in range(SIZE - 1, -1, -1):
        for x in range(SIZE):
            r = g = b = a = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    s = sample(x + (sx + 0.5) / SAMPLES, y + (sy + 0.5) / SAMPLES)
                    if s:
                        r, g, b, a = r + s[0] * s[3], g + s[1] * s[3], b + s[2] * s[3], a + s[3]
            n = SAMPLES * SAMPLES
            if a:
                rows += bytes((round(b / a), round(g / a), round(r / a), round(a / n)))  # B, G, R, A
            else:
                rows += bytes((0, 0, 0, 0))
    with open(out, "wb") as f:
        f.write(header + rows)
    print("wrote", os.path.normpath(out), len(header) + len(rows), "bytes")


if __name__ == "__main__":
    main()
