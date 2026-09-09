# Visage

Face unlock for Mac. Look at the camera when the lock screen appears; Visage recognizes you on-device and types your password.

Visage is built in the same spirit as [Glance](https://github.com/jonnyoo/glance): a menu-bar agent, nine-angle enrollment, ArcFace embeddings, liveness checks, and a notch-style scan animation. The Swift code in this repository is original. See `NOTICE.md` for model and lock-screen credits.

## This is not iPhone Face ID

MacBooks have a 2D webcam, not a TrueDepth camera.

- Heavy liveness can reject a printed photo and many phone screens.
- A video of you can still succeed.
- macOS has no public API for a third-party biometric login, so Visage unlocks by typing the password you stored.

Treat it as a convenience feature. It is off until you finish setup.

## Requirements

- macOS 14 Sonoma or later
- A Mac with a camera (built-in, USB, or Continuity Camera)
- Xcode 16 or later to build
- Camera, Accessibility, and Touch ID (or device password) permissions

## Build and run

```bash
git clone https://github.com/plut0000/visage.git
cd visage
chmod +x tools/fetch_arcface.sh && ./tools/fetch_arcface.sh
open Visage.xcodeproj
```

Select the **Visage** scheme, pick your Mac as the destination, and press Run.

If signing fails, set your Team under **Signing & Capabilities**, or leave **Sign to Run Locally** (`CODE_SIGN_IDENTITY = "-"`).

Launch Visage from `/Applications` after you copy it there. Testing lock-screen unlock from an Xcode-launched build is unreliable because TCC may attribute camera and Accessibility grants to Xcode.

## First-run setup

1. Allow **Camera**.
2. Allow **Accessibility** so Visage can type on the lock screen.
3. Authenticate with **Touch ID** (or your device password). That unlocks the AES key that encrypts embeddings and the stored login password.
4. Capture nine head poses. Each frame becomes a 512-d ArcFace embedding; the image is discarded.
5. Save the password you use to log in to this Mac.

After that, lock the Mac (Control-Command-Q) and look at the camera. A pill/notch animation scans; on a match Visage types the password and presses Return.

## Features

| | |
|---|---|
| Face unlock | Wake, lock, or Space on the lock screen |
| Multiple identities | Extra enrollments for glasses, lighting, or other people |
| Liveness | Off, Light (reject glare), Heavy (also require a blink or head turn) |
| Notch / island UI | Face ID-style rings, success check, failure shake |
| Encrypted vault | AES-GCM under a Touch ID–gated Keychain key |
| Camera picker | Built-in vs external display |
| Launch at login | `SMAppService` |

## How unlock works

1. The session key is already unwrapped in memory (Touch ID at setup or from the menu bar).
2. The screen is actually locked (`CGSSessionScreenIsLocked`).
3. An enabled identity matches above the cosine threshold (default 0.38).
4. Liveness accepts the face.
5. Accessibility is granted, so the password can be typed.

Face images never go to disk or the network. Embeddings live in `~/Library/Application Support/Visage/face-identities.enc`.

## Rebuilding the ArcFace model

A converted InsightFace `w600k_mbf` Core ML package lives in `Visage/Models/ArcFace.mlpackage`. After a fresh clone:

```bash
chmod +x tools/fetch_arcface.sh && ./tools/fetch_arcface.sh
```

To convert again from official InsightFace weights:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r tools/requirements.txt
python tools/convert_arcface.py
```

## Privacy and security

- No accounts, no analytics, no cloud.
- The login password is encrypted and zeroed after each unlock attempt.
- The Touch ID session re-locks after the idle interval you choose.
- Private SkyLight symbols are used only so the scan animation can appear on the lock screen. If Apple removes them, unlock still works; the overlay may not show while locked.

## License

MIT. Third-party notices in `NOTICE.md`.
