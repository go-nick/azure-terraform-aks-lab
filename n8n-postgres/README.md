# n8n on AKS

Terraform provisions an AKS cluster (Cilium dataplane/network policy) and a managed
Postgres Flexible Server. Kubernetes manifests deploy n8n by hand - no Helm chart,
reverse-engineered from n8n's Docker install docs.

## Infra (Terraform)

```bash
cp .env.example .env   # fill in your subscription ID + db password
make init
make plan
make apply
```

Outputs `db_host`, `db_name`, `db_user` for the Postgres server once applied.

## n8n (Kubernetes manifests)

n8n currently runs standalone with SQLite (default), not yet wired to the
Postgres server above - that's a later step.

```bash
az aks get-credentials --resource-group rg-cloud-course-aks --name mercury-cluster
kubectl apply -f manifests/
kubectl port-forward pod/n8n 5678:5678
```

Then open `http://localhost:5678`.

- `manifests/pod.yaml` - n8n container, non-root (UID 1000), PVC-backed storage
- `manifests/persistentvolume.yaml` - PVC using the cluster's default StorageClass
- `manifests/configmap.yaml` - env vars (timezone, runner/permission flags)

## Teardown

```bash
kubectl delete -f manifests/
make destroy
```
