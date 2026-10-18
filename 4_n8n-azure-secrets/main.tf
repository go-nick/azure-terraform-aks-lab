terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "azurerm" {
  features {}
  # subscription_id comes from the ARM_SUBSCRIPTION_ID env var (see .env.example)
  resource_provider_registrations = "none"
}

provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
  load_config_file       = false
}

# ____________________________________________________________________________________________
# VARIABLES
variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_user" {
  type = string
  sensitive = true
}

# ____________________________________________________________________________________________
# AZURE
#
resource "azurerm_resource_group" "aks" {
  name     = "rg-cloud-aks"
  location = "westus"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "nick-aks-cluster"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = "nick"
  kubernetes_version  = "1.34.0"

  # Azure enables this by default on creation and won't allow disabling it afterward -
  # declare it explicitly so Terraform stops trying to revert it to the schema default.
  oidc_issuer_enabled = true

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2s_v7"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "cilium"
    network_data_plane = "cilium"
  }
  # configuration for secrets
  key_vault_secrets_provider {
    secret_rotation_enabled = false
  }
}

# __________________________________________________________________________________________
# POSTGRES DB

# The managed server itself: the actual compute/storage instance (the "engine").
# By default it only has the built-in system db (postgres) - no app database exists yet.
resource "azurerm_postgresql_flexible_server" "n8n_db" {

  name                = "psql-n8n-nicklab-aks-01"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  # zone omitted - westus reports no supported zones for this SKU, let Azure auto-place

  # from .env
  administrator_login    = var.db_user
  administrator_password = var.db_password

  sku_name   = "B_Standard_B1ms"
  storage_mb = 32768
  version    = "16"

  backup_retention_days = 7

  # Allow Azure services to access (needed for AKS)
  public_network_access_enabled = true
}

# Server-level config override - a single named parameter on the server, like
# `ALTER SYSTEM SET require_secure_transport = 'OFF'`. Not a database itself.
resource "azurerm_postgresql_flexible_server_configuration" "disable_ssl" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.n8n_db.id
  value     = "OFF"
}

# The actual logical database n8n connects to - equivalent to running
# `CREATE DATABASE n8n;` against the server above. One server can host many
# separate databases; without this resource, n8n's connection string
# (DB_POSTGRESDB_DATABASE=n8n) would have nothing to point at.
resource "azurerm_postgresql_flexible_server_database" "n8n" {
  name      = "n8n"
  server_id = azurerm_postgresql_flexible_server.n8n_db.id
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.n8n_db.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ___________________________________________________________________________________
## Key vault

data "azurerm_client_config" "current" {}

## Create the resource key vault
resource "azurerm_key_vault" "nicklab_vault" {
  name                = "kv-n8n-nicklab"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Make it easy to destroy and recreate
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  # Allow Terraform to manage secrets
  # Using RBAC authorization to authenticate to the secrets
  rbac_authorization_enabled = true
  depends_on                 = [azurerm_kubernetes_cluster.main]
}

# Give yourself permission to manage secrets
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.nicklab_vault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Give yourself permission to manage kubernetes key vault
resource "azurerm_role_assignment" "aks_keyvault_secrets_provider" {
  scope                = azurerm_key_vault.nicklab_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].object_id
}

# Create the secrets
resource "azurerm_key_vault_secret" "db_host" {
  name         = "db-host"
  value        = azurerm_postgresql_flexible_server.n8n_db.fqdn
  key_vault_id = azurerm_key_vault.nicklab_vault.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "db_name" {
  name         = "db-name"
  value        = azurerm_postgresql_flexible_server_database.n8n.name
  key_vault_id = azurerm_key_vault.nicklab_vault.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "db_user" {
  name         = "db-user"
  # this secret can't be created until postgres server exists
  value        = azurerm_postgresql_flexible_server.n8n_db.administrator_login
  key_vault_id = azurerm_key_vault.nicklab_vault.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  # this secret can't be created until postgres server exists
  value        = azurerm_postgresql_flexible_server.n8n_db.administrator_password
  key_vault_id = azurerm_key_vault.nicklab_vault.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

# _________________________________________________________________________________
# n8n (Kubernetes manifests)

resource "kubectl_manifest" "n8n_namespace" {
  yaml_body = file("${path.module}/manifests/namespace.yaml")
}

resource "kubectl_manifest" "n8n_secrets" {
  yaml_body = templatefile("${path.module}/manifests/secrets.yaml.tpl", {
    client_id = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].client_id
    tenant_id = data.azurerm_client_config.current.tenant_id
    keyvault_name = azurerm_key_vault.nicklab_vault.name
  })

  depends_on = [
    kubectl_manifest.n8n_namespace, 
  ]
}

resource "kubectl_manifest" "n8n_configmap" {
  yaml_body = file("${path.module}/manifests/configmap.yaml")

  depends_on = [
    kubectl_manifest.n8n_namespace,
  ]
}

resource "kubectl_manifest" "n8n_pvc" {
  yaml_body = file("${path.module}/manifests/storage.yaml")

  depends_on = [
    kubectl_manifest.n8n_configmap,
  ]
}

resource "kubectl_manifest" "n8n_deployment" {
  yaml_body = file("${path.module}/manifests/deployment.yaml")

  depends_on = [
    kubectl_manifest.n8n_namespace,
    kubectl_manifest.n8n_configmap,
    kubectl_manifest.n8n_pvc,
  ]
}

resource "kubectl_manifest" "n8n_service" {
  yaml_body = file("${path.module}/manifests/service.yaml")

  depends_on = [
    kubectl_manifest.n8n_deployment,
  ]
}

# ________________________________________________________________________________
# OUTPUTS

output "key_vault_name" {
  value = azurerm_key_vault.nicklab_vault.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.nicklab_vault.vault_uri
}

output "aks_keyvault_secrets_provider_client_id" {
  value       = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].client_id
  description = "AKS Key Vault Secrets Provider Client ID for use in SecretProviderClass"
}
output "db_host" {
  value = azurerm_postgresql_flexible_server.n8n_db.fqdn
}

output "db_name" {
  value = azurerm_postgresql_flexible_server_database.n8n.name
}

output "kubectl_credentials_command" {
  description = "Run this to authenticate your local kubectl/k9s against this cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.aks.name} --name ${azurerm_kubernetes_cluster.main.name} --overwrite-existing"
}

