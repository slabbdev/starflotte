#!/usr/bin/env bash
# One fleet scout: drive the local navette daemon against the scout's target,
# write result-$SCOUT.json (machine summary) + screenshot + page extract.
set -uo pipefail

BASE="${NAVETTE_URL:-http://127.0.0.1:8765}"
SCOUT="${SCOUT:?SCOUT env var required}"
URL="${URL:?URL env var required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p work

status="ERROR"; title=""; final_url=""; bytes=0; note=""

post() { curl -s -m 120 -X POST "$BASE/$1" -H 'Content-Type: application/json' -d "$2"; }

resp=$(post navigate "$(jq -n --arg u "$URL" '{url:$u,with_content:true,format:"markdown"}')")
if jq -e '.ok == true' >/dev/null 2>&1 <<<"$resp"; then
  final_url=$(jq -r '.url // ""' <<<"$resp")
  title=$(jq -r '.title // ""' <<<"$resp")
  jq -r '.content // ""' <<<"$resp" > "work/page-scout-$SCOUT.md"
  bytes=$(wc -c < "work/page-scout-$SCOUT.md" | tr -d ' ')
  head -c 4000 "work/page-scout-$SCOUT.md" > "work/head-scout-$SCOUT.txt"
  { printf '%s\n' "$title"; cat "work/head-scout-$SCOUT.txt"; } > "work/probe-scout-$SCOUT.txt"
  wall=0
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    if grep -qiF -- "$pat" "work/probe-scout-$SCOUT.txt"; then wall=1; break; fi
  done < "$ROOT/scripts/wall-patterns.txt"
  if [ "$wall" = "1" ]; then
    status="WALL"
    note="anti-bot page detected"
  else
    status="OK"
  fi
  post wait '{"ms":2000}' >/dev/null
  curl -s -m 60 -X POST "$BASE/screenshot" -o "work/scout-$SCOUT.png"
else
  note=$(jq -r '.error // "navigate failed"' <<<"$resp" 2>/dev/null) || note="navigate failed"
  if [ -z "$note" ] || [ "$note" = "null" ]; then note="navigate failed"; fi
fi

jq -n --arg scout "$SCOUT" --arg target "$URL" --arg status "$status" \
  --arg title "$title" --arg final "$final_url" --argjson bytes "${bytes:-0}" --arg note "$note" \
  '{scout:$scout,target:$target,status:$status,title:$title,final_url:$final,bytes:$bytes,note:$note}' \
  > "work/result-$SCOUT.json"
cat "work/result-$SCOUT.json"
