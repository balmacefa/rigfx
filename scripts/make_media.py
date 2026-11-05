"""frames (anim/retarget/<char>/<move>/NNN.png) -> site/media/<char>-<move>.gif (stride 2, pixel-perfect, cropped to the union box)."""
import os, sys, json
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "anim", "retarget"); OUT = os.path.join(ROOT, "site", "media")
os.makedirs(OUT, exist_ok=True)
man = []
for c in sorted(d for d in os.listdir(SRC) if os.path.isdir(os.path.join(SRC, d))):
    for m in sorted(os.listdir(os.path.join(SRC, c))):
        d = os.path.join(SRC, c, m)
        fs = sorted(f for f in os.listdir(d) if f[0].isdigit())[::2]
        ims = [Image.open(os.path.join(d, f)).convert("RGB") for f in fs]
        ims[0].save(os.path.join(OUT, f"{c}-{m}.gif"), save_all=True, append_images=ims[1:], duration=83, loop=0, optimize=True)
        man.append({"char": c, "move": m, "frames": len(ims), "w": ims[0].width, "h": ims[0].height})
json.dump(man, open(os.path.join(ROOT, "site", "media", "index.json"), "w"))
print(len(man), "gifs")
