apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: n8n-secrets
  namespace: n8n
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "${client_id}" # tf resource: akz_keyvault_secrets_provider_client_id
    keyvaultName: "${keyvault_name}" # tf resource: key_vault_name
    tenantId: "${tenant_id}" # az account list
    objects: |
      array:
        - |
          objectName: db-user
          objectType: secret
        - |
          objectName: db-password
          objectType: secret
  secretObjects:
    - secretName: n8n-container-env
      type: Opaque
      data:
        - objectName: db-user
          key: DB_POSTGRESDB_USER
        - objectName: db-password
          key: DB_POSTGRESDB_PASSWORD
