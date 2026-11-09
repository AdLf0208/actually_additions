# Licence and provenance notice — Actually Additions (Horizon port)

This port is **MIT**. `LICENSE` in this repository is the original MIT text plus
the port line; this file records where every licence and every asset came from
so a reviewer can follow it.

## Licence, as read from the mod's own files

| Source | Read |
|---|---|
| `actuallyadditions-1.3.26+mc1.21.1.jar` (`ports/_shared/licence-cache/`, SHA-1 `bd1826f117065dc3d73f0a7197091a4c37829a06`, 3,217,309 B) | `META-INF/neoforge.mods.toml`: `license="MIT"`, `authors="Ellpeck"` |
| The same jar | **no** `LICENSE`/`COPYING`/`NOTICE` file inside — the loader metadata is the declaration |
| Upstream repository `Ellpeck/ActuallyAdditions` at `cd9d9c63254f471f966ee51b078afdf47af5f852` | `LICENSE`: MIT, `Copyright (c) 2019 Mrbysco` |
| `ports/_shared/licence-audit.csv` | `actuallyadditions … MIT / MIT … rank 0, permissive` |

`LICENSE` here copies the upstream repository's MIT text verbatim (including its
`Copyright (c) 2019 Mrbysco`) and adds the port line. The jar's `authors` field
names **Ellpeck** as the original author; the jar credits BootyToast,
GlenthorLP, canitzp (textures and models), Flanks, MrBysco, ErrorMikey (porters)
and Ridanisaurus (1.20+ textures).

## Assets and data

Every carried asset in `content/` comes from that same jar, extracted by
`horizon-port-pack` at the campaign pin and then patched by
`content/patches/assemble.py` (the patch table is documented in
`content/README.md`). Nothing was drawn or invented by this port; the nine
textures, the block/item models, the blockstates, the lang file, the loot
tables, the recipes and the advancements are the mod's own files.

The Rust code (`mixins/actuallyadditions/*.rs`) is a **clean-room rewrite**. The
upstream Java was read for behaviour only (buffers, burn rates, timings, roll
chances, refusal rules) and is not copied or translated.

## Icon

`icon.png` is the jar's `assets/actuallyadditions/textures/logo.png` (377×212),
resized to fit 128×128 and centred on a transparent 128×128 canvas.

## Distribution

Local-only until the maintainer approved publication; this repository is that
publication, under MIT with these notices preserved.
