// GPU assets for a video project (run from the project dir, next to project.json):
//   node <rigfx>/tools/video/gen.mjs            backgrounds (FLUX schnell) + narration (Chatterbox); skips files that exist
//   node <rigfx>/tools/video/gen.mjs --dry      only print what would be generated and the estimated cost
//   node <rigfx>/tools/video/gen.mjs --only bg|vo   [--force id,id]  regenerate those ids
// Endpoints that worked (2026-11):
//   voice   dovnz0ml2w3kqa (serverless Chatterbox, cold start ~90 s, ~12 s exec per segment)
//           input {text, exaggeration, cfg_weight, temperature} -> output.audio_base64 (wav)
//   images  black-forest-labs-flux-1-schnell  input {prompt, width:1344, height:768, num_inference_steps:4}
//           -> output.result (jpeg URL), output.cost = $0.003 each
import fs from "node:fs";
import { run, totalUsd } from "./rp.mjs";

const D = process.cwd();
const argv = process.argv.slice(2), has = (f) => argv.includes("--" + f), val = (f) => { const i = argv.indexOf("--" + f); return i >= 0 ? argv[i + 1] : undefined; };
const P = JSON.parse(fs.readFileSync("project.json", "utf8"));
const ids = P.segments.map((s) => s.id);
if (new Set(ids).size !== ids.length) { console.error("duplicate segment ids in project.json"); process.exit(1); }
const force = new Set((val("force") || "").split(",").filter(Boolean));
const only = val("only");
const V = { endpoint: "dovnz0ml2w3kqa", exaggeration: 0.45, cfg_weight: 0.5, temperature: 0.75, ...(P.voice || {}) };
const I = { endpoint: "black-forest-labs-flux-1-schnell", width: 1344, height: 768, steps: 4, style: "", ...(P.image || {}) };
fs.mkdirSync("bg", { recursive: true }); fs.mkdirSync("vo", { recursive: true });

const bgTodo = Object.entries(P.bg || {}).filter(([k]) => force.has(k) || !fs.existsSync(`bg/${k}.jpg`));
const voTodo = P.segments.filter((s) => force.has(s.id) || !fs.existsSync(`vo/${s.id}.wav`));
console.log(`backgrounds to generate: ${bgTodo.length} (~$${(bgTodo.length * 0.003).toFixed(3)}), narration segments: ${voTodo.length} (cents), spent so far: $${totalUsd(D).toFixed(3)}`);
if (has("dry")) process.exit(0);

if (only !== "vo") for (const [k, prompt] of bgTodo) {
  const j = await run(I.endpoint, { prompt: prompt + (I.style ? ", " + I.style : ""), width: I.width, height: I.height, num_inference_steps: I.steps }, { dir: D, note: "bg " + k });
  if (j.status !== "COMPLETED") { console.log("BG FAIL", k, JSON.stringify(j).slice(0, 200)); continue; }
  fs.writeFileSync(`bg/${k}.jpg`, Buffer.from(await (await fetch(j.output.result)).arrayBuffer()));
  console.log("bg", k, j.output.cost);
}
if (only !== "bg") for (const s of voTodo) {
  const j = await run(V.endpoint, { text: s.text, exaggeration: V.exaggeration, cfg_weight: V.cfg_weight, temperature: V.temperature }, { wait: 90000, dir: D, note: "vo " + s.id });
  if (j.status !== "COMPLETED") { console.log("TTS FAIL", s.id, JSON.stringify(j).slice(0, 300)); continue; }
  fs.writeFileSync(`vo/${s.id}.wav`, Buffer.from(j.output.audio_base64, "base64"));
  console.log("vo", s.id, j.executionTime, "ms");
}
console.log(`GPU spent (logged in cost.json): $${totalUsd(D).toFixed(3)} + voice calls (not priced by the endpoint, ~cents)`);
