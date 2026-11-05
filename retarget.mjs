// Retarget matrix: every move x every body in chars2d/. One animation library, any proportions. 0 GPU.
//
//   node retarget.mjs                               all moves x all characters, parallel (cpus-1 jobs)
//   node retarget.mjs moves/sword-combo             one move (positional args, "moves/" prefix optional)
//   node retarget.mjs --chars giant,wizard --moves sword-combo,fireball-throw
//   node retarget.mjs --jobs 4 --out D:/tmp/anim    --out: output root (default ./anim/retarget)
//   node retarget.mjs --transparent                 bg "none": RGBA frames with alpha (for videos / compositing)
//   PIXELFX_DIR=C:/path/to/pixelfx node retarget.mjs    the patched pixelfx clone (default ./pixelfx)
//
// Output: <out>/<char>/<move>/NNN.png + sheet.png, and <out>/manifest.json
//   [{char, move, frames, w, h, fps, pivot:[x,y], dir, rel}]  (merged with an existing manifest, entries replaced by char+move)
import { mkdirSync, writeFileSync, readdirSync, readFileSync, existsSync, renameSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, dirname, resolve } from "node:path";
import { fork } from "node:child_process";
import os from "node:os";

const HERE = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const flag = (n) => argv.includes("--" + n);
const opt = (n, d) => { const i = argv.indexOf("--" + n); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : d; };
const BOOL = new Set(["--transparent", "--child", "--help"]), VAL = new Set(["--jobs", "--chars", "--moves", "--out", "--tasks"]);
const positional = argv.filter((a, i) => !a.startsWith("--") && !VAL.has(argv[i - 1]));
const REPO = resolve(process.env.PIXELFX_DIR || join(HERE, "pixelfx"));
const OUT = resolve(opt("out", join(HERE, "anim", "retarget")));
const TRANSPARENT = flag("transparent");
const FPS = 24;
const U = (p) => "file:///" + p.split(String.fromCharCode(92)).join("/");
const norm = (m) => (m.startsWith("moves/") ? m : "moves/" + m);

if (flag("help")) {
  console.log(readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").slice(0, 12).join("\n"));
  process.exit(0);
}
if (!existsSync(join(REPO, "tools/lib/fxlib.mjs"))) {
  console.error(`pixelfx not found at ${REPO}. Clone patch-gg/pixelfx there, or set PIXELFX_DIR.`);
  process.exit(1);
}

const loadChars = (only) => {
  const dir = join(HERE, "chars2d");
  const all = readdirSync(dir).filter((f) => f.endsWith(".json")).map((f) => JSON.parse(readFileSync(join(dir, f), "utf8")));
  return only ? all.filter((c) => only.includes(c.name)) : all;
};
const allMoves = () => readdirSync(join(REPO, "src/fx/moves")).filter((f) => f.endsWith(".js")).map((f) => "moves/" + f.replace(".js", ""));

// ---------- child: renders a list of {char, move} tasks ----------
async function child() {
  const tasks = JSON.parse(readFileSync(opt("tasks"), "utf8"));
  const { loadEffect, renderAct } = await import(U(join(REPO, "tools/lib/fxlib.mjs")));
  const { encodePNG } = await import(U(join(REPO, "tools/lib/png.mjs")));
  const { setActorPalette, setBody } = await import(U(join(REPO, "src/core/rig.js")));
  const chars = Object.fromEntries(loadChars().map((c) => [c.name, c]));
  const fxCache = {}, part = [];
  const sheetOf = (fr, w, h) => { // horizontal strip of up to 12 evenly picked frames
    const n = Math.min(12, fr.length), pick = Array.from({ length: n }, (_, i) => fr[Math.round((i * (fr.length - 1)) / Math.max(1, n - 1))]);
    const out = new Uint8Array(w * n * h * 4);
    pick.forEach((f, k) => { for (let y = 0; y < h; y++) out.set(f.subarray(y * w * 4, (y + 1) * w * 4), (y * w * n + k * w) * 4); });
    return { w: w * n, h, data: out };
  };
  for (const t of tasks) {
    const c = chars[t.char], fx = (fxCache[t.move] ??= await loadEffect(t.move, join(REPO, "src", "fx")));
    setBody(c.body); setActorPalette(c.pal);
    const r = renderAct(fx, { fps: FPS, bg: TRANSPARENT ? "none" : "dark", target: false, hold: TRANSPARENT ? 0.3 : 0.2 });
    const name = t.move.split("/")[1], rel = `${c.name}/${name}`, dir = join(OUT, c.name, name);
    mkdirSync(dir, { recursive: true });
    const pix = (f) => (TRANSPARENT ? f.clear : f.color);
    r.frames.forEach((f, i) => writeFileSync(join(dir, String(i).padStart(3, "0") + ".png"), encodePNG(r.w, r.h, pix(f))));
    const s = sheetOf(r.frames.map(pix), r.w, r.h);
    writeFileSync(join(dir, "sheet.png"), encodePNG(s.w, s.h, s.data));
    part.push({ char: c.name, move: t.move, frames: r.frames.length, w: r.w, h: r.h, fps: FPS, pivot: r.pivot, dir, rel });
    console.log(c.name, t.move, r.frames.length);
  }
  setBody(null); setActorPalette(null);
  writeFileSync(opt("tasks").replace(/\.json$/, ".manifest.json"), JSON.stringify(part));
}

// ---------- parent: build the task list, fan out, merge manifests ----------
async function parent() {
  const only = opt("chars")?.split(",").filter(Boolean);
  const chars = loadChars(only);
  if (only) for (const n of only) if (!chars.find((c) => c.name === n)) { console.error("unknown character:", n); process.exit(1); }
  const moveArgs = [...positional, ...(opt("moves", "")?.split(",").filter(Boolean) ?? [])].map(norm);
  const moves = moveArgs.length ? moveArgs : allMoves();
  const tasks = moves.flatMap((m) => chars.map((c) => ({ char: c.name, move: m })));
  if (!tasks.length) { console.error("nothing to render"); process.exit(1); }
  const jobs = Math.max(1, Math.min(+opt("jobs", Math.max(1, os.cpus().length - 1)) || 1, tasks.length));
  mkdirSync(OUT, { recursive: true });
  const tmp = join(os.tmpdir(), "rigfx-retarget-" + process.pid);
  mkdirSync(tmp, { recursive: true });
  const per = Math.ceil(tasks.length / jobs), files = [];
  for (let j = 0; j < jobs; j++) { // contiguous chunks keep the same move together (one effect load per child)
    const chunk = tasks.slice(j * per, (j + 1) * per);
    if (!chunk.length) continue;
    const f = join(tmp, `t${j}.json`);
    writeFileSync(f, JSON.stringify(chunk));
    files.push(f);
  }
  const t0 = Date.now();
  console.log(`${tasks.length} renders (${chars.length} chars x ${moves.length} moves), ${files.length} jobs, out ${OUT}${TRANSPARENT ? ", transparent" : ""}`);
  const fwd = ["--out", OUT, ...(TRANSPARENT ? ["--transparent"] : [])];
  const codes = await Promise.all(files.map((f) => new Promise((ok) => {
    const p = fork(fileURLToPath(import.meta.url), ["--child", "--tasks", f, ...fwd], { env: process.env, stdio: ["ignore", "inherit", "inherit", "ipc"] });
    p.on("exit", (c) => ok(c ?? 1));
  })));
  const part = files.flatMap((f) => { const m = f.replace(/\.json$/, ".manifest.json"); return existsSync(m) ? JSON.parse(readFileSync(m, "utf8")) : []; });
  const mpath = join(OUT, "manifest.json");
  const old = existsSync(mpath) ? JSON.parse(readFileSync(mpath, "utf8")) : [];
  const key = (e) => e.char + "|" + e.move, fresh = new Set(part.map(key));
  const merged = [...old.filter((e) => !fresh.has(key(e))), ...part].sort((a, b) => key(a).localeCompare(key(b)));
  writeFileSync(mpath + ".tmp", JSON.stringify(merged, null, 1));
  renameSync(mpath + ".tmp", mpath);
  rmSync(tmp, { recursive: true, force: true });
  const bad = codes.filter((c) => c !== 0).length;
  console.log(`done: ${part.length}/${tasks.length} rendered in ${((Date.now() - t0) / 1000).toFixed(1)}s, manifest ${merged.length} entries${bad ? `, ${bad} CHILD(REN) FAILED` : ""}`);
  process.exit(bad || part.length !== tasks.length ? 1 : 0);
}

await (flag("child") ? child() : parent());
