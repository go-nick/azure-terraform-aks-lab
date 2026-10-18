# Azure Lab

Studying lab for Terraform + Azure + Kubernetes. Each subfolder is an independent
Terraform project - its own state, its own secrets, its own `terraform init`.

## Usage

Each project folder has a `Makefile` that sources `.env` before running Terraform,
and an `.env` with secrets/subscription IDs that's never committed.

```bash
cd <project-folder>
cp .env.example .env   # fill in your own values
make init
make plan
make apply
```

Teardown:
```bash
make destroy
```

## Projects

Each project builds on the last - same n8n app, one new piece of real
infrastructure added at a time.

| Path | Details |
|------|---------|
| `1_n8n-hello/` | AKS cluster (Cilium CNI) + Azure Postgres Flexible Server provisioned via Terraform. n8n deployed with hand-written Kubernetes manifests - no Helm chart - reverse-engineered directly from n8n's Docker-only install docs. **Proves:** core Terraform/AKS provisioning, translating container-only documentation into native Kubernetes primitives (PVC/StorageClass dynamic provisioning) from first principles, resolving real Azure region/SKU/version constraints via live API checks instead of trial-and-error. |
| `2_n8n-postgres/` | Converted the bare Pod into a Deployment and wired n8n to the externally managed Postgres server, validating connectivity with a throwaway `psql` pod before trusting the app layer. **Proves:** Pod-to-Deployment migration, external managed-database integration, and a methodical "verify the dependency before debugging the app" troubleshooting habit. |
| `3_n8n-loadbalancer/` | Exposed n8n publicly via a `type: LoadBalancer` Service. Found and fixed a real zero-Endpoints bug caused by a missing Pod label. **Proves:** the Kubernetes Service/Endpoints/label-selector debugging methodology (selector -> Endpoints -> Service -> LoadBalancer, top-down) and solid understanding of how cloud-provider LoadBalancers actually get wired to Pods. |
| `4_n8n-azure-secrets/` | Azure Key Vault + AKS Secrets Store CSI Driver. Secrets flow entirely through managed-identity auth - `SecretProviderClass` -> CSI volume mount -> `secretObjects` sync -> native `Secret` -> `envFrom` - with zero credentials ever hardcoded, and `templatefile()` keeping the managed identity's client ID valid across cluster rebuilds. **Proves:** secure, identity-based secrets architecture over stored credentials, diagnosing and migrating off a real upstream Terraform provider bug (`hashicorp/kubernetes` -> `gavinbunney/kubectl`), and documenting a non-trivial data flow clearly enough for someone else to follow. |
| `5_n8n-ingress-certs/` | Traefik + cert-manager + Let's Encrypt, fully wired through Terraform (`helm_release` + a templated `ClusterIssuer`), with a staging-then-prod ACME workflow and automatic TLS termination. Dropped the app's direct public LoadBalancer once Ingress became the sole entry point. **Proves:** production-grade TLS/certificate automation, full-stack incident troubleshooting (traced a stuck certificate through the real `Certificate -> CertificateRequest -> Order -> Challenge` chain to its DNS root cause), security-conscious IaC (no PII/secrets committed), and correct dependency-graph modeling in Terraform (real edges vs. accidental ordering).

## New project helper

```bash
make new-project
```

Prompts for a name, copies `n8n-hello/` into a new folder as a starting template
(skips `.env`, `.terraform/`, `.terraform.lock.hcl`, `terraform.tfstate*`). Edit
the copied `main.tf`/`README.md` and fill in a fresh `.env` from there.
