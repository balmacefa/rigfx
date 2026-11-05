#!/usr/bin/env python3
"""Pack rigfx retarget frames into Aseprite-JSON-hash sprite sheets (Pillow only)."""
import argparse, json, math, os, re, sys, time, zipfile
from multiprocessing import Pool
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEF_SRC = r"C:\Users\fabia\OneDrive\Escritorio\pixelfx-demo\anim\retarget"
DEF_OUT = os.path.join(ROOT, "dist", "sheets")
ALPHA_DIR = r"C:\Users\fabia\rigfx-video\frames"
CHARS = os.path.join(ROOT, "chars2d")
MAXPX = 8192
FPS, DUR = 24, 42


def frame_files(d):
    return sorted(os.path.join(d, f) for f in os.listdir(d) if re.fullmatch(r"\d+\.png", f))


def grid(n, w, h):
    maxc = max(1, MAXPX // w)
    cols = min(maxc, max(1, math.ceil(math.sqrt(n * h / w))))  # near-square in pixels
    rows = math.ceil(n / cols)
    while rows * h > MAXPX and cols < maxc:
        cols += 1
        rows = math.ceil(n / cols)
    if rows * h > MAXPX:
        raise ValueError("sheet exceeds %dpx: %d frames of %dx%d" % (MAXPX, n, w, h))
    return cols, rows


def job(a):
    char, move, src_dir, out, transparent, pivot, fps = a
    try:
        files = frame_files(src_dir)
        if not files:
            raise ValueError("no frames")
        n = len(files)
        w, h = Image.open(files[0]).size
        cols, rows = grid(n, w, h)
        sheet = Image.new("RGBA", (cols * w, rows * h), (0, 0, 0, 0))
        frames = {}
        for i, f in enumerate(files):
            im = Image.open(f).convert("RGBA")
            if im.size != (w, h):
                raise ValueError("size mismatch in " + f)
            x, y = (i % cols) * w, (i // cols) * h
            sheet.paste(im, (x, y))
            frames["%s-%s-%03d" % (char, move, i)] = {
                "frame": {"x": x, "y": y, "w": w, "h": h}, "rotated": False, "trimmed": False,
                "spriteSourceSize": {"x": 0, "y": 0, "w": w, "h": h},
                "sourceSize": {"w": w, "h": h}, "duration": DUR}
        od = os.path.join(out, char)
        os.makedirs(od, exist_ok=True)
        png = os.path.join(od, move + ".png")
        sheet.save(png, optimize=False, compress_level=6)
        rf = {"char": char, "move": move, "fps": fps, "frame_count": n, "transparent": transparent}
        if pivot:
            rf["pivot"] = pivot
        cj = os.path.join(CHARS, char + ".json")
        if os.path.exists(cj):
            rf["body"] = json.load(open(cj, encoding="utf-8"))
        meta = {"app": "rigfx export_sheets", "version": "1.0", "image": move + ".png",
                "format": "RGBA8888", "size": {"w": sheet.width, "h": sheet.height}, "scale": "1",
                "frameTags": [{"name": move, "from": 0, "to": n - 1, "direction": "forward"}],
                "rigfx": rf}
        jp = os.path.join(od, move + ".json")
        with open(jp, "w", encoding="utf-8") as fh:
            json.dump({"frames": frames, "meta": meta}, fh, indent=1)
        return {"char": char, "move": move, "frames": n, "w": w, "h": h, "cols": cols, "rows": rows,
                "sheet": [sheet.width, sheet.height], "transparent": transparent,
                "png": "%s/%s.png" % (char, move), "json": "%s/%s.json" % (char, move),
                "png_bytes": os.path.getsize(png), "json_bytes": os.path.getsize(jp)}
    except Exception as e:
        return {"char": char, "move": move, "error": repr(e)}


def discover(src, only):
    man = {}
    mp = os.path.join(src, "manifest.json")
    if os.path.exists(mp):
        for e in json.load(open(mp, encoding="utf-8")):
            man[(e["char"], e["move"].split("/")[-1])] = e
    combos = []
    for c in sorted(os.listdir(src)):
        cd = os.path.join(src, c)
        if not os.path.isdir(cd):
            continue
        for m in sorted(os.listdir(cd)):
            if os.path.isdir(os.path.join(cd, m)) and frame_files(os.path.join(cd, m)):
                combos.append((c, m))
    sel = []
    for c, m in combos:
        if only and not any(o == c or o == c + ":" + m for o in only):
            continue
        d, tr = os.path.join(src, c, m), False
        ad = os.path.join(ALPHA_DIR, "%s-%s" % (c, m))
        if os.path.isdir(ad) and frame_files(ad):
            d, tr = ad, True
        e = man.get((c, m), {})
        sel.append((c, m, d, tr, e.get("pivot"), e.get("fps", FPS)))
    return sel


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=DEF_SRC)
    ap.add_argument("--out", default=DEF_OUT)
    ap.add_argument("--only", action="append", default=[], help="char or char:move (repeatable, comma ok)")
    ap.add_argument("--workers", type=int, default=6)
    a = ap.parse_args()
    only = [x for s in a.only for x in s.split(",") if x]
    t0 = time.time()
    jobs = [(c, m, d, a.out, tr, pv, fps) for c, m, d, tr, pv, fps in discover(a.src, only)]
    with Pool(a.workers) as p:
        res = p.map(job, jobs, chunksize=1)
    ok = [r for r in res if "error" not in r]
    bad = [r for r in res if "error" in r]
    os.makedirs(a.out, exist_ok=True)
    idx = {"count": len(ok), "total_bytes": sum(r["png_bytes"] + r["json_bytes"] for r in ok),
           "sheets": ok, "failures": bad}
    with open(os.path.join(a.out, "index.json"), "w", encoding="utf-8") as fh:
        json.dump(idx, fh, indent=1)
    zp = os.path.join(os.path.dirname(os.path.abspath(a.out)), "rigfx-sheets.zip")
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_STORED) as z:  # PNGs already compressed
        for r in ok:
            z.write(os.path.join(a.out, r["png"]), "sheets/" + r["png"])
            z.write(os.path.join(a.out, r["json"]), "sheets/" + r["json"])
        z.write(os.path.join(a.out, "index.json"), "sheets/index.json")
    print("sheets=%d failures=%d MB=%.1f zip=%.1fMB time=%.1fs" % (
        len(ok), len(bad), idx["total_bytes"] / 1e6, os.path.getsize(zp) / 1e6, time.time() - t0))
    for b in bad:
        print("FAIL", b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
