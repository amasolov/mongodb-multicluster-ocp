#!/usr/bin/env bash
set -euo pipefail
#
# Copy MongoDB CRDs from the central cluster to member clusters.
# The kubectl mongodb multicluster setup command does not install CRDs
# on member clusters, which are needed for the operator to manage
# cross-cluster resources.
#
# Requires: kubectl
# Environment: KUBECONFIG must point to the merged multicluster kubeconfig.

CENTRAL_CLUSTER="${CENTRAL_CLUSTER:-cluster1}"

export KUBECONFIG="${KUBECONFIG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/multicluster.kubeconfig}"

CRDS=(
  mongodb.mongodb.com
  mongodbmulticluster.mongodb.com
  opsmanagers.mongodb.com
  mongodbusers.mongodb.com
  mongodbcommunity.mongodbcommunity.mongodb.com
)

for crd in "${CRDS[@]}"; do
  echo "Copying CRD: ${crd}"
  CRD_YAML=$(kubectl --context "$CENTRAL_CLUSTER" get crd "$crd" -o yaml \
    | grep -v 'resourceVersion\|uid\|creationTimestamp\|selfLink')

  for ctx in cluster2 cluster3; do
    echo "$CRD_YAML" | kubectl --context "$ctx" apply -f - 2>/dev/null || true
  done
done

echo "CRD installation on member clusters complete."
