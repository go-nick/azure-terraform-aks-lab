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

- `n8n-hello/` - AKS cluster + managed Postgres via Terraform; n8n deployed with
  hand-written Kubernetes manifests (no Helm chart), reverse-engineered from
  n8n's Docker install docs.
