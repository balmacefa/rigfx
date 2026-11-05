# rigfx — one animation, any body

Retarget one library of 2D pixel-art animations onto characters of any proportions, with no re-animating and no GPU.
Live demo: https://rigfx.balmacefa.com (also https://balmacefa.github.io/rigfx/)

A character is a JSON file of proportion multipliers (`legS`, `torsoS`, `armS`, `headS`, `neckS`, `widthS`, `thick`) plus a palette.
The rig solves every pose from where the hands and feet should go. The retargeting layer re-aims those targets to the new limb lengths, so
the same 12 moves (sword combo, fireball, ground pound, rocket launcher...) fit 17 different bodies: a giant, a chibi, a golem, a lanky mage, a long-armed brute...
Style comes from procedural gear listed in the same JSON: `headGear` (helmet, visor, horns, wizardhat, hood, ears, mohawk, tusks, antenna, bighair, crown) and `bodyGear` (pauldrons, cape, belt, backpack, tail).

## Run it
```bash
git clone https://github.com/patch-gg/pixelfx pixelfx        # MIT: the effects + rig this builds on
git -C pixelfx checkout a841596
git -C pixelfx apply ../patches/rig-retarget.patch            # adds setBody(), setActorPalette() and the gear
# (or point PIXELFX_DIR at an existing patched clone)

# 1. a new character: one command, no hand-written palette
node tools/new-character.mjs --list-gear
node tools/new-character.mjs viking --legS 1.1 --armS 1.15 --thick 1.3 --head helmet,horns --gear cape,pauldrons --color "#c89632"

# 2. render the matrix in parallel (default jobs = cpus-1)
node retarget.mjs                                   # all moves x all characters -> anim/retarget/<char>/<move>/NNN.png + manifest.json
node retarget.mjs sword-combo --chars viking,giant  # filter by move / character
node retarget.mjs --transparent --out frames        # RGBA frames for compositing (videos)

# 3. media + sprite sheets + publish (needs Pillow)
python scripts/make_media.py                        # GIFs for the site (parallel)
python tools/export_sheets.py                       # Aseprite-JSON sprite sheets + dist/rigfx-sheets.zip, see docs/SPRITESHEETS.md
bash tools/publish.sh                               # dry run; add --yes to commit + push

# 4. a 2-minute promo video from a project.json (GPU voice + backgrounds for pennies, CPU for the rest)
#    see tools/video/README.md
```
Needs Node >= 18 and Python 3 with Pillow. `node retarget.mjs --help` lists every flag.

## Known limits (v0.2)
- Weapons scale with the body (`weaponS`, default = `armS`) and pose translation scales with the legs/torso. Weapons above ~2.5x can show gaps in the stroke.
- Effects drawn at fixed coordinates inside `src/fx/moves/*.js` (e.g. dust at absolute x) are not rescaled; only the pose is.
- Effects pinned to the body (frost, poison) use an approximate uniform mapping, not per-bone; gear outside the stock silhouette (golem pauldrons) is not mapped.
- Sprite sheets (RGBA, Aseprite JSON + pivot + fps) via `tools/export_sheets.py`, see `docs/SPRITESHEETS.md`. Loader snippets are untested in the engines.

## License
MIT © balmacefa. Built on [patch-gg/pixelfx](https://github.com/patch-gg/pixelfx) (MIT, see `NOTICE-pixelfx-LICENSE.txt`).
