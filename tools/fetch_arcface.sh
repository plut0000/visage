#!/usr/bin/env bash
# Downloads the MIT-licensed ArcFace Core ML package Visage needs at build time,
# and writes a 1024×1024 app icon if one is not already present.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Visage/Models/ArcFace.mlpackage"
BASE="https://raw.githubusercontent.com/jonnyoo/glance/main/glance/Models/ArcFace.mlpackage"
ICON="$ROOT/Visage/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

mkdir -p "$DEST/Data/com.apple.CoreML/weights"

curl -fsSL "$BASE/Manifest.json" -o "$DEST/Manifest.json"
curl -fsSL "$BASE/Data/com.apple.CoreML/model.mlmodel" -o "$DEST/Data/com.apple.CoreML/model.mlmodel"
curl -fsSL "$BASE/Data/com.apple.CoreML/weights/weight.bin" -o "$DEST/Data/com.apple.CoreML/weights/weight.bin"

echo "ArcFace model ready at $DEST"

if [[ ! -f "$ICON" ]]; then
  python3 - "$ICON" <<'PY'
import struct, sys, zlib
from pathlib import Path

def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

w = h = 1024
# Accent color used in Assets.xcassets (sRGB 0.42, 0.82, 1.00)
r, g, b = 107, 209, 255
row = b"\x00" + bytes([r, g, b]) * w
raw = row * h
png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(raw, 9))
    + chunk(b"IEND", b"")
)
path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(png)
print(f"Wrote placeholder app icon at {path}")
PY
fi
