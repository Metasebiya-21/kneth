#!/usr/bin/env bash
# DEV/TEST SEED ONLY -- never run against a shared, staging or production environment.
# Creates a second dev identity that is a Keycloak PLATFORM ADMIN (realm role `platform_admin`), with a
# linked identity.agents row (the token validator resolves every caller to an agent), so live tests can
# call the platform-admin routes (grant / change / revoke an assignment, read the audit log) as someone
# OTHER than the seeded dev agent they act on. It has NO client assignment: platform-wide operations
# need none, and `AssignmentRole.admin` is a different, per-client thing.
#   username: dev-platform-admin   password: dev-platform-admin-password-123
# Idempotent. Needs Keycloak on :8080 and the `postgres` docker container.
set -euo pipefail
KEYCLOAK=${KEYCLOAK:-http://127.0.0.1:8080}
REALM=onboarding
COMPOSE="$(cd "$(dirname "$0")/../../../backend/onboarding-platform" && pwd)/docker-compose-keycloak.yml"
ADMIN_PW=${KEYCLOAK_ADMIN_PASSWORD:-$(grep KEYCLOAK_ADMIN_PASSWORD "$COMPOSE" | head -1 | awk '{print $2}')}
USERNAME=dev-platform-admin
PASSWORD=dev-platform-admin-password-123
AGENT_ID=5c1a7d2e-0b6a-4e57-9a11-7f0d0e5a0001

TOKEN=$(curl -sf -X POST "$KEYCLOAK/realms/master/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode "password=$ADMIN_PW" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
api() { curl -sf -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$@"; }

# realm role
api "$KEYCLOAK/admin/realms/$REALM/roles/platform_admin" >/dev/null 2>&1 || \
  api -X POST "$KEYCLOAK/admin/realms/$REALM/roles" -d '{"name":"platform_admin"}' >/dev/null

# user
UID_KC=$(api "$KEYCLOAK/admin/realms/$REALM/users?username=$USERNAME&exact=true" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["id"] if d else "")')
if [ -z "$UID_KC" ]; then
  api -X POST "$KEYCLOAK/admin/realms/$REALM/users" -d "{\"username\":\"$USERNAME\",\"enabled\":true,\"emailVerified\":true,\"credentials\":[{\"type\":\"password\",\"value\":\"$PASSWORD\",\"temporary\":false}]}" >/dev/null
  UID_KC=$(api "$KEYCLOAK/admin/realms/$REALM/users?username=$USERNAME&exact=true" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
fi
for ROLE in agent platform_admin; do
  BODY=$(api "$KEYCLOAK/admin/realms/$REALM/roles/$ROLE")
  api -X POST "$KEYCLOAK/admin/realms/$REALM/users/$UID_KC/role-mappings/realm" -d "[$BODY]" >/dev/null
done

# linked agent row (an agent-type identity record on an existing case, plus identity.agents)
docker exec postgres psql -U onboarding -d onboarding -v ON_ERROR_STOP=1 -q -c "
INSERT INTO identity.records(id, case_id, golden_id, record_type, full_name, created_at)
SELECT '$AGENT_ID', case_id, NULL, 'agent', 'Dev Platform Admin', now() FROM identity.records WHERE record_type='agent' LIMIT 1
ON CONFLICT (id) DO NOTHING;
INSERT INTO identity.agents(id, employee_id, keycloak_user_id) VALUES ('$AGENT_ID', 'EMP-DEV-ADMIN', '$UID_KC')
ON CONFLICT (id) DO UPDATE SET keycloak_user_id = EXCLUDED.keycloak_user_id;"
echo "dev platform admin ready: $USERNAME (agent $AGENT_ID, keycloak $UID_KC)"
