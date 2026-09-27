#!/usr/bin/env bash
# Records REAL responses from a running onboarding-platform (+ Keycloak) into
# test/fixtures/stac/: the Stac manifest (POST /cases/flow-manifest/stac, the
# app's only manifest route; with no case_id it creates a case) and the live
# district options per seeded region. The offline scenario tests (make ci)
# replay these; the live tests (test/live/) hit the backend directly. Re-run
# after any backend seed/serializer change. Needs: backend on :8000, Keycloak
# on :8080, the seeded agent/client/workflow from NOTES.md's Phase 5 plus the
# seeds in tool/*.sql.
#
# It no longer calls the legacy POST /cases/flow-manifest. test/fixtures/stac/
# manifest_legacy.json is a FROZEN recording of that route, kept only as the reference the
# Stac -> flow-stage mapper is checked against (test/features/flow/data/stac_manifest_mapper_test.dart).
# This script does not re-record it; it was re-recorded by hand once, after
# tool/seed_stac_business_docs.sql and tool/seed_stac_liveness.sql added stages, so it covers the same stages as manifest_stac.json.
set -euo pipefail
BACKEND=${BACKEND:-http://127.0.0.1:8000}
KEYCLOAK=${KEYCLOAK:-http://127.0.0.1:8080}
AGENT_USER=${AGENT_USER:-tagent}
AGENT_PASS=${AGENT_PASS:-test#123}
CLIENT_ID=${CLIENT_ID:-e8ce7cac-22fb-4858-8328-bd62297c7e75}
WORKFLOW_ID=${WORKFLOW_ID:-340f410e-9493-4e02-a2c9-1acfc9a58372}
OUT="$(cd "$(dirname "$0")/.." && pwd)/test/fixtures/stac"
mkdir -p "$OUT"

TOKEN=$(curl -sf -X POST "$KEYCLOAK/realms/onboarding/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=onboarding-platform \
  --data-urlencode "username=$AGENT_USER" --data-urlencode "password=$AGENT_PASS" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

post() { curl -sf -X POST "$BACKEND$1" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$2"; }

STAC=$(post /cases/flow-manifest/stac "{\"client_id\":\"$CLIENT_ID\",\"workflow_id\":\"$WORKFLOW_ID\",\"case_id\":null}")
CASE_ID=$(echo "$STAC" | python3 -c 'import sys,json;print(json.load(sys.stdin)["case_id"])')

echo "$STAC" | python3 -m json.tool > "$OUT/manifest_stac.json"

# Live options for the cascading district field, for each seeded region.
python3 - "$BACKEND" "$TOKEN" "$CLIENT_ID" "$WORKFLOW_ID" "$OUT" <<'PY'
import json, sys, urllib.request, urllib.parse
backend, token, client, workflow, out = sys.argv[1:6]
stac = json.load(open(f"{out}/manifest_stac.json"))
def find(node, key):
    if isinstance(node, dict):
        if node.get("id") == key and node.get("type", "").startswith("kneth_"): return node
        for v in node.values():
            r = find(v, key)
            if r: return r
    elif isinstance(node, list):
        for v in node:
            r = find(v, key)
            if r: return r
region = find(stac, "region")
options = {}
for o in region["options"]:
    q = urllib.parse.urlencode({"region": o["value"]})
    req = urllib.request.Request(
        f"{backend}/config/clients/{client}/workflows/{workflow}/fields/district/options?{q}",
        headers={"Authorization": f"Bearer {token}"})
    options[o["value"]] = json.load(urllib.request.urlopen(req))
json.dump(options, open(f"{out}/district_options_by_region_value.json", "w"), indent=2)
PY
echo "recorded case $CASE_ID into $OUT"
