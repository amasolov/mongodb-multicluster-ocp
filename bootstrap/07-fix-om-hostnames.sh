#!/usr/bin/env bash
set -euo pipefail
#
# Fix the Ops Manager automation config to use external DNS hostnames
# instead of cluster-local service names. This is needed because MCK 1.8.0
# pushes svc.cluster.local hostnames to the automation config even when
# externalDomain is set in the CR.
#
# This script reads the current automation config, replaces the internal
# hostnames with external ones derived from the hostname-override ConfigMap,
# and pushes the updated config back.
#
# Requires: kubectl, curl, python3
# Environment: KUBECONFIG must point to the merged multicluster kubeconfig.

CENTRAL_CLUSTER="${CENTRAL_CLUSTER:-cluster1}"
MONGODB_NS="${MONGODB_NS:-mongodb-data}"
RS_NAME="${RS_NAME:-mongodb-rs}"

export KUBECONFIG="${KUBECONFIG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/multicluster.kubeconfig}"

PUBLIC_KEY=$(kubectl --context "$CENTRAL_CLUSTER" -n "$MONGODB_NS" \
  get secret ops-manager-api-key -o jsonpath='{.data.publicKey}' | base64 -d)
PRIVATE_KEY=$(kubectl --context "$CENTRAL_CLUSTER" -n "$MONGODB_NS" \
  get secret ops-manager-api-key -o jsonpath='{.data.privateKey}' | base64 -d)

OM_URL=$(kubectl --context "$CENTRAL_CLUSTER" -n "$MONGODB_NS" \
  get configmap ops-manager-connection -o jsonpath='{.data.baseUrl}')

PROJECT_ID=$(kubectl --context "$CENTRAL_CLUSTER" -n "$MONGODB_NS" \
  get configmap ops-manager-connection -o jsonpath='{.data.orgId}')

echo "Ops Manager URL: ${OM_URL}"
echo "Project ID: ${PROJECT_ID}"

HOSTNAME_MAP=""
for ctx in cluster1 cluster2 cluster3; do
  CM=$(kubectl --context "$ctx" -n "$MONGODB_NS" \
    get configmap "${RS_NAME}-hostname-override" -o json 2>/dev/null || echo '{"data":{}}')
  HOSTNAME_MAP="${HOSTNAME_MAP}$(echo "$CM" | python3 -c "
import json, sys
data = json.load(sys.stdin).get('data', {})
for pod, fqdn in data.items():
    print(f'{pod}-svc.{\"$MONGODB_NS\"}.svc.cluster.local={fqdn}')
" 2>/dev/null)"
  HOSTNAME_MAP="${HOSTNAME_MAP}
"
done

if [ -z "$(echo "$HOSTNAME_MAP" | tr -d '[:space:]')" ]; then
  echo "No hostname overrides found. Is the MongoDBMultiCluster CR deployed?"
  exit 1
fi

echo "Hostname mappings:"
echo "$HOSTNAME_MAP" | grep -v '^$'

TMP_CONFIG=$(mktemp)
trap 'rm -f "$TMP_CONFIG"' EXIT

curl -s --digest -u "$PUBLIC_KEY:$PRIVATE_KEY" \
  "$OM_URL/api/public/v1.0/groups/$PROJECT_ID/automationConfig" > "$TMP_CONFIG"

python3 - "$TMP_CONFIG" "$HOSTNAME_MAP" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
mappings_raw = sys.argv[2]

hostname_map = {}
for line in mappings_raw.strip().split('\n'):
    if '=' in line:
        old, new = line.strip().split('=', 1)
        hostname_map[old] = new

with open(config_file) as f:
    data = json.load(f)

changed = 0
for process in data.get('processes', []):
    old_host = process.get('hostname', '')
    if old_host in hostname_map:
        process['hostname'] = hostname_map[old_host]
        changed += 1

with open(config_file, 'w') as f:
    json.dump(data, f)

print(f"Updated {changed} process hostname(s)")
PYEOF

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --digest -u "$PUBLIC_KEY:$PRIVATE_KEY" \
  -H "Content-Type: application/json" -X PUT \
  "$OM_URL/api/public/v1.0/groups/$PROJECT_ID/automationConfig" \
  -d @"$TMP_CONFIG")

if [ "$HTTP_CODE" = "200" ]; then
  echo "Automation config updated successfully."
else
  echo "ERROR: Ops Manager returned HTTP ${HTTP_CODE}"
  exit 1
fi
