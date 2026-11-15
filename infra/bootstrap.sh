#!/usr/bin/env bash
# Bootstrap da nuvem (rodar UMA vez, logado com "az login", no Git Bash ou Cloud Shell).
#
# Cria o que o Terraform não deve criar para si mesmo:
#   1. Resource group da aplicação (o deploy só terá permissão nele — menor privilégio)
#   2. Storage Account para o state remoto do Terraform (sem chave compartilhada, sem acesso público)
#   3. Identidade gerenciada com credencial federada (OIDC) para o GitHub Actions — sem senha
#
# Uso:
#   GITHUB_REPO="seu-usuario/belka-app-mvp" bash infra/bootstrap.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1 # Git Bash: não converter "/subscriptions/..." em caminho do Windows

: "${GITHUB_REPO:?Defina GITHUB_REPO=usuario/repositorio (exatamente como no GitHub)}"
LOCATION="${LOCATION:-brazilsouth}"
APP_RG="${APP_RG:-rg-belka}"
STATE_RG="${STATE_RG:-rg-belka-tfstate}"
STATE_SA="${STATE_SA:-stbelkatf${RANDOM}${RANDOM}}" # nome globalmente único, minúsculas e dígitos
IDENTITY="${IDENTITY:-id-belka-github}"
GH_ENVIRONMENT="${GH_ENVIRONMENT:-production}"

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
echo ">> Assinatura: $SUBSCRIPTION_ID | Região: $LOCATION"

echo ">> Registrando resource providers (pode levar alguns minutos)"
for p in Microsoft.App Microsoft.OperationalInsights Microsoft.Insights Microsoft.AlertsManagement Microsoft.Storage Microsoft.ManagedIdentity; do
  az provider register --namespace "$p" --wait
done

echo ">> Resource groups"
az group create -n "$APP_RG" -l "$LOCATION" -o none
az group create -n "$STATE_RG" -l "$LOCATION" -o none
APP_RG_ID="$(az group show -n "$APP_RG" --query id -o tsv)"

echo ">> Storage do state: $STATE_SA"
az storage account create -n "$STATE_SA" -g "$STATE_RG" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false -o none
SA_ID="$(az storage account show -n "$STATE_SA" -g "$STATE_RG" --query id -o tsv)"
az storage account blob-service-properties update --account-name "$STATE_SA" -g "$STATE_RG" \
  --enable-versioning true -o none

ME="$(az ad signed-in-user show --query id -o tsv)"
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none
echo ">> Aguardando propagação da permissão (60 s)"
sleep 60
az storage container create -n tfstate --account-name "$STATE_SA" --auth-mode login -o none

echo ">> Identidade do GitHub Actions (OIDC, sem segredo de senha)"
az identity create -n "$IDENTITY" -g "$STATE_RG" -l "$LOCATION" -o none
CLIENT_ID="$(az identity show -n "$IDENTITY" -g "$STATE_RG" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show -n "$IDENTITY" -g "$STATE_RG" --query principalId -o tsv)"
az identity federated-credential create --name "github-${GH_ENVIRONMENT}" \
  --identity-name "$IDENTITY" -g "$STATE_RG" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:${GITHUB_REPO}:environment:${GH_ENVIRONMENT}" \
  --audiences "api://AzureADTokenExchange" -o none

# O GitHub pode emitir o subject no formato com IDs imutáveis
# (repo:dono@ID/repo@ID:environment:...). Se o gh CLI estiver logado, cria também essa variante.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  OWNER_ID="$(gh api "repos/${GITHUB_REPO}" --jq .owner.id)"
  REPO_ID="$(gh api "repos/${GITHUB_REPO}" --jq .id)"
  az identity federated-credential create --name "github-${GH_ENVIRONMENT}-ids" \
    --identity-name "$IDENTITY" -g "$STATE_RG" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "repo:${GITHUB_REPO%%/*}@${OWNER_ID}/${GITHUB_REPO##*/}@${REPO_ID}:environment:${GH_ENVIRONMENT}" \
    --audiences "api://AzureADTokenExchange" -o none
else
  echo "!! gh CLI não logado: se o deploy falhar com AADSTS700213, crie a credencial com o subject exibido no erro."
fi

# Menor privilégio: Contributor só no RG da aplicação; leitura/escrita só no blob do state.
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role Contributor --scope "$APP_RG_ID" -o none
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none

cat <<EOF

=====================================================================
 Pronto. Cadastre no GitHub (Settings > Secrets and variables > Actions):

 Secrets:
   AZURE_CLIENT_ID        = $CLIENT_ID
   AZURE_TENANT_ID        = $TENANT_ID
   AZURE_SUBSCRIPTION_ID  = $SUBSCRIPTION_ID
   ALERT_EMAIL            = <e-mail da equipe>
   DATABRICKS_SERVER_HOSTNAME / DATABRICKS_HTTP_PATH / DATABRICKS_TOKEN  (opcionais)

 Variables:
   AZURE_RESOURCE_GROUP     = $APP_RG
   TFSTATE_RESOURCE_GROUP   = $STATE_RG
   TFSTATE_STORAGE_ACCOUNT  = $STATE_SA

 E crie o Environment "${GH_ENVIRONMENT}" (Settings > Environments).
=====================================================================
EOF
