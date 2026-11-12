"""Builds the zip to share Baquiano: dist/Baquiano-<version>.zip, with the
Baquiano folder at its root (unzipped into Interface/AddOns it lands in
place). The version is read from Baquiano/Baquiano.toc.

    python tools/package.py

Only the files the game loads go in: .lua, .toc, .xml and .tga.
"""
import os
import re
import sys
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ADDON = os.path.join(ROOT, "Baquiano")
DIST = os.path.join(ROOT, "dist")
KEEP = (".lua", ".toc", ".xml", ".tga")


def version():
    with open(os.path.join(ADDON, "Baquiano.toc"), encoding="utf-8") as f:
        m = re.search(r"^## Version:\s*(\S+)", f.read(), re.M)
    if not m:
        sys.exit("no '## Version:' line in Baquiano.toc")
    return m.group(1)


def check_toc():
    """Every file the .toc lists must exist (a missing one breaks the addon)."""
    with open(os.path.join(ADDON, "Baquiano.toc"), encoding="utf-8") as f:
        files = [l.strip() for l in f if l.strip() and not l.startswith("#")]
    missing = [name for name in files if not os.path.isfile(os.path.join(ADDON, name))]
    if missing:
        sys.exit("listed in Baquiano.toc but missing: " + ", ".join(missing))


def main():
    check_toc()
    ver = version()
    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, "Baquiano-%s.zip" % ver)
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in sorted(os.listdir(ADDON)):
            path = os.path.join(ADDON, name)
            if os.path.isfile(path) and name.lower().endswith(KEEP):
                z.write(path, "Baquiano/" + name)
                count += 1
    print("%s: %d files, %d KB" % (os.path.relpath(out, ROOT), count, os.path.getsize(out) // 1024))


if __name__ == "__main__":
    main()
