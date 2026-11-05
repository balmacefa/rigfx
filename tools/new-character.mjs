// Create a character JSON in chars2d/ from a handful of flags (no hand-written palettes).
//
//   node tools/new-character.mjs viking --legS 1.1 --armS 1.15 --thick 1.3 --widthS 1.3 \
//        --head helmet,horns --gear cape,pauldrons,belt --color #c89632 [--core #6b4a2a] [--force]
//   node tools/new-character.mjs --list-gear
//
// Body flags are multipliers of the stock body (1 = stock): legS torsoS armS headS neckS widthS thick  (allowed 0.3 .. 2.5)
// --color = main (shell) colour; --core = joints/secondary colour (default: a darker shifted hue).
import { writeFileSync, existsSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, dirname } from "node:path";

const HEAD_GEAR = ["helmet", "visor", "horns", "wizardhat", "hood", "ears", "mohawk", "tusks", "antenna", "bighair", "crown"];
const BODY_GEAR = ["pauldrons", "cape", "belt", "backpack", "tail"];
const NUM = ["legS", "torsoS", "armS", "headS", "neckS", "widthS", "thick"];
const argv = process.argv.slice(2);

if (argv.includes("--list-gear")) {
  console.log("headGear (--head): " + HEAD_GEAR.join(" "));
  console.log("bodyGear (--gear): " + BODY_GEAR.join(" "));
  process.exit(0);
}
const die = (m) => { console.error("error: " + m); process.exit(1); };
const name = argv.find((a, i) => !a.startsWith("--") && !(argv[i - 1] || "").startsWith("--"));
if (!name || !/^[a-z][a-z0-9_-]*$/.test(name)) die("usage: node tools/new-character.mjs <name> [--legS 1.2 ...] [--head a,b] [--gear a,b] [--color #hex] [--core #hex] [--force]  (name: lowercase letters/digits/-/_)");
const val = (n) => { const i = argv.indexOf("--" + n); return i >= 0 ? argv[i + 1] : undefined; };
for (const a of argv) if (a.startsWith("--") && ![...NUM, "head", "gear", "color", "core", "force", "list-gear"].includes(a.slice(2))) die(`unknown flag ${a}`);

const body = {};
for (const k of NUM) {
  const v = val(k);
  if (v === undefined) continue;
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0.3 || n > 2.5) die(`--${k} must be a number between 0.3 and 2.5 (got ${v})`);
  body[k] = n;
}
const list = (flag, allowed, label) => {
  const v = val(flag);
  if (!v) return [];
  const items = v.split(",").map((s) => s.trim()).filter(Boolean);
  const bad = items.filter((x) => !allowed.includes(x));
  if (bad.length) die(`unknown ${label}: ${bad.join(", ")}. Valid: ${allowed.join(" ")}`);
  return items;
};
const headGear = list("head", HEAD_GEAR, "head gear"), bodyGear = list("gear", BODY_GEAR, "body gear");
if (headGear.length) body.headGear = headGear;
if (bodyGear.length) body.bodyGear = bodyGear;

// ---- colour ramps from one hex
const parse = (h) => { if (!/^#[0-9a-f]{6}$/i.test(h || "")) die(`bad colour "${h}" (use #rrggbb)`); return [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255); };
const toHsl = ([r, g, b]) => {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn;
  if (!d) return [0, 0, l];
  const s = d / (1 - Math.abs(2 * l - 1)), h = mx === r ? ((g - b) / d + 6) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h * 60, s, l];
};
const hsl = (h, s, l) => {
  h = ((h % 360) + 360) % 360; s = Math.max(0, Math.min(1, s)); l = Math.max(0, Math.min(1, l));
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return "#" + [r, g, b].map((v) => Math.round((v + m) * 255).toString(16).padStart(2, "0")).join("");
};
const [H, S] = toHsl(parse(val("color") || "#8a8fa6"));
const coreArg = val("core");
const [Hc, Sc] = coreArg ? toHsl(parse(coreArg)) : [H + 150, Math.max(0.35, S * 0.8)];
const pal = {
  shell: [hsl(H, S * 0.85, 0.9), hsl(H, S, 0.72), hsl(H, S, 0.55), hsl(H, S * 0.95, 0.38)],
  core: [hsl(Hc, Sc, 0.42), hsl(Hc, Sc, 0.3), hsl(Hc, Sc, 0.2), hsl(Hc, Sc, 0.2)],
  ink: hsl(H, 0.5, 0.06), seam: hsl(H, 0.45, 0.15), mark: hsl(Hc, 0.9, 0.82),
};

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const dir = join(ROOT, "chars2d"), file = join(dir, name + ".json");
mkdirSync(dir, { recursive: true });
if (existsSync(file) && !argv.includes("--force")) die(`${file} already exists (use --force to overwrite)`);
writeFileSync(file, JSON.stringify({ name, body: Object.keys(body).length ? body : null, pal }));
console.log(`wrote ${file}\n${JSON.stringify({ name, body, pal }, null, 1)}\nnext: node retarget.mjs --chars ${name}`);
