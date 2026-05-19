#!/usr/bin/env bash
set -euo pipefail
#
# Merge three cluster kubeconfigs into a single file with simplified context names.
# Requires: oc CLI
#
# Usage:
#   ./01-merge-kubeconfig.sh \
#     <cluster1-api> <cluster1-password> \
#     <cluster2-api> <cluster2-password> \
#     <cluster3-api> <cluster3-password>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT="${REPO_ROOT}/multicluster.kubeconfig"

if [[ $# -ne 6 ]]; then
  echo "Usage: $0 <api1> <pw1> <api2> <pw2> <api3> <pw3>"
  exit 1
fi

CLUSTERS=("cluster1" "cluster2" "cluster3")
APIS=("$1" "$3" "$5")
PASSWORDS=("$2" "$4" "$6")
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

for i in 0 1 2; do
  echo "Logging in to ${CLUSTERS[$i]} (${APIS[$i]})..."
  KUBECONFIG="${TMP_DIR}/kc${i}" oc login --insecure-skip-tls-verify \
    "${APIS[$i]}" -u kubeadmin -p "${PASSWORDS[$i]}" > /dev/null

  KUBECONFIG="${TMP_DIR}/kc${i}" kubectl config rename-context \
    "$(KUBECONFIG="${TMP_DIR}/kc${i}" kubectl config current-context)" \
    "${CLUSTERS[$i]}" 2>/dev/null || true
done

KUBECONFIG="${TMP_DIR}/kc0:${TMP_DIR}/kc1:${TMP_DIR}/kc2" \
  kubectl config view --flatten > "$OUTPUT"

echo "Merged kubeconfig written to: $OUTPUT"
echo "Contexts:"
KUBECONFIG="$OUTPUT" kubectl config get-contexts -o name
