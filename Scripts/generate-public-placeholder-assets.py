#!/usr/bin/env python3
"""Generate original GPL-3.0-only placeholder artwork using only Python's stdlib.

Copyright (C) 2026 materialofair
No production artwork, fonts, system symbols, or third-party images are used.
PNG files contain only IHDR, IDAT and IEND chunks (no ancillary metadata).
"""
from pathlib import Path
import struct
import zlib


ROOT = Path(__file__).resolve().parents[1] / "App/Assets.xcassets"
PALETTES = {
    "Primary": (28, 75, 64),
    "Paper": (109, 79, 44),
    "Pebble": (65, 75, 100),
    "Calculator": (57, 61, 66),
}


def chunk(kind, payload):
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))


def image(size, background, calculator=False):
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        v = y / size
        for x in range(size):
            u = x / size
            if calculator:
                foreground = 0.27 < u < 0.73 and 0.23 < v < 0.36
                for cx in (0.33, 0.50, 0.67):
                    for cy in (0.49, 0.66, 0.83):
                        foreground |= abs(u - cx) < 0.052 and abs(v - cy) < 0.052
            else:
                radius = ((u - 0.5) ** 2 + (v - 0.40) ** 2) ** 0.5
                foreground = ((0.17 < radius < 0.235 and v < 0.49)
                              or (0.265 < u < 0.735 and 0.43 < v < 0.78))
                if (u - 0.5) ** 2 + (v - 0.575) ** 2 < 0.035 ** 2:
                    foreground = False
                if abs(u - 0.5) < 0.017 and 0.575 < v < 0.65:
                    foreground = False
            rows.extend((240, 242, 236) if foreground else background)
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def main():
    for name, color in PALETTES.items():
        suffix = "" if name == "Primary" else "-" + name
        icon = ROOT / f"AppIcon{suffix}.appiconset" / f"AppIcon{suffix}-1024.png"
        icon.write_bytes(image(1024, color, name == "Calculator"))
        preview = ROOT / f"IconPreview-{name}.imageset" / f"IconPreview-{name}.png"
        preview.write_bytes(image(256, color, name == "Calculator"))
    (ROOT / "LaunchMark.imageset/LaunchMark.png").write_bytes(image(256, PALETTES["Primary"]))


if __name__ == "__main__":
    main()
