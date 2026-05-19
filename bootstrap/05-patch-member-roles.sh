#!/usr/bin/env bash
set -euo pipefail
#
# Patch the operator Role on member clusters to include mongodb.com API group
# permissions. The kubectl mongodb multicluster setup command does not grant
# these, causing blockOwnerDeletion errors on MongoDBMultiCluster resources.
#
# Requires: kubectl
# Environment: KUBECONFIG must point to the merged multicluster kubeconfig.

export KUBECONFIG="${KUBECONFIG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/multicluster.kubeconfig}"

PATCH='[{"op":"add","path":"/rules/-","value":{
  "apiGroups":["mongodb.com"],
  "resources":["mongodbmulticluster","mongodbmulticluster/finalizers","mongodbmulticluster/status",
               "mongodb","mongodb/finalizers","mongodb/status","opsmanagers","opsmanagers/finalizers",
               "opsmanagers/status","mongodbusers","mongodbusers/status","mongodbsearch",
               "mongodbsearch/finalizers","mongodbsearch/status"],
  "verbs":["*"]
}},{"op":"add","path":"/rules/-","value":{
  "apiGroups":["mongodbcommunity.mongodb.com"],
  "resources":["*"],
  "verbs":["*"]
}}]'

for ctx in cluster2 cluster3; do
  for ns in mongodb-data mongodb-ops-manager; do
    echo "Patching Role on ${ctx} in ${ns}..."
    kubectl --context "$ctx" -n "$ns" patch role mongodb-kubernetes-operator-multi-role \
      --type='json' -p="$PATCH" 2>/dev/null || echo "  (role not found yet, will be created by RBAC setup)"
  done
done

echo "Member cluster role patches complete."
