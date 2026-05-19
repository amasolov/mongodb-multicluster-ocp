#!/usr/bin/env bash
set -euo pipefail
#
# Run kubectl mongodb multicluster setup to create ServiceAccounts, Roles,
# RoleBindings, and kubeconfig secrets across all member clusters.
#
# Requires: kubectl, kubectl-mongodb plugin
# Environment: KUBECONFIG must point to the merged multicluster kubeconfig.

CENTRAL_CLUSTER="${CENTRAL_CLUSTER:-cluster1}"
OPERATOR_NS="${OPERATOR_NS:-mongodb-operator}"

export KUBECONFIG="${KUBECONFIG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/multicluster.kubeconfig}"

for NS in mongodb-data mongodb-ops-manager; do
  echo "Setting up multi-cluster RBAC for namespace: ${NS}..."
  kubectl mongodb multicluster setup \
    --central-cluster="$CENTRAL_CLUSTER" \
    --member-clusters=cluster1,cluster2,cluster3 \
    --member-cluster-namespace="$NS" \
    --central-cluster-namespace="$OPERATOR_NS" \
    --create-service-account-secrets \
    --install-database-roles=true
done

echo "Multi-cluster RBAC setup complete."
