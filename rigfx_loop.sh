#!/bin/bash
# rigfx autogen loop (runs INSIDE the n8n container). pi -> new char -> render ->
# GIFs -> commit+push to balmacefa/rigfx -> redeploy Coolify. Uses env GITHUB_TOKEN, COOLIFY_TOKEN.
set -e
REPO=/home/node/.n8n/rigfx-work
APP_UUID=dwsxygvv4inbdfodvfnsn1zm
export PYTHONPATH="$REPO/pylibs"
cd "$REPO"
# self-heal Pillow into the volume (survives redeploys) if missing
python3 -c 'import PIL' 2>/dev/null || pip install --break-system-packages --target="$REPO/pylibs" Pillow >/dev/null 2>&1
git pull -q "https://x-access-token:${GITHUB_TOKEN}@github.com/balmacefa/rigfx.git" main || true

EXIST=$(ls chars2d/*.json 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/.json//' | paste -sd, -)
PROMPT="You are a pixel-art art director for the open-source project rigfx. Design ONE brand-new character, distinct from these existing ones: ${EXIST}. Output ONLY ONE single line, exactly starting with 'node tools/new-character.mjs', with: <name lowercase letters only> --legS <n> --torsoS <n> --armS <n> --headS <n> --neckS <n> --widthS <n> --thick <n> (each multiplier 0.6-1.8) --head <comma-separated from: helmet,visor,horns,wizardhat,hood,ears,mohawk,tusks,antenna,bighair,crown> --gear <comma-separated from: pauldrons,cape,belt,backpack,tail> --color #RRGGBB --core #RRGGBB . No prose, no backticks."
RES=$(cd /tmp && pi -p "$PROMPT" </dev/null 2>/dev/null)
CMD=$(printf '%s\n' "$RES" | grep -m1 '^node tools/new-character.mjs' || true)
[ -z "$CMD" ] && { echo "no CMD from pi; got: $RES"; exit 1; }
NAME=$(printf '%s' "$CMD" | awk '{print $3}')
echo "== new character: $NAME =="

eval "$CMD --force"
PIXELFX_DIR="$REPO/pixelfx" node retarget.mjs --chars "$NAME"
python3 scripts/make_media.py --only "$NAME"

git add -A
if git diff --cached --quiet; then echo "no changes, skipping"; exit 0; fi
git -c user.name=balmacefa -c user.email=8296124+balmacefa@users.noreply.github.com commit -q -m "rigfx: add character $NAME (auto via n8n+pi)"
git push -q "https://x-access-token:${GITHUB_TOKEN}@github.com/balmacefa/rigfx.git" HEAD:main
echo "== pushed $NAME =="

# Coolify API is behind Cloudflare Access on its public host, but reachable on
# the internal docker gateway; use that so the container can trigger a redeploy.
GW=$(ip route | awk '/default/{print $3}' | head -1)
curl -s -X POST -o /dev/null -w 'coolify deploy HTTP %{http_code}\n' \
  -H "Authorization: Bearer ${COOLIFY_TOKEN}" \
  "http://${GW}:8000/api/v1/deploy?uuid=${APP_UUID}&force=false"
echo "== done $NAME =="
