#!/usr/bin/env python3
"""Copy this repository's licence and provenance notice into the carried content.

The package's `data/` is what a player installs, and the licence requires its
notice to travel with copies of the work, so the notice rides as data the game
ignores: `data/actuallyadditions/license/license.txt` and
`data/actuallyadditions/license/notice.txt`, written from the repository's
`LICENSE` and `LICENSE-NOTICE.md` (the same two files the SDK package ships at
its root, which `cargo horizon-mod build` also packs).
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "actuallyadditions" / "license"

OUT.mkdir(parents=True, exist_ok=True)
for source, name in (("LICENSE", "license.txt"), ("LICENSE-NOTICE.md", "notice.txt")):
    text = (ROOT / source).read_text()
    (OUT / name).write_text(text)
    print(f"wrote {OUT / name}")
