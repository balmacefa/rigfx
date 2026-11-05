// Transparent frames for every clip named in project.json ("char:move" in scene.clips / scene.grid.items), via retarget.mjs.
//   node <rigfx>/tools/video/vidframes.mjs            (run from the project dir; honours PIXELFX_DIR and --jobs N)
// Output: frames/<char>/<move>/NNN.png (RGBA) + frames/manifest.json (pivot, fps) -- what build.py reads.
import fs from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join, dirname, resolve } from "node:path";

const RETARGET = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "retarget.mjs");
const P = JSON.parse(fs.readFileSync("project.json", "utf8"));
const need = new Map(); // move -> Set(char)
for (const s of P.segments) {
  const sc = s.scene || {};
  for (const c of [...(sc.clips || []).map((x) => x.clip), ...((sc.grid && sc.grid.items) || []).map((x) => x.clip)]) {
    const [ch, mv] = c.split(":");
    if (!need.has(mv)) need.set(mv, new Set());
    need.get(mv).add(ch);
  }
}
const jobs = process.argv.includes("--jobs") ? ["--jobs", process.argv[process.argv.indexOf("--jobs") + 1]] : [];
const out = resolve("frames");
let bad = 0;
for (const [mv, chars] of need) {
  const r = spawnSync(process.execPath, [RETARGET, mv, "--chars", [...chars].join(","), "--transparent", "--out", out, ...jobs], { stdio: "inherit", env: process.env });
  if (r.status) bad++;
}
console.log(bad ? `${bad} move(s) failed` : `frames ready for ${need.size} move(s) in ${out}`);
process.exit(bad ? 1 : 0);
