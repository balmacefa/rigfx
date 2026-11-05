"""project.json -> seg/<id>.mp4 (one silent 1080p clip per segment, duration = narration + 0.75 s). Parallel across segments.

Run from the project dir (the one holding project.json, bg/, vo/, frames/):
    python <rigfx>/tools/video/build.py                 all segments, cpus-1 workers
    python <rigfx>/tools/video/build.py s03 s05 --workers 2
    python <rigfx>/tools/video/build.py --still s05:40   write still_s05.png (frame 40) to check the layout fast

Scene keys (all optional, any combination; "type" is only a human label: title, clip, grid, 4up, code, outro):
  "title":  {"y":150, "lines":[{"text":"rigfx","size":190,"color":"accent"}, ...]}
  "clips":  [{"clip":"giant:sword-combo","x":440,"y":940,"scale":5,"label":"giant","start":0,"loop":true}]
  "grid":   {"items":[{"clip":"a:move","label":"a"}...],"cols":6,"cellW":320,"cellH":300,"y0":125,"scale":2.1,"crop":[x0,y0,x1,y1],"start":4}
  "panel":  {"box":[x0,y0,x1,y1],"lines":[{"text":"...","size":44,"color":"accent","mono":false}],"x":1330,"y":330,"step":62}
Clip frames come from frames/<char>/<move>/NNN.png (node retarget.mjs --transparent --out frames) + frames/manifest.json (pivot).
"""
import os, sys, json, glob, math, subprocess, argparse
from concurrent.futures import ProcessPoolExecutor
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H, FPS = 1920, 1080, 24
ACC = (255, 184, 74)
FONT = os.environ.get("FONT", "C:/Windows/Fonts/segoeuib.ttf")
MONO = os.environ.get("MONO", "C:/Windows/Fonts/consola.ttf")
_fonts, _clips, _bgs, _man = {}, {}, {}, {}


def font(sz, mono=False):
    k = (sz, mono)
    if k not in _fonts:
        try:
            _fonts[k] = ImageFont.truetype(MONO if mono else FONT, sz)
        except OSError:
            _fonts[k] = ImageFont.load_default()
    return _fonts[k]


def manifest(D):
    if D not in _man:
        p = os.path.join(D, "frames", "manifest.json")
        _man[D] = {e["rel"]: e for e in json.load(open(p))} if os.path.exists(p) else {}
    return _man[D]


def clip(D, name):
    """'char:move' -> (frames, pivot)"""
    if (D, name) not in _clips:
        c, m = name.split(":")
        fs = sorted(glob.glob(os.path.join(D, "frames", c, m, "[0-9]*.png")))
        if not fs:
            raise SystemExit(f"no frames for {name}: run vidframes.mjs first")
        e = manifest(D).get(f"{c}/{m}")
        _clips[(D, name)] = ([Image.open(f).convert("RGBA") for f in fs], tuple(e["pivot"]) if e else (fs and Image.open(fs[0]).width // 2, Image.open(fs[0]).height - 6))
    return _clips[(D, name)]


def bgframe(D, k, t, dur, dark=0.62):
    if (D, k) not in _bgs:
        _bgs[(D, k)] = Image.open(os.path.join(D, "bg", f"{k}.jpg")).convert("RGB")
    im = _bgs[(D, k)]
    z = 1.0 + 0.07 * (t / max(dur, 0.1))  # slow Ken Burns zoom
    w, h = im.size
    cw, ch = w / z, h / z
    x0, y0 = (w - cw) / 2, (h - ch) / 2
    out = im.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize((W, H), Image.BICUBIC)
    return Image.eval(out, lambda v: int(v * dark)).convert("RGBA")


def sprite(img, s):
    # pixel-crisp at any scale: nearest up to the next integer, then smooth down to the exact size
    n = max(1, math.ceil(s))
    up = img.resize((img.width * n, img.height * n), Image.NEAREST)
    return up if n == s else up.resize((max(1, int(img.width * s)), max(1, int(img.height * s))), Image.LANCZOS)


_sh = {}
def shadow(canvas, cx, gy, w):
    # small cached patch instead of a full-canvas blur per call (this was 10x of the render time)
    if w not in _sh:
        sh = Image.new("RGBA", (w + 24, 48), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((12, 12, 12 + w, 36), fill=(0, 0, 0, 110))
        _sh[w] = sh.filter(ImageFilter.GaussianBlur(4))
    canvas.alpha_composite(_sh[w], (max(0, cx - w // 2 - 12), max(0, gy - 22)))


def text(d, xy, s, sz, fill=(255, 255, 255), mono=False, anchor="la", outline=3):
    d.text(xy, s, font=font(sz, mono), fill=fill, anchor=anchor, stroke_width=outline, stroke_fill=(10, 8, 16))


def color(c):
    return ACC if c in (None, "accent") else tuple(c) if isinstance(c, (list, tuple)) else (255, 255, 255)


def place(canvas, D, name, fi, cx, gy, s, loop=True, crop=None, shade=True):
    frames, (px, py) = clip(D, name)
    im = frames[fi % len(frames) if loop else min(fi, len(frames) - 1)]
    if crop:
        im = im.crop(tuple(crop)); px, py = px - crop[0], py - crop[1]
    if shade:
        shadow(canvas, int(cx), int(gy), int(70 * s))
    canvas.alpha_composite(sprite(im, s), (int(cx - px * s), int(gy - py * s)))


def draw_scene(D, seg, fi, t, dur):
    sc = seg.get("scene", {})
    c = bgframe(D, seg["bg"], t, dur)
    d = ImageDraw.Draw(c)
    g = sc.get("grid")
    if g:
        items, cols = g["items"], g.get("cols", 4)
        cw, ch, y0, s = g.get("cellW", 320), g.get("cellH", 300), g.get("y0", 125), g.get("scale", 2)
        rows = math.ceil(len(items) / cols)
        for k, it in enumerate(items):
            r, cc = divmod(k, cols)
            nin = cols if r < rows - 1 else len(items) - cols * (rows - 1)
            cx = (W - nin * cw) // 2 + cc * cw + cw // 2
            gy = y0 + r * ch + ch - 60
            place(c, D, it["clip"], fi + g.get("start", 0), cx, gy, s, crop=g.get("crop"))
            if it.get("label"):
                text(d, (cx, gy + 18), it["label"], 26, anchor="ma")
    for cl in sc.get("clips", []):
        place(c, D, cl["clip"], fi + cl.get("start", 0), cl.get("x", W // 2), cl.get("y", 940), cl.get("scale", 4), loop=cl.get("loop", True), shade=cl.get("shadow", True))
        if cl.get("label"):
            text(d, (cl.get("x", W // 2), cl.get("y", 940) + 12), cl["label"], cl.get("labelSize", 32), anchor="ma")
    p = sc.get("panel")
    if p:
        if p.get("box"):
            ov = Image.new("RGBA", c.size, (0, 0, 0, 0))
            ImageDraw.Draw(ov).rounded_rectangle(tuple(p["box"]), 22, fill=(12, 10, 20, p.get("alpha", 160)), outline=(255, 184, 74, 90), width=2)
            c.alpha_composite(ov); d = ImageDraw.Draw(c)
        x, y, step = p.get("x", p["box"][0] + 35 if p.get("box") else 80), p.get("y", p["box"][1] + 35 if p.get("box") else 80), p.get("step", 62)
        for ln in p.get("lines", []):
            text(d, (x, y), ln["text"], ln.get("size", 44), color(ln.get("color")) if ln.get("color") else (255, 255, 255), mono=ln.get("mono", False), outline=0 if ln.get("mono") else 3)
            y += ln.get("step", step)
    ti = sc.get("title")
    if ti:
        y = ti.get("y", 150)
        for ln in ti["lines"]:
            text(d, (W // 2, y), ln["text"], ln["size"], color(ln.get("color")), anchor="ma", outline=4)
            y += int(ln["size"] * 1.25)
    return c.convert("RGB")


def vo_dur(D, sid):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", os.path.join(D, "vo", f"{sid}.wav")]).strip())


def render_seg(job):
    D, seg, dur = job
    n = int(dur * FPS)
    out = os.path.join(D, "seg", f"{seg['id']}.mp4")
    p = subprocess.Popen(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-vf", f"fade=in:0:10,fade=out:{n - 10}:10",
                          "-c:v", "libx264", "-crf", "18", "-preset", "veryfast", "-pix_fmt", "yuv420p", out], stdin=subprocess.PIPE)
    for fi in range(n):
        p.stdin.write(draw_scene(D, seg, fi, fi / FPS, dur).tobytes())
    p.stdin.close()
    if p.wait():
        raise SystemExit(f"ffmpeg failed on {seg['id']}")
    return seg["id"], round(dur, 1)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--dir", default=os.getcwd())
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--still", default="")
    a = ap.parse_args()
    D = os.path.abspath(a.dir)
    P = json.load(open(os.path.join(D, "project.json"), encoding="utf8"))
    segs = P["segments"]
    ids = [s["id"] for s in segs]
    if len(set(ids)) != len(ids):
        raise SystemExit(f"duplicate segment ids in project.json: {sorted({i for i in ids if ids.count(i) > 1})}")
    os.makedirs(os.path.join(D, "seg"), exist_ok=True)
    durs = {s["id"]: max(vo_dur(D, s["id"]) + 0.75, 3.6) for s in segs}
    json.dump(durs, open(os.path.join(D, "seg", "durs.json"), "w"))
    if a.still:
        sid, fr = a.still.split(":")
        seg = next(s for s in segs if s["id"] == sid)
        draw_scene(D, seg, int(fr), int(fr) / FPS, durs[sid]).save(os.path.join(D, f"still_{sid}.png"))
        print("wrote", f"still_{sid}.png")
        sys.exit(0)
    todo = [s for s in segs if not a.ids or s["id"] in a.ids]
    with ProcessPoolExecutor(a.workers) as ex:
        for sid, d in ex.map(render_seg, [(D, s, durs[s["id"]]) for s in todo]):
            print(sid, d, "s", flush=True)
    print("total", round(sum(durs.values()), 1), "s")
