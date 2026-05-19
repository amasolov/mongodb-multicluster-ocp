# Multi-Cluster MongoDB HA/DR on OpenShift

Deployment guide and automation for a high-availability, disaster-recovery MongoDB replica set across 3 independent OpenShift clusters using the MongoDB Controllers for Kubernetes (MCK) 1.8.0 operator with Ops Manager.

Tested on OpenShift 4.20 with MCK 1.8.0 and MongoDB Enterprise 8.0.4.

## Architecture

```
+-----------------------------+    +-----------------------------+    +-------------------+
|     Cluster 1 / DC1         |    |     Cluster 2 / DC2         |    | Cluster 3 / Arb   |
|     (us-east-2)             |    |     (ap-southeast-1)        |    | (eu-central-1)    |
|                             |    |                             |    |                   |
|  MCK Operator (central)     |    |                             |    |                   |
|  Ops Manager (1 replica)    |    |                             |    |                   |
|  AppDB (3 members, local)   |    |                             |    |                   |
|  ExternalDNS                |    |  ExternalDNS                |    | ExternalDNS       |
|                             |    |                             |    |                   |
|  Data Member 0 (pri=10) <---+--->+--> Data Member 2 (pri=5)    |<-->| Data Member 4     |
|  Data Member 1 (pri=10) <---+--->+--> Data Member 3 (pri=5)    |<-->|  (pri=0, arbiter) |
|                             |    |                             |    |                   |
|  [NLB per pod]              |    |  [NLB per pod]              |    | [NLB]             |
+-----------------------------+    +-----------------------------+    +-------------------+
       |                                   |                                 |
       v                                   v                                 v
   Route53 zone                       Route53 zone                      Route53 zone
```

**Data replica set:** 5 members (2+2+1 arbiter). Any single site loss leaves a 3-of-5 majority and writes continue automatically. Cross-site failover was verified in under 15 seconds.

**Ops Manager:** Single instance on Cluster 1 with a 3-member AppDB. Exposed via an OpenShift Route so agents on all clusters can reach it.

**Networking:** AWS NLB LoadBalancer services per MongoDB pod. ExternalDNS creates Route53 records that map pod hostnames to NLB addresses. No service mesh required.

## Prerequisites

- 3 OpenShift clusters (4.14+) with `kubeadmin` access
- A StorageClass supporting `ReadWriteOnce` on each cluster (e.g. `gp3-csi` on AWS)
- AWS credentials with Route53 write access for each cluster's DNS zone
- Port 27017 reachable between all 3 clusters (NLB security groups)
- `oc`, `kubectl`, and `helm` CLIs installed locally
- The `kubectl-mongodb` plugin ([MCK releases](https://github.com/mongodb/mongodb-kubernetes/releases/tag/1.8.0))
- OpenShift GitOps (Argo CD) installed on each cluster (for the GitOps workflow)

## Repository Layout

```
gitops/
  base/                   Shared Kustomize manifests (all clusters)
    namespaces.yaml       Namespace definitions
    cert-manager/         TLS CA and server certificates
    external-dns/         ExternalDNS deployment, RBAC, AWS secret
    ops-manager/          Ops Manager CR, admin secret, OCP Route
    mongodb-data/         MongoDBMultiCluster CR, OM connection config
    rbac/                 SCC grants, member-cluster role patches
  overlays/
    cluster1/             Central cluster (includes Ops Manager + data CR)
    cluster2/             Secondary data site
    cluster3/             Arbiter site
  argocd/
    appset.yaml           ApplicationSet (generates 3 Argo CD Applications)
    project.yaml          AppProject with destination restrictions

bootstrap/                Imperative day-0 scripts (run once before GitOps)
  01-merge-kubeconfig.sh  Build merged kubeconfig with simplified contexts
  02-helm-install-mck-operator.sh  Install MCK multi-cluster operator via Helm
  03-multicluster-rbac-setup.sh    kubectl mongodb multicluster setup
  04-grant-scc.sh         Grant anyuid SCC to MongoDB ServiceAccounts
  05-patch-member-roles.sh  Add mongodb.com API group to member Roles
  06-install-crds-members.sh  Copy CRDs to member clusters
  07-fix-om-hostnames.sh  Fix Ops Manager automation config hostnames

playbooks/                Day-2 Ansible playbooks
  test_failover.yml       Simulate site loss, verify election
  teardown.yml            Remove all MongoDB resources
```

## Deployment: GitOps Workflow (Argo CD)

### Phase 1: Bootstrap (imperative, run once)

These steps set up the MCK operator and cross-cluster RBAC that Argo CD cannot manage declaratively.

```bash
# 1. Build the merged kubeconfig
./bootstrap/01-merge-kubeconfig.sh \
  https://api.cluster1.example.com:6443 '<password1>' \
  https://api.cluster2.example.com:6443 '<password2>' \
  https://api.cluster3.example.com:6443 '<password3>'

export KUBECONFIG=multicluster.kubeconfig

# 2. Install the MCK multi-cluster operator via Helm
./bootstrap/02-helm-install-mck-operator.sh

# 3. Set up cross-cluster RBAC (ServiceAccounts, Roles, kubeconfig secrets)
./bootstrap/03-multicluster-rbac-setup.sh

# 4. Grant anyuid SCC on all clusters
./bootstrap/04-grant-scc.sh

# 5. Patch member-cluster Roles for mongodb.com API group
./bootstrap/05-patch-member-roles.sh

# 6. Copy CRDs to member clusters
./bootstrap/06-install-crds-members.sh
```

### Phase 2: Customise the overlays

Edit the following files with your environment-specific values:

1. **`gitops/base/mongodb-data/mongodb-multicluster.yaml`**: Set the `externalDomain` for each cluster in `clusterSpecList`.

2. **`gitops/overlays/cluster{1,2,3}/external-dns-patch.yaml`**: Set `--domain-filter` and `--txt-owner-id` for each cluster's Route53 zone.

3. **`gitops/overlays/cluster1/ops-manager-connection-patch.yaml`**: Set `baseUrl` to the external Ops Manager Route URL after Ops Manager is running.

### Phase 3: Apply secrets out-of-band

Create the secrets that are not committed to the repo:

```bash
# AWS credentials for ExternalDNS (on each cluster)
for ctx in cluster1 cluster2 cluster3; do
  kubectl --context $ctx -n external-dns create secret generic aws-route53-credentials \
    --from-literal=aws_access_key_id='<key>' \
    --from-literal=aws_secret_access_key='<secret>'
done

# Ops Manager admin credentials (cluster1 only)
kubectl --context cluster1 -n mongodb-ops-manager create secret generic ops-manager-admin-secret \
  --from-literal=Username='admin' \
  --from-literal=Password='<password>' \
  --from-literal=FirstName='Admin' \
  --from-literal=LastName='User'

# Ops Manager API key (all clusters, after Ops Manager is running)
for ctx in cluster1 cluster2 cluster3; do
  kubectl --context $ctx -n mongodb-data create secret generic ops-manager-api-key \
    --from-literal=publicKey='<key>' \
    --from-literal=privateKey='<secret>'
done
```

### Phase 4: Register clusters and deploy via Argo CD

```bash
# Register member clusters with Argo CD (from the hub cluster)
argocd cluster add cluster2 --name cluster2
argocd cluster add cluster3 --name cluster3

# Apply the AppProject and ApplicationSet
kubectl apply -f gitops/argocd/project.yaml
kubectl apply -f gitops/argocd/appset.yaml
```

Argo CD will sync the overlays to each cluster in order of sync waves:
- **Wave 0:** Namespaces, RBAC, SCC grants
- **Wave 1:** cert-manager Issuers and Certificates
- **Wave 2:** ExternalDNS
- **Wave 3:** Ops Manager (cluster1 only)
- **Wave 4:** Ops Manager connection ConfigMap and API key
- **Wave 5:** MongoDBMultiCluster CR (cluster1 only)

### Phase 5: Post-sync fixes

After the MongoDBMultiCluster CR is applied and pods are running, fix the Ops Manager automation config hostnames:

```bash
./bootstrap/07-fix-om-hostnames.sh
```

This is a workaround for MCK 1.8.0 pushing `svc.cluster.local` hostnames to the automation config even when `externalDomain` is configured.

## Deployment: Standalone (without Argo CD)

If you are not using GitOps, you can apply the manifests directly:

```bash
# Run all bootstrap scripts (steps 1-6 above)

# Then apply each overlay manually
for ctx in cluster1 cluster2 cluster3; do
  kustomize build gitops/overlays/$ctx | kubectl --context $ctx apply -f -
done

# Run the post-sync hostname fix
./bootstrap/07-fix-om-hostnames.sh
```

## Testing Failover

```bash
ansible-playbook playbooks/test_failover.yml --ask-vault-pass -e failover_target=cluster1
```

Or manually:

```bash
# Freeze both cluster1 members to prevent re-election
kubectl --context cluster1 exec mongodb-rs-0-0 -- mongosh --eval 'db.adminCommand({replSetFreeze: 120})'
kubectl --context cluster1 exec mongodb-rs-0-1 -- mongosh --eval 'rs.stepDown(120, 10)'

# Verify cluster2 member becomes primary
kubectl --context cluster2 exec mongodb-rs-1-0 -- mongosh --eval 'rs.status()'
```

## Known Issues and Workarounds

| Issue | Workaround |
|---|---|
| `kubectl mongodb multicluster setup` does not install `mongodb.com` API group RBAC on member clusters | `bootstrap/05-patch-member-roles.sh` |
| CRDs are not installed on member clusters by the setup command | `bootstrap/06-install-crds-members.sh` |
| Ops Manager operator cannot verify self-signed TLS certs for its own API calls | Disable TLS on the Ops Manager API; keep TLS on AppDB |
| Agents on member clusters cannot download from Ops Manager via `svc.cluster.local` | Expose Ops Manager with an OpenShift Route; update ConfigMaps with external URL |
| Operator pushes `svc.cluster.local` hostnames to automation config even with `externalDomain` | `bootstrap/07-fix-om-hostnames.sh` |
| OpenShift SCC blocks MongoDB pods with `runAsUser` | `bootstrap/04-grant-scc.sh` |
| MCK multi-cluster operator is not available via OLM | `bootstrap/02-helm-install-mck-operator.sh` |

## Security

- **Credentials are never committed to Git.** Secret manifests contain `PLACEHOLDER` values. Real secrets are applied out-of-band.
- **SCRAM-SHA-256 authentication** is enabled on the data replica set.
- **TLS** is enabled on the AppDB via cert-manager certificates.
- Argo CD is configured with `ignoreDifferences` on Secret `/data` to avoid overwriting real credentials with placeholders.

## References

- [MongoDB Controllers for Kubernetes](https://www.mongodb.com/docs/kubernetes/current/)
- [Multi-Cluster Replica Sets](https://www.mongodb.com/docs/kubernetes/current/reference-architectures/multi-cluster/multi-cluster-replica-sets/)
- [Deploy Without Service Mesh](https://www.mongodb.com/docs/kubernetes/current/reference-architectures/multi-cluster-no-mesh/deploy-operator-no-mesh/)
- [Configure External DNS](https://www.mongodb.com/docs/kubernetes-operator/current/reference-architectures/multi-cluster-no-mesh/external-dns-no-mesh/)
- [Ops Manager Multi-Cluster](https://www.mongodb.com/docs/kubernetes/current/reference/k8s-operator-om-specification/)
- [Geographically Distributed Replica Sets](https://www.mongodb.com/docs/manual/tutorial/deploy-geographically-distributed-replica-set/)
