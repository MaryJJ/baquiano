"""Generates Baquiano/StarterData.lua: the paths recorded in your game, to
ship with the addon. Whoever installs it gets them added on their first login
(as an import, so /baq import undo takes them out), and again the new ones
each time a release brings more.

    python tools/make_starter.py [path to SavedVariables/Baquiano.lua]

It carries the paths of every zone and the crossings between zones, in the
same text as /baq export (see Baquiano/Share.lua); not flights, trail,
distance walked or settings. Close the game first (or /reload), so that the
saved file is up to date.
"""
import glob
import math
import os
import re
import sys
import time

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "Baquiano", "StarterData.lua")
SAVED = r"D:\BNetGames\World of Warcraft\_forever_\WTF\Account\*\SavedVariables\Baquiano.lua"

# --- Reading the saved file (a Lua table) ---------------------------------

TOKEN = re.compile(r'''\s*(?:--[^\n]*\n?\s*)*(?:
    (?P<str>"(?:\\.|[^"\\])*")
  | (?P<num>-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)
  | (?P<name>[A-Za-z_]\w*)
  | (?P<sym>[{}\[\]=,;])
)''', re.X)


def tokens(text):
    pos = 0
    while True:
        m = TOKEN.match(text, pos)
        if not m or m.end() == pos:
            rest = text[pos:].strip()
            if rest and not rest.startswith("--"):
                raise ValueError("cannot read at: " + rest[:40])
            return
        pos = m.end()
        for kind in ("str", "num", "name", "sym"):
            if m.group(kind) is not None:
                yield kind, m.group(kind)
                break


class Parser:
    def __init__(self, text):
        self.toks = list(tokens(text))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self, value=None):
        tok = self.toks[self.i]
        if value is not None and tok[1] != value:
            raise ValueError("expected %s, got %s" % (value, tok[1]))
        self.i += 1
        return tok

    def value(self):
        kind, v = self.take()
        if kind == "str":
            return bytes(v[1:-1], "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")
        if kind == "num":
            return float(v) if any(c in v for c in ".eE") else int(v)
        if kind == "name":
            return {"true": True, "false": False, "nil": None}[v]
        if v == "{":
            return self.table()
        raise ValueError("unexpected " + v)

    def table(self):
        out, n = {}, 0
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                out[key] = self.value()
            elif self.peek()[0] == "name" and self.toks[self.i + 1][1] == "=":
                key = self.take()[1]
                self.take("=")
                out[key] = self.value()
            else:
                n += 1
                out[n] = self.value()
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return out


def load(path):
    text = open(path, encoding="utf-8").read()
    m = re.search(r"BaquianoDB\s*=\s*", text)
    p = Parser(text[m.end():])
    return p.value()


def array(t):
    return [t[i] for i in range(1, len(t) + 1)] if t else []

# --- Writing, exactly as Share.lua does -------------------------------------

ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
COORD = 262143


def number(out, n):
    n = math.floor(n)
    while n >= 32:
        out.append(ALPHABET[32 + n % 32])
        n //= 32
    out.append(ALPHABET[n])


def signed(out, n):
    number(out, n * 2 if n >= 0 else -n * 2 - 1)


def coord(out, v):
    q = max(0, min(COORD, math.floor((v + 0.5) / 2 * COORD + 0.5)))
    out += [ALPHABET[q // 4096], ALPHABET[(q // 64) % 64], ALPHABET[q % 64]]


def checksum(s):
    total = 0
    for i, c in enumerate(s, 1):
        total = (total + ord(c) * (i % 7 + 1)) % 4096
    return ALPHABET[total // 64] + ALPHABET[total % 64]


def export(db):
    parts, zones, points = ["BAQ1"], 0, 0
    for m in sorted(db.get("maps", {})):
        saved = db["maps"][m]
        nodes, edges = array(saved.get("nodes")), array(saved.get("edges"))
        if not nodes:
            continue
        zones, points = zones + 1, points + len(nodes) // 2
        out = ["M"]
        number(out, m)
        for v in nodes:
            coord(out, v)
        out.append(",")
        prev = 0
        for e in range(0, len(edges) - 1, 2):
            a, b = edges[e], edges[e + 1]
            signed(out, a - prev)
            signed(out, b - a)
            prev = a
        out.append(",")
        prev = 0
        for i in sorted(k for k, v in (saved.get("inside") or {}).items() if v):
            number(out, i - prev)
            prev = i
        parts.append("".join(out))
    out = ["P"]
    for p in array(db.get("portals")):
        p = array(p)
        number(out, p[0]); coord(out, p[1]); coord(out, p[2])
        number(out, p[3]); coord(out, p[4]); coord(out, p[5])
    if len(out) > 1:
        parts.append("".join(out))
    body = ";".join(parts)
    return body + ";=" + checksum(body), zones, points


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        found = glob.glob(SAVED)
        if len(found) != 1:
            sys.exit("give the path to SavedVariables/Baquiano.lua (found %d)" % len(found))
        path = found[0]
    text, zones, points = export(load(path))
    if "]]" in text:
        sys.exit("unexpected ']]' in the text")
    version = time.strftime("%Y%m%d") + "-" + text[-2:]
    with open(OUT, "w", encoding="utf-8", newline="\r\n") as f:
        f.write("-- Generated by tools/make_starter.py: paths that come with the addon,\n")
        f.write("-- added on the first login (see Share.lua). Do not edit.\n")
        f.write("local ADDON, ns = ...\n")
        f.write('ns.StarterData = { version = "%s", text = [[%s]] }\n' % (version, text))
    print("%d zones, %d points, %d letters -> %s (version %s)"
          % (zones, points, len(text), os.path.relpath(OUT, ROOT), version))


if __name__ == "__main__":
    main()
