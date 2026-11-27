#!/bin/bash
# rigfx game grower — FULLY AUTONOMOUS. pi extends site/game.html (a browser game
# that reuses the generated character GIFs). ONE improvement per run -> push main -> deploy.
# Only touches site/game.html so it never conflicts with the character/UI crons.
set -e
REPO=/home/node/.n8n/rigfx-work
APP_UUID=dwsxygvv4inbdfodvfnsn1zm
cd "$REPO"
AUTH="https://x-access-token:${GITHUB_TOKEN}@github.com/balmacefa/rigfx.git"

echo "== sync main =="
git fetch -q "$AUTH" main
git checkout -q -B main FETCH_HEAD
[ -f site/game.html ] && cp site/game.html /tmp/game.before.html || echo "(no game yet)"

echo "== ask pi to grow the game =="
EXIST=$(ls site/media/chars.json >/dev/null 2>&1 && echo yes || echo no)
PROMPT='You are a game developer working in this git repo for rigfx. The file site/game.html is a single-file browser game ("rigfx arena") that reuses the pixel-art character animations in site/media/ (GIFs named <char>-<move>.gif; character list in site/media/chars.json; moves: sword-combo, fireball-throw, ice-lance-throw, lightning-call, meteor-call, ground-pound, rocket-launcher, holy-smite, dash-strike, earth-stomp, arrow-shot, pistol-shots).
Make ONE concrete improvement that makes the game MORE fun / interactive / interesting to explore: e.g. a new mechanic (combos, crit, blocking, items, special moves), better feel/juice (screen shake, hit flashes, particles via CSS/canvas), progression (levels, boss, leaderboard in localStorage), character picker, keyboard controls, sound via WebAudio, or polish. Edit site/game.html IN PLACE (use your file tools).
HARD CONSTRAINTS: keep it a SINGLE self-contained file (inline CSS/JS, no external deps/build); keep loading characters from media/chars.json and using media/<char>-<move>.gif so new auto-generated characters keep working; keep the back link to "/"; do NOT touch any other file. Make a focused, working change, not a full rewrite. End by stating the one change you made.'
cd "$REPO" && pi -p "$PROMPT" </dev/null 2>/dev/null | tail -4

# safety: must stay a working single file that still uses the roster
if ! grep -q "chars.json" site/game.html || ! grep -q "media/" site/game.html; then
  echo "VALIDATION FAILED -> revert, no push"; [ -f /tmp/game.before.html ] && cp /tmp/game.before.html site/game.html; exit 1
fi
if git diff --quiet -- site/game.html; then echo "no game change this run"; exit 0; fi

git add site/game.html
git -c user.name=balmacefa -c user.email=8296124+balmacefa@users.noreply.github.com commit -q -m "game: grow rigfx arena (auto via n8n+pi)"
git push -q "$AUTH" HEAD:main || { echo "push race, retry"; git fetch -q "$AUTH" main; git rebase -q FETCH_HEAD || git rebase --abort; git push -q "$AUTH" HEAD:main; }
echo "== pushed to main =="

GW=$(ip route | awk '/default/{print $3}' | head -1)
curl -s -X POST -o /dev/null -w 'coolify deploy HTTP %{http_code}\n' -H "Authorization: Bearer ${COOLIFY_TOKEN}" "http://${GW}:8000/api/v1/deploy?uuid=${APP_UUID}&force=false"
echo "== done (live) =="
