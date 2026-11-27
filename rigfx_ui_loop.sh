#!/bin/bash
# rigfx UI/UX humanizer — FULLY AUTONOMOUS. pi makes ONE tasteful improvement to
# site/index.html, pushes straight to main and redeploys live. Uses env GITHUB_TOKEN, COOLIFY_TOKEN.
set -e
REPO=/home/node/.n8n/rigfx-work
APP_UUID=dwsxygvv4inbdfodvfnsn1zm
cd "$REPO"
AUTH="https://x-access-token:${GITHUB_TOKEN}@github.com/balmacefa/rigfx.git"

echo "== sync main =="
git fetch -q "$AUTH" main
git checkout -q -B main FETCH_HEAD
cp site/index.html /tmp/index.before.html

echo "== ask pi for one UI/UX improvement =="
PROMPT='You are a senior UI/UX designer and front-end engineer working in this git repo for rigfx (a landing page for an open-source 2D animation rig).
Make ONE concrete, tasteful improvement to site/index.html that HUMANIZES the UI/UX: warmer/clearer copy tone, better visual hierarchy and spacing, accessibility (aria, contrast, focus states), a subtle tasteful micro-interaction, or better mobile layout. Edit the file IN PLACE (use your file tools).
HARD CONSTRAINTS: keep it a single self-contained file; DO NOT break or remove the inline <script> that fetches media/index.json and media/chars.json and renders #grid and #moves; do NOT touch any file under site/media/ or any .json; no external build steps or dependencies. Make a SMALL, focused change, not a rewrite. End by stating the one change you made.'
cd "$REPO" && pi -p "$PROMPT" </dev/null 2>/dev/null | tail -4

# safety: the data-loading contract must survive, else revert and bail
if ! grep -q "media/index.json" site/index.html || ! grep -q "media/chars.json" site/index.html || ! grep -q "grid" site/index.html; then
  echo "VALIDATION FAILED -> revert, no push"; cp /tmp/index.before.html site/index.html; exit 1
fi
if git diff --quiet -- site/index.html; then echo "no UI change this run"; exit 0; fi

git add site/index.html
git -c user.name=balmacefa -c user.email=8296124+balmacefa@users.noreply.github.com commit -q -m "ui: humanize UI/UX (auto via n8n+pi)"
git push -q "$AUTH" HEAD:main
echo "== pushed to main =="

GW=$(ip route | awk '/default/{print $3}' | head -1)
curl -s -X POST -o /dev/null -w 'coolify deploy HTTP %{http_code}\n' \
  -H "Authorization: Bearer ${COOLIFY_TOKEN}" \
  "http://${GW}:8000/api/v1/deploy?uuid=${APP_UUID}&force=false"
echo "== done (live) =="
