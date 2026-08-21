#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export QUICKLOOK_PLUGIN_DIR="${QUICKLOOK_PLUGIN_DIR:-$ROOT}"
if command -v python3 >/dev/null 2>&1 && [ -f "$ROOT/compat/quicklookd.py" ]; then
  exec python3 "$ROOT/compat/quicklookd.py" "$@"
fi
oneshot=""
while [ $# -gt 0 ]; do
  case "$1" in
    --oneshot) oneshot=$2; shift 2 ;;
    --plugin-dir) shift 2 ;;
    *) shift ;;
  esac
done
home=${HOME:-/tmp}
req=${oneshot:-}
qid=1
q=""
if [ -n "$req" ]; then
  q=$(printf '%s' "$req" | sed -n 's/.*"q":"\([^"]*\)".*/\1/p')
  qid=$(printf '%s' "$req" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  qid=${qid:-1}
fi
qsafe=$(printf '%s' "$q" | tr -cd 'A-Za-z0-9._-')
if [ -z "$qsafe" ]; then
  printf '{"id":%s,"kind":"results","results":[],"backend":"posix","indexing":false,"progress":1}\n' "$qid"
  exit 0
fi
if command -v plocate >/dev/null 2>&1; then
  paths=$(plocate -il 40 -- "$qsafe" 2>/dev/null || true)
else
  paths=$(find "$home" -iname "*${qsafe}*" \( -name .git -o -name node_modules -o -name .cache \) -prune -o -print 2>/dev/null | head -n 40)
fi
printf '{"id":%s,"kind":"results","results":[' "$qid"
sep=""
printf '%s\n' "$paths" | while IFS= read -r p; do
  [ -n "$p" ] || continue
  name=$(basename -- "$p")
  p=$(printf '%s' "$p" | sed 's/\\/\\\\/g; s/"/\\"/g')
  name=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '%s{"path":"%s","name":"%s","kind":"hex","score":100,"mtime":0,"size":0}' "$sep" "$p" "$name"
  sep=","
done
printf '],"backend":"posix","indexing":false,"progress":1}\n'
