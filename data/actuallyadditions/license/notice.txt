# Licence provenance and notices

## The upstream notice, verbatim

`LICENSE` in this package is the original mod's licence text,
<https://github.com/Ellpeck/ActuallyAdditions/blob/v1.3.26/LICENSE>, copied **byte for byte**:
1,063 bytes, sha256
`82ea451b20be461c2bbf279262d4a28c34bed3edc3197b90ae902b77fb22c560`. It keeps the copyright
line the upstream file carries — `Copyright (c) 2019 Mrbysco` — rather than a rewritten one, as
MIT requires the notice to be reproduced unchanged. This provenance section is separate on
purpose: nothing of ours is mixed into that text.

## Provenance

- Mod: `actuallyadditions` — Actually Additions, <https://github.com/Ellpeck/ActuallyAdditions>.
- Original author(s): Ellpeck, and the project's contributors (the licence file names Mrbysco).
- Original jar this port was written against: `actuallyadditions-1.3.26+mc1.21.1.jar` (Modrinth
  SHA-1 `bd1826f117065dc3d73f0a7197091a4c37829a06`), whose `META-INF/neoforge.mods.toml` declares
  `license="MIT"`.
- The `src/` half is a clean-room Rust rewrite written from the mod's observed behaviour and its
  own data files, not a translation of its Java; the carried `assets/` and `data/` come from the
  MIT-licensed jar.

## This port's own notice

The port's own Rust code and package metadata are Copyright (c) 2026 the Horizon port authors and
are distributed under the same MIT terms, with the upstream notice above kept intact.

## Where the notices travel

They are packed in the archive itself, not only kept in the source repository: `LICENSE` and
`LICENSE-NOTICE.md` at the package root, and copies under
`data/actuallyadditions/license/{license.txt,notice.txt}`, written by `tools/stamp_license.py`
before packaging.
