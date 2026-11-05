// Retarget matrix: every move x every body in chars2d/. One animation library, any proportions. 0 GPU.
// usage: node retarget.mjs [move ...]   (default: all moves/*)   -> anim/retarget/<char>/<move>/NNN.png + sheets
import { mkdirSync, writeFileSync, readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, dirname } from "node:path";
const HERE = dirname(fileURLToPath(import.meta.url)), REPO = join(HERE, "pixelfx");
const U = p => "file:///" + p.split(String.fromCharCode(92)).join("/");
const { loadEffect, renderAct } = await import(U(join(REPO, "tools/lib/fxlib.mjs")));
const { encodePNG } = await import(U(join(REPO, "tools/lib/png.mjs")));
const { setActorPalette, setBody } = await import(U(join(REPO, "src/core/rig.js")));
const chars = readdirSync(join(HERE, "chars2d")).filter(f => f.endsWith(".json")).map(f => JSON.parse(readFileSync(join(HERE, "chars2d", f), "utf8")));
const moves = process.argv.length > 2 ? process.argv.slice(2) : readdirSync(join(REPO, "src/fx/moves")).map(f => "moves/" + f.replace(".js", ""));
const sheetOf = (fr, w, h) => { // horizontal strip of up to 12 evenly picked frames
  const n = Math.min(12, fr.length), pick = Array.from({ length: n }, (_, i) => fr[Math.round(i * (fr.length - 1) / Math.max(1, n - 1))]);
  const out = new Uint8Array(w * n * h * 4);
  pick.forEach((f, k) => { for (let y = 0; y < h; y++) out.set(f.subarray(y * w * 4, (y + 1) * w * 4), (y * w * n + k * w) * 4); });
  return { w: w * n, h, data: out };
};
const manifest = [];
for (const mv of moves) {
  const fx = await loadEffect(mv, join(REPO, "src", "fx"));
  for (const c of chars) {
    setBody(c.body); setActorPalette(c.pal);
    const r = renderAct(fx, { fps: 24, bg: "dark", target: false, hold: 0.2 });
    const dir = join(HERE, "anim", "retarget", c.name, mv.split("/")[1]);
    mkdirSync(dir, { recursive: true });
    r.frames.forEach((f, i) => writeFileSync(join(dir, String(i).padStart(3, "0") + ".png"), encodePNG(r.w, r.h, f.color)));
    const s = sheetOf(r.frames.map(f => f.color), r.w, r.h);
    writeFileSync(join(dir, "sheet.png"), encodePNG(s.w, s.h, s.data));
    manifest.push({ char: c.name, move: mv, frames: r.frames.length, w: r.w, h: r.h, dir });
    console.log(c.name, mv, r.frames.length);
  }
}
setBody(null); setActorPalette(null);
writeFileSync(join(HERE, "anim", "retarget", "manifest.json"), JSON.stringify(manifest, null, 1));
