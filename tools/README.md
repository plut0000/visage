# Tools

## convert_arcface.py

Converts InsightFace `w600k_mbf` to the Core ML package Visage loads at runtime.

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r tools/requirements.txt
python tools/convert_arcface.py
```

Writes `Visage/Models/ArcFace.mlpackage`. Adapted from Glance's MIT-licensed converter.

## fetch_arcface.sh

Downloads that Core ML package from Glance's public MIT repo into `Visage/Models/`. Run it after cloning if the model binaries are not in the tree. If `AppIcon-1024.png` is missing, it also writes a solid-color placeholder icon so the asset catalog still compiles.
