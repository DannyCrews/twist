#!/usr/bin/env python3
"""Assert the rendered snapshots actually show something.

`ImageRenderer` returns a blank image for a `ScrollView` rather than failing, so a UI change
can silently reduce a screen to an empty rectangle and the PNG will still be written, still be
the right size, and still look plausible in a file listing. That has happened here. This is the
cheapest guard: a screen that renders to one flat colour, or to almost no distinct colours, is
not a screen.

Usage: check-snapshots.py <directory>
"""
import struct
import sys
import zlib
from pathlib import Path

MIN_DISTINCT_COLOURS = 24
MIN_INK_FRACTION = 0.004  # share of pixels differing from the most common colour


def decode(path):
    data = path.read_bytes()
    pos, idat = 8, b""
    width = height = colour = 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        kind = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            width, height, _depth, colour = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + length

    raw = zlib.decompress(idat)
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    stride = width * channels
    rows, previous, offset = [], bytearray(stride), 0
    for _ in range(height):
        filt = raw[offset]
        line = bytearray(raw[offset + 1 : offset + 1 + stride])
        offset += 1 + stride
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = previous[x]
            c = previous[x - channels] if x >= channels else 0
            if filt == 1:
                line[x] = (line[x] + a) & 255
            elif filt == 2:
                line[x] = (line[x] + b) & 255
            elif filt == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if (pa <= pb and pa <= pc) else (b if pb <= pc else c))) & 255
        rows.append(bytes(line))
        previous = line
    return width, height, channels, rows


def inspect(path):
    width, height, channels, rows = decode(path)
    counts = {}
    # Every fourth pixel in both directions: enough to characterise the image, four times faster.
    for y in range(0, height, 4):
        row = rows[y]
        for x in range(0, width, 4):
            key = row[x * channels : x * channels + 3]
            counts[key] = counts.get(key, 0) + 1

    sampled = sum(counts.values())
    dominant = max(counts.values())
    ink = 1 - dominant / sampled
    return len(counts), ink


def main(directory):
    paths = sorted(Path(directory).glob("*.png"))
    if not paths:
        print(f"no snapshots in {directory} — run `make snapshots` first")
        return 1

    failures = []
    print(f"{'snapshot':22} {'colours':>8} {'ink':>8}")
    for path in paths:
        colours, ink = inspect(path)
        ok = colours >= MIN_DISTINCT_COLOURS and ink >= MIN_INK_FRACTION
        print(f"{path.stem:22} {colours:8d} {ink:7.2%} {'' if ok else '  BLANK'}")
        if not ok:
            failures.append(path.stem)

    if failures:
        print(f"\n{len(failures)} snapshot(s) rendered blank or near-blank: {', '.join(failures)}")
        return 1
    print(f"\nall {len(paths)} snapshots have content")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "build/snapshots"))
