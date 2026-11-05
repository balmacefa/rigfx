"""anim/retarget/<char>/<move>/NNN.png -> site/media/<char>-<move>.gif (+ index.json, chars.json), in parallel.

  python scripts/make_media.py                 all, cpus-1 workers
  python scripts/make_media.py --src DIR --out DIR --stride 3 --workers 4 --only giant,wizard
GIFs use 1 of every `stride` frames (default 3) at 100 ms. index.json is rebuilt from the GIFs on disk, so --only is safe.
"""
import argparse, glob, json, os
from concurrent.futures import ProcessPoolExecutor
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument("--src", default=os.path.join(ROOT, "anim", "retarget"))
ap.add_argument("--out", default=os.path.join(ROOT, "site", "media"))
ap.add_argument("--stride", type=int, default=3)
ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) - 1))
ap.add_argument("--only", default="")
A = ap.parse_args()


def one(job):
    c, m, d = job
    fs = sorted(f for f in os.listdir(d) if f[:1].isdigit() and f.endswith(".png"))[:: A.stride]
    if not fs:
        return None
    ims = [Image.open(os.path.join(d, f)).convert("RGB") for f in fs]
    ims[0].save(os.path.join(A.out, f"{c}-{m}.gif"), save_all=True, append_images=ims[1:], duration=100, loop=0, optimize=True)
    return {"char": c, "move": m, "frames": len(ims), "w": ims[0].width, "h": ims[0].height}


if __name__ == "__main__":
    os.makedirs(A.out, exist_ok=True)
    only = {x for x in A.only.split(",") if x}
    jobs = []
    for c in sorted(d for d in os.listdir(A.src) if os.path.isdir(os.path.join(A.src, d))):
        if only and c not in only:
            continue
        for m in sorted(os.listdir(os.path.join(A.src, c))):
            if os.path.isdir(os.path.join(A.src, c, m)):
                jobs.append((c, m, os.path.join(A.src, c, m)))
    with ProcessPoolExecutor(A.workers) as ex:
        done = [r for r in ex.map(one, jobs, chunksize=4) if r]
    # index.json = every GIF now on disk (keeps entries from earlier runs when --only is used)
    idx = {}
    for f in glob.glob(os.path.join(A.out, "*.gif")):
        c, m = os.path.basename(f)[:-4].split("-", 1)
        idx[(c, m)] = {"char": c, "move": m}
    prev = os.path.join(A.out, "index.json")
    old = {(e["char"], e["move"]): e for e in json.load(open(prev))} if os.path.exists(prev) else {}
    for r in done:
        old[(r["char"], r["move"])] = r
    final = [old.get(k, v) for k, v in sorted(idx.items())]
    json.dump(final, open(prev, "w"))
    chars = {}
    for f in sorted(glob.glob(os.path.join(ROOT, "chars2d", "*.json"))):
        j = json.load(open(f, encoding="utf8"))
        chars[j["name"]] = j
    if chars:
        json.dump(chars, open(os.path.join(A.out, "chars.json"), "w"))
    print(f"{len(done)} gifs written, {len(final)} in index, {len(chars)} characters")
