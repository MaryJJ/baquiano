"""Generate Baquiano/arrow.tga: a white 64x64 arrow pointing up.

The game tints and rotates it, so only the shape with transparency is needed.
Usage: python3 tools/make_arrow.py
"""
import os
import struct

SIZE = 64
SAMPLES = 4  # edge smoothing: 4x4 samples per pixel

# Arrow vertices (x, y), with y pointing down.
POLY = [(32, 4), (57, 34), (41, 34), (41, 60), (23, 60), (23, 34), (7, 34)]


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


def alpha(x, y):
    hits = 0
    for sy in range(SAMPLES):
        for sx in range(SAMPLES):
            if inside(x + (sx + 0.5) / SAMPLES, y + (sy + 0.5) / SAMPLES):
                hits += 1
    return round(255 * hits / (SAMPLES * SAMPLES))


def main():
    out = os.path.join(os.path.dirname(__file__), "..", "Baquiano", "arrow.tga")
    # Uncompressed 32-bit TGA; rows go bottom to top.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    rows = bytearray()
    for y in range(SIZE - 1, -1, -1):
        for x in range(SIZE):
            rows += bytes((255, 255, 255, alpha(x, y)))  # B, G, R, A
    with open(out, "wb") as f:
        f.write(header + rows)
    print("wrote", os.path.normpath(out), len(header) + len(rows), "bytes")


if __name__ == "__main__":
    main()
