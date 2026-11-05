# rigfx — one animation, any body

Retarget one library of 2D pixel-art animations onto characters of any proportions, with no re-animating and no GPU.
Live demo: https://rigfx.balmacefa.com (also https://balmacefa.github.io/rigfx/)

A character is a JSON file of proportion multipliers (`legS`, `torsoS`, `armS`, `headS`, `neckS`, `widthS`, `thick`) plus a palette.
The rig solves every pose from where the hands and feet should go. The retargeting layer re-aims those targets to the new limb lengths, so
the same 12 moves (sword combo, fireball, ground pound, rocket launcher...) fit a giant, a chibi, a lanky mage or a long-armed brute.

## Run it
```bash
git clone https://github.com/patch-gg/pixelfx pixelfx        # MIT: the effects + rig this builds on
git -C pixelfx checkout a841596
git -C pixelfx apply ../patches/rig-retarget.patch            # adds setBody() / setActorPalette()
node retarget.mjs                  # all moves x all characters -> anim/retarget/<char>/<move>/NNN.png
node retarget.mjs moves/sword-combo
python scripts/make_media.py       # GIFs for the site (needs Pillow)
```
Needs Node >= 18. Add a character by dropping a JSON in `chars2d/` (see the example on the site).

## Known limits (quick and dirty v0.1)
- Weapons are not scaled with the body. Pose translation (`x`/`y`, jump height) is not rescaled.
- Effects pinned to the body (frost, poison) assume the stock 24x38 body.
- No sprite-sheet + JSON export yet (PNG frames and GIFs only).

## License
MIT © balmacefa. Built on [patch-gg/pixelfx](https://github.com/patch-gg/pixelfx) (MIT, see `NOTICE-pixelfx-LICENSE.txt`).
