#!/usr/bin/env bash
set -euo pipefail
#
# Install the MCK multi-cluster operator via Helm on the central cluster.
# The multi-cluster variant is only available via the Helm chart, not OLM.
#
# Requires: helm, kubectl
# Environment: KUBECONFIG must point to the merged multicluster kubeconfig.

CENTRAL_CLUSTER="${CENTRAL_CLUSTER:-cluster1}"
OPERATOR_NS="${OPERATOR_NS:-mongodb-operator}"
MCK_VERSION="${MCK_VERSION:-1.8.0}"

export KUBECONFIG="${KUBECONFIG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/multicluster.kubeconfig}"

echo "Adding MongoDB Helm repo..."
helm repo add mongodb https://mongodb.github.io/helm-charts 2>/dev/null || true
helm repo update mongodb

echo "Creating operator namespace..."
kubectl --context "$CENTRAL_CLUSTER" create namespace "$OPERATOR_NS" --dry-run=client -o yaml \
  | kubectl --context "$CENTRAL_CLUSTER" apply -f -

echo "Installing MCK operator ${MCK_VERSION} on ${CENTRAL_CLUSTER}..."
helm upgrade --install mongodb-kubernetes-operator-multi-cluster mongodb/mongodb-kubernetes \
  --version "$MCK_VERSION" \
  --namespace "$OPERATOR_NS" \
  --set operator.name=mongodb-kubernetes-operator-multi-cluster \
  --set operator.createOperatorServiceAccount=false \
  --set operator.createResourcesServiceAccountsAndRoles=false \
  --set "multiCluster.clusters={cluster1,cluster2,cluster3}" \
  --set "operator.watchNamespace=mongodb-ops-manager\,mongodb-data" \
  --set operator.resources.requests.cpu=100m \
  --set operator.resources.requests.memory=200Mi \
  --kube-context "$CENTRAL_CLUSTER"

echo "Waiting for operator deployment..."
kubectl --context "$CENTRAL_CLUSTER" -n "$OPERATOR_NS" \
  rollout status deployment/mongodb-kubernetes-operator-multi-cluster --timeout=120s

echo "MCK operator installed successfully."
