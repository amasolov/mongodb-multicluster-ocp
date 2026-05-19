#!/usr/bin/env bash
set -euo pipefail
#
# Grant the anyuid SCC to all MongoDB ServiceAccounts on all clusters.
# Required because MongoDB containers run as non-root with specific UIDs
# that conflict with OpenShift's restricted SCC.
#
# Requires: oc CLI
# Environment: KUBECONFIG must point to the merged multicluster kubeconfig.

export KUBECONFIG="${KUBECONFIG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/multicluster.kubeconfig}"

SERVICE_ACCOUNTS=(
  mongodb-kubernetes-operator-multi-cluster
  mongodb-kubernetes-database-pods
  mongodb-kubernetes-appdb
  mongodb-kubernetes-ops-manager
)
NAMESPACES=(mongodb-operator mongodb-ops-manager mongodb-data)

for ctx in cluster1 cluster2 cluster3; do
  echo "Granting anyuid SCC on ${ctx}..."
  for sa in "${SERVICE_ACCOUNTS[@]}"; do
    for ns in "${NAMESPACES[@]}"; do
      oc --context "$ctx" adm policy add-scc-to-user anyuid \
        -z "$sa" -n "$ns" 2>/dev/null || true
    done
  done
done

echo "SCC grants complete."
