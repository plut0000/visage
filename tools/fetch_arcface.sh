#!/usr/bin/env bash
# Downloads the MIT-licensed ArcFace Core ML package Visage needs at build time.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Visage/Models/ArcFace.mlpackage"
BASE="https://raw.githubusercontent.com/jonnyoo/glance/main/glance/Models/ArcFace.mlpackage"

mkdir -p "$DEST/Data/com.apple.CoreML/weights"

curl -fsSL "$BASE/Manifest.json" -o "$DEST/Manifest.json"
curl -fsSL "$BASE/Data/com.apple.CoreML/model.mlmodel" -o "$DEST/Data/com.apple.CoreML/model.mlmodel"
curl -fsSL "$BASE/Data/com.apple.CoreML/weights/weight.bin" -o "$DEST/Data/com.apple.CoreML/weights/weight.bin"

echo "ArcFace model ready at $DEST"
