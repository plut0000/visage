# Notices

Visage is an original Face ID-style unlocker for macOS. The product,
architecture, and source in this repository were written for this project.

## Inspiration

[Glance](https://github.com/jonnyoo/glance) by Jonathan Zhou (MIT License)
showed that a Mac webcam, on-device embeddings, and Accessibility keystroke
injection can deliver a Face ID-like unlock. Visage follows that product
shape — enroll, match locally, type the stored password at the lock screen —
with original Swift code.

## Recognition model

The bundled `ArcFace.mlpackage` is InsightFace `w600k_mbf` (MobileFaceNet
trained with ArcFace loss), converted to Core ML. The conversion pipeline
and packaged weights used here follow Glance's MIT-licensed tooling.

- InsightFace: https://github.com/deepinsight/insightface
- Glance conversion: `tools/convert_arcface.py` in jonnyoo/glance

Re-convert from official InsightFace weights with:

```
python3 -m venv .venv && source .venv/bin/activate
pip install insightface onnxruntime onnx2torch coremltools torch
python tools/convert_arcface.py
```

## Lock-screen overlay

macOS does not expose a public API for drawing over the lock screen.
`LockScreenSpace.swift` loads SkyLight symbols at runtime, following the
approach in [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)
(MIT). If those private symbols disappear, Visage still unlocks — the
animation simply will not appear on the lock screen.

## Licenses included

Glance, SkyLightWindow, and this project are MIT licensed. InsightFace
model weights remain subject to their upstream license.
