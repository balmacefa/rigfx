#!/usr/bin/env bash
# Publish the rigfx repo: GIFs -> sprite sheets -> git commit -> push. DRY BY DEFAULT: without --yes it only prints the plan.
#   bash tools/publish.sh                 show what would happen
#   bash tools/publish.sh --yes -m "rigfx v0.3: 3 new characters"
# One push per repo: make sure no other Claude session is writing here (ListAgents) before using --yes.
set -euo pipefail
cd "$(dirname "$0")/.."
YES=0; MSG="rigfx: update characters, animations and media"
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    -m) shift; MSG="$1" ;;
    *) echo "unknown arg $1"; exit 2 ;;
  esac; shift
done
PY=${PYTHON:-python}
run() { if [ "$YES" = 1 ]; then echo "+ $*"; "$@"; else echo "[dry] $*"; fi; }

echo "== 1. GIFs for the site (anim/retarget -> site/media)"
if [ ! -d anim/retarget ]; then echo "anim/retarget missing: run  PIXELFX_DIR=<patched pixelfx> node retarget.mjs  first"; [ "$YES" = 1 ] && exit 1; fi
run "$PY" scripts/make_media.py

echo "== 2. sprite sheets (dist/sheets + dist/rigfx-sheets.zip, not committed; attach the zip to a GitHub release)"
if [ -f tools/export_sheets.py ]; then run "$PY" tools/export_sheets.py --src "$(pwd -W 2>/dev/null || pwd)/anim/retarget"; else echo "(tools/export_sheets.py not present, skipped)"; fi

echo "== 3. git"
git status --short | head -20
run git add -A
run git -c user.name=balmacefa -c user.email=8296124+balmacefa@users.noreply.github.com commit -m "$MSG

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
run git push origin main

cat <<'EOF'

== 4. after the push (these are NOT run by this script)
 a) GitHub Pages updates by itself (workflow "pages", ~1 min).
 b) Coolify subdomain https://rigfx.balmacefa.com needs a redeploy:
      wsl bash -c "cd /mnt/c/Users/fabia/OneDrive/Escritorio/ansible_coolify && ansible-playbook -i inventory.ini playbooks/services/deploy_rigfx_website.yml -e dry_run=false"
 c) Landing balmacefa.com (repo consulting-website, push to main = deploy, takes 5-8 min and answers 503 meanwhile):
      update the card in src/content/home/{en,es}.json and the posts src/content/blog/rigfx-*.md (character/animation counts, video),
      `npm run build`, commit only those files, push. Serve the mp4 from https://balmacefa.github.io/rigfx/media/... (Coolify gives no 206 -> iOS).
 d) Verify: curl -s -o /dev/null -w '%{http_code}' https://rigfx.balmacefa.com/ ; curl -s -r 0-99 -o /dev/null -w '%{http_code}' <mp4 url>   (expect 200 and 206)
EOF
