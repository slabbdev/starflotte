#!/usr/bin/env bash
# One fleet scout. Two mission modes:
#   legacy: work/targets.txt URL list — navigate + extract markdown
#   task:   work/task-$SCOUT.json (parsed from the issue's json block) —
#           navigate, run navette steps as {"route":{payload}} objects, then
#           run the task's extract JS and report the result
set -uo pipefail

BASE="${NAVETTE_URL:-http://127.0.0.1:8765}"
SCOUT="${SCOUT:?SCOUT env var required}"
URL="${URL:?URL env var required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p work

status="ERROR"; title=""; final_url=""; bytes=0; note=""; name=""; extract=""

post() { curl -s -m 120 -X POST "$BASE/$1" -H 'Content-Type: application/json' -d "$2"; }

classify() { # WALL detection over work/probe-scout-$SCOUT.txt
  local wall=0
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    if grep -qiF -- "$pat" "work/probe-scout-$SCOUT.txt"; then wall=1; break; fi
  done < "$ROOT/scripts/wall-patterns.txt"
  if [ "$wall" = "1" ]; then echo WALL; else echo OK; fi
}

task_file=""
if [ -n "${TASK:-}" ] && [ -f "work/task-$SCOUT.json" ]; then task_file="work/task-$SCOUT.json"; fi

if [ -n "$task_file" ]; then
  name=$(jq -r '.name // ""' "$task_file")
  task_url=$(jq -r '.url // empty' "$task_file")
  [ -n "$task_url" ] && URL="$task_url"

  resp=$(post navigate "$(jq -n --arg u "$URL" '{url:$u}')")
  if jq -e '.ok == true' >/dev/null 2>&1 <<<"$resp"; then
    title=$(jq -r '.title // ""' <<<"$resp")
    final_url=$(jq -r '.url // ""' <<<"$resp")
    sleep 2
    steps_ok=1
    n=$(jq '.steps // [] | length' "$task_file")
    i=0
    while [ "$i" -lt "$n" ]; do
      route=$(jq -r --argjson i "$i" '.steps[$i] | keys[0]' "$task_file")
      # pseudo-route: /wait is selector-only on this build, so timed pauses
      # are plain sleeps, capped at 30 s
      if [ "$route" = "sleep" ]; then
        ms=$(jq -r --argjson i "$i" '.steps[$i].sleep.ms // 1000' "$task_file")
        [ "$ms" -gt 30000 ] && ms=30000
        sleep $(( ms / 1000 ))
        i=$((i+1))
        continue
      fi
      payload=$(jq -c --argjson i "$i" --arg r "$route" '.steps[$i][$r]' "$task_file")
      resp=$(post "$route" "$payload")
      if ! jq -e '.ok == true' >/dev/null 2>&1 <<<"$resp"; then
        steps_ok=0; status="ERROR"
        detail=$(jq -r '.error // ""' <<<"$resp" 2>/dev/null)
        note="step $i ($route) failed${detail:+: $detail}"
        break
      fi
      i=$((i+1))
    done
    if [ "$steps_ok" = "1" ]; then
      extract_js=$(jq -r '.extract // ""' "$task_file")
      if [ -n "$extract_js" ]; then
        resp=$(post evaluate "$(jq -n --arg js "$extract_js" '{js:$js}')")
        extract=$(jq -r '.result // ""' <<<"$resp" | head -c 2000)
      fi
      { printf '%s\n' "$title"; printf '%s' "$extract"; } > "work/probe-scout-$SCOUT.txt"
      status=$(classify)
      bytes=${#extract}
      sleep 1
      curl -s -m 60 -X POST "$BASE/screenshot" -o "work/scout-$SCOUT.png"
    fi
  else
    note="navigate failed"
  fi

  jq -n --arg scout "$SCOUT" --arg name "$name" --arg target "$URL" --arg status "$status" \
    --arg title "$title" --arg final "$final_url" --argjson bytes "$bytes" --arg note "$note" \
    --arg extract "$extract" \
    '{scout:$scout,name:$name,target:$target,status:$status,title:$title,final_url:$final,bytes:$bytes,note:$note,extract:$extract}' \
    > "work/result-$SCOUT.json"
  cat "work/result-$SCOUT.json"
  exit 0
fi

# legacy mode: plain URL list
resp=$(post navigate "$(jq -n --arg u "$URL" '{url:$u,with_content:true,format:"markdown"}')")
if jq -e '.ok == true' >/dev/null 2>&1 <<<"$resp"; then
  final_url=$(jq -r '.url // ""' <<<"$resp")
  title=$(jq -r '.title // ""' <<<"$resp")
  jq -r '.content // ""' <<<"$resp" > "work/page-scout-$SCOUT.md"
  bytes=$(wc -c < "work/page-scout-$SCOUT.md" | tr -d ' ')
  head -c 4000 "work/page-scout-$SCOUT.md" > "work/head-scout-$SCOUT.txt"
  { printf '%s\n' "$title"; cat "work/head-scout-$SCOUT.txt"; } > "work/probe-scout-$SCOUT.txt"
  status=$(classify)
  sleep 2
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
