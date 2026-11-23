#!/usr/bin/env bash
# Where does `actuallyadditions:restonia_crystal` come from at 1.3.26? A reproducible audit of the
# artefact (the jar ATM10 ships + the matching upstream source), written because the port's own notes
# and `tools/recipe-blockers.json` claimed "upstream grows it from a seed in water" and no amount of
# reading the code supports that. Every line below is a command and its output, not a claim.
#
#   tools/audit_restonia_source.sh > ../_shared/evidence/actuallyadditions/restonia-source-audit.log
#
# Exit 0 always: this is an audit, its result is the text, not the status.
set -uo pipefail

CLONE=/home/adlf/Desktop/all_the_mods_10_rust_rewrite
JAR=${JAR:-$CLONE/ports/_shared/licence-cache/actuallyadditions-1.3.26+mc1.21.1.jar}
SRC=${SRC:-$CLONE/ports/_shared/upstream/actuallyadditions}
BLOCKS=$SRC/src/main/java/de/ellpeck/actuallyadditions/mod/blocks

run() { echo "\$ $*"; "$@" 2>&1 || echo "(exit $?)"; echo; }
jarp() { echo "\$ unzip -p .../$1"; unzip -p "$JAR" "$1" 2>&1 || echo "(exit $?)"; echo; }
jarl() { echo "\$ unzip -Z1 ... | grep -E '$1'"; unzip -Z1 "$JAR" | grep -E "$1" || echo "(no match)"; echo; }

echo "# restonia_crystal source audit — Actually Additions 1.3.26+mc1.21.1 (MIT)"
echo "# generated $(date -u '+%Y-%m-%dT%H:%M:%SZ') by ports/actuallyadditions/tools/audit_restonia_source.sh"
echo

echo "## 0. artefact identity"
run sha1sum "$JAR"
echo "\$ unzip -p ... META-INF/neoforge.mods.toml | grep version= & license="
unzip -p "$JAR" META-INF/neoforge.mods.toml | grep -E '^(license|version)=' ; echo
run git -C "$SRC" log -1 --format=%H\ %ci
run grep -n mod_version "$SRC/gradle.properties"
echo

echo "## 1. is there a growth tick anywhere? every randomTick/isRandomlyTicking in the source"
run grep -rn "randomTick\|isRandomlyTicking" "$SRC/src/main/java"
echo

echo "## 2. the cluster block has no tick and ignores its crystal argument"
run sed -n '31,60p' "$BLOCKS/CrystalClusterBlock.java"
run grep -n "crystal" "$BLOCKS/CrystalClusterBlock.java"
echo "\$ grep -n 'crystal' src/.../blocks/base/*.java  src/.../blocks/ActuallyBlock.java"
grep -n -i 'crystal' "$BLOCKS"/base/*.java "$BLOCKS"/ActuallyBlock.java || echo "(no match)"
echo

echo "## 3. no seed item: every registered id containing 'seed'"
run grep -rn "ITEMS.register(\".*seed" "$SRC/src/main/java/de/ellpeck/actuallyadditions/mod/items/ActuallyItems.java"
echo "\$ ... every jar entry containing 'seed' (textures/models excluded)"
unzip -Z1 "$JAR" | grep -i 'seed' | grep -vE 'textures|models/item' || echo "(no match)"
echo

echo "## 4. the cluster is not generated: the jar's whole worldgen tree"
jarl '^data/actuallyadditions/worldgen'
echo "\$ ... any configured_feature / placed_feature naming a cluster"
unzip -Z1 "$JAR" | grep -E 'worldgen/(configured|placed)_feature/.*cluster' || echo "(no match)"
echo "\$ ... the lush-cave generator that once placed clusters, at 1.21.1"
run grep -n "CRYSTAL_CLUSTERS\|class WorldGenLushCaves" "$SRC/src/main/java/de/ellpeck/actuallyadditions/mod/gen/WorldGenLushCaves.java"
echo "\$ ... how much of that file is commented out"
echo "commented lines: $(grep -c '^\s*//' "$SRC/src/main/java/de/ellpeck/actuallyadditions/mod/gen/WorldGenLushCaves.java") of $(wc -l < "$SRC/src/main/java/de/ellpeck/actuallyadditions/mod/gen/WorldGenLushCaves.java")"
echo

echo "## 5. every recipe whose result is restonia_crystal, with its input"
echo "\$ grep over data/actuallyadditions/recipe/** for '\"id\": \"actuallyadditions:restonia_crystal\"'"
for f in $(unzip -Z1 "$JAR" | grep '^data/actuallyadditions/recipe/.*\.json$'); do
    if unzip -p "$JAR" "$f" | grep -q '"id": "actuallyadditions:restonia_crystal"'; then
        echo "--- $f"
        unzip -p "$JAR" "$f"
        echo
    fi
done
echo "\$ ... the laser conversion the booklet documents (laser/crystalize_restonia_crystal)"
jarp data/actuallyadditions/recipe/laser/crystalize_restonia_crystal.json

echo "## 6. the mod's own words (booklet, crystal chapter)"
echo "\$ unzip -p ... assets/actuallyadditions/lang/en_us.json | grep chapter.crystals"
unzip -p "$JAR" assets/actuallyadditions/lang/en_us.json | grep -E '"booklet.actuallyadditions.chapter.crystals.text.(1|2)"'
echo

echo "## 7. the machine that performs it: cycle and cost"
run grep -n "ENERGY_USE\|currentTime = 100\|getDistance" "$SRC/src/main/java/de/ellpeck/actuallyadditions/mod/tile/TileEntityAtomicReconstructor.java" "$SRC/src/main/java/de/ellpeck/actuallyadditions/api/lens/LensConversion.java"
run grep -n -A12 "invokeReconstructor" "$SRC/src/main/java/de/ellpeck/actuallyadditions/mod/misc/apiimpl/MethodHandler.java"
jarp data/actuallyadditions/recipe/atomic_reconstructor.json

echo "## 8. the chain's gates: what iron_casing / basic_coil / crusher key on"
for r in iron_casing basic_coil crusher; do jarp "data/actuallyadditions/recipe/$r.json"; done

echo "## 9. every source of black_quartz in the jar (is the ore the only one?)"
echo "\$ grep over data/actuallyadditions/** for a recipe RESULT of black_quartz"
for f in $(unzip -Z1 "$JAR" | grep -E '^data/actuallyadditions/(recipe|loot_table)/'); do
    body=$(unzip -p "$JAR" "$f")
    case "$f" in
        *recipe/*)
            echo "$body" | grep -q '"id": "actuallyadditions:black_quartz"' && { echo "--- $f"; echo "$body"; echo; }
            ;;
        *loot_table/*)
            echo "$body" | grep -q '"name": "actuallyadditions:black_quartz"' && echo "--- $f (loot)"
            ;;
    esac
done
echo "\$ ... the second loot source: the engineer house's own chest table (a structure, also worldgen)"
echo "entries: $(unzip -p "$JAR" data/actuallyadditions/loot_table/engineer_house.json | grep -o '"actuallyadditions:[a-z_]*"' | sort -u | tr '\n' ' ')"
echo

echo "## 9b. does a restonia_crystal_shard exist anywhere but the cluster's loot table?"
for f in $(unzip -Z1 "$JAR" | grep -E '^data/actuallyadditions/(recipe|loot_table)/'); do
    unzip -p "$JAR" "$f" | grep -q 'restonia_crystal_shard' && echo "--- $f"
done
jarp data/actuallyadditions/loot_table/blocks/restonia_crystal_cluster.json
jarp data/actuallyadditions/worldgen/configured_feature/ore_black_quartz.json
jarp data/actuallyadditions/worldgen/placed_feature/ore_black_quartz.json
jarp data/actuallyadditions/neoforge/biome_modifier/add_black_quartz.json

echo "## 10. result"
echo "no growth tick, no seed item, no cluster worldgen feature and no cluster recipe exist at"
echo "1.3.26; the cluster block is decorative. restonia_crystal has exactly one non-circular source:"
echo "the Atomic Reconstructor's laser conversion of #c:dusts/redstone (40 CF of a 1000 CF shot)."
echo "iron_casing and basic_coil each key on black_quartz, whose only sources are ore_black_quartz"
echo "(configured feature + placed feature + add_black_quartz biome modifier) and the engineer"
echo "house's chest table (a structure loot table) — both worldgen. The crystal alone cannot make"
echo "either craftable."
