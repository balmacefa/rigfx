// RunPod helper. The API key is read from the pwmgr vault at call time and is NEVER printed or logged.
//   node C:/Users/fabia/OneDrive/Escritorio/pwmgr/cli.mjs get runpod-api-key
// Every call is appended to <project>/cost.json: {t, endpoint, usd (null when the endpoint doesn't report it), ms, note}
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const PWMGR = process.env.PWMGR_CLI || "C:/Users/fabia/OneDrive/Escritorio/pwmgr/cli.mjs";
let _key;
const key = () => (_key ??= execFileSync(process.execPath, [PWMGR, "get", "runpod-api-key"], { encoding: "utf8" }).trim().replace(/^.*= */, ""));

export function logCost(dir, rec) {
  const f = join(dir, "cost.json");
  const all = existsSync(f) ? JSON.parse(readFileSync(f, "utf8")) : [];
  all.push({ t: new Date().toISOString(), ...rec });
  writeFileSync(f, JSON.stringify(all, null, 1));
}
export const totalUsd = (dir) => {
  const f = join(dir, "cost.json");
  return existsSync(f) ? JSON.parse(readFileSync(f, "utf8")).reduce((s, r) => s + (r.usd || 0), 0) : 0;
};

/** runsync with polling fallback. Returns the final job object ({status, output, executionTime, ...}). */
export async function run(endpoint, input, { wait = 60000, dir, note = "" } = {}) {
  const H = { Authorization: "Bearer " + key(), "Content-Type": "application/json" };
  const r = await fetch(`https://api.runpod.ai/v2/${endpoint}/runsync?wait=${wait}`, { method: "POST", headers: H, body: JSON.stringify({ input }) });
  let j = await r.json();
  for (let i = 0; i < 60 && (j.status === "IN_QUEUE" || j.status === "IN_PROGRESS"); i++) {
    await new Promise((s) => setTimeout(s, 3000));
    j = await (await fetch(`https://api.runpod.ai/v2/${endpoint}/status/${j.id}`, { headers: H })).json();
  }
  if (dir) logCost(dir, { endpoint, status: j.status, usd: j.output?.cost ?? null, ms: j.executionTime ?? null, note });
  return j;
}
