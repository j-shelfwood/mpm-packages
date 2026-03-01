#!/usr/bin/env bash
set -euo pipefail

# Patch the "Machine Activity Grid" cell view so Mosaic has the required
# columns for rendering (fillColumns + xColumn). Some template applies reset
# these to null/empty in InfluxDB 2.x.
#
# Usage:
#   ./influx-collector/fix-mosaic-view.sh <token> [host] [dashboard_id]
#
# Defaults:
#   host         = https://influx.shelfwood.co
#   dashboard_id = 105583c23aef5000

TOKEN="${1:-}"
HOST="${2:-https://influx.shelfwood.co}"
DASHBOARD_ID="${3:-105583c23aef5000}"

if [[ -z "$TOKEN" ]]; then
  echo "error: token required"
  echo "usage: $0 <token> [host] [dashboard_id]"
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

curl -sS \
  -H "Authorization: Token $TOKEN" \
  "$HOST/api/v2/dashboards/$DASHBOARD_ID?include=properties" \
  > "$tmpdir/dashboard.json"

python3 - "$tmpdir/dashboard.json" "$tmpdir/cell_patch.json" <<'PY'
import json
import sys

dash = json.load(open(sys.argv[1]))
out = sys.argv[2]

cell = None
for c in dash.get("cells", []):
    name = c.get("name") or c.get("properties", {}).get("name")
    if name == "Machine Activity Grid":
        cell = c
        break

if not cell:
    raise SystemExit("Machine Activity Grid cell not found")

json.dump({"cell_id": cell["id"]}, open(out, "w"))
print(cell["id"])
PY

CELL_ID="$(python3 - <<'PY' "$tmpdir/cell_patch.json"
import json,sys
print(json.load(open(sys.argv[1]))["cell_id"])
PY
)"

curl -sS \
  -H "Authorization: Token $TOKEN" \
  "$HOST/api/v2/dashboards/$DASHBOARD_ID/cells/$CELL_ID/view" \
  > "$tmpdir/view_body.json"

python3 - "$tmpdir/view_body.json" <<'PY'
import json,sys
obj=json.load(open(sys.argv[1]))
props=obj.get("properties", {})
props["fillColumns"]=["_value"]
props["xColumn"]="_time"
props["ySeriesColumns"]=props.get("ySeriesColumns") or ["mod","type","node"]
props["yLabelColumns"]=props.get("yLabelColumns") or ["mod","type","node"]
props["yLabelColumnSeparator"]=props.get("yLabelColumnSeparator") or " / "
obj["properties"]=props
json.dump(obj, open(sys.argv[1], "w"))
PY

status="$(curl -sS -o "$tmpdir/resp.json" -w "%{http_code}" \
  -X PATCH \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  "$HOST/api/v2/dashboards/$DASHBOARD_ID/cells/$CELL_ID/view" \
  --data-binary @"$tmpdir/view_body.json")"

python3 - <<'PY' "$status" "$tmpdir/resp.json"
import json,sys
status=sys.argv[1]
resp=json.load(open(sys.argv[2]))
props=resp.get("properties",{})
print("http_status:", status)
print("fillColumns:", props.get("fillColumns"))
print("xColumn:", props.get("xColumn"))
print("ySeriesColumns:", props.get("ySeriesColumns"))
PY
