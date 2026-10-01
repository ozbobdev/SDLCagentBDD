# SDLCdocs

Document driven software development lifecycle repository.

## Purpose
SDLCdocs defines a document-first SDLC where Product Owners, Developer agents, and Project Managers collaborate via a Product Catalog wiki and a BDD wiki. Agents automate intake, issue creation, BDD generation, and documentation maintenance.

## Repo structure
- AGENT_PROMPT.txt
- sub-agents.md
- github.md
- agents/
  - monitor_and_fix_bugs.md
- samples/
  - README.md
  - sample-squad.json
  - sample-app/
    - openapi-v0.1.yaml
    - openapi-v1.0.yaml
    - dotnet-api/
    - angular-web/
- screenshots/

## Squad
This repo needs a Squad team leader who iterates on documentation and SDLC workflows.

Install squad CLI
- npm install -g @bradygaster/squad-cli

Start copilot agent for squad
- copilot --agent squad --yolo

## First use (GitHub + Azure setup)
1. Create or choose an Azure subscription for this repo.
2. Create required Azure resource groups (Portal or CLI):
   - `rg-sdlcdocs-harness` (agent harness deployment target)
   - `rg-sdlcdocs-sample-app` (sample app deployment target)
   - `rg-sdlcdocs-tfstate` (Terraform backend resources)
3. Create Terraform backend storage (Portal or CLI):
   - Storage account (example: `sdlcdocstfstate001`)
   - Blob container (example: `tfstate`)
4. Create a service principal and assign least-privilege roles:
   - Contributor on harness and sample-app resource groups
   - Storage Blob Data Contributor on Terraform backend container
5. Add required GitHub repository secrets:
   - `AZURE_CLIENT_ID`
   - `AZURE_CLIENT_SECRET`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `TF_BACKEND_RESOURCE_GROUP`
   - `TF_BACKEND_STORAGE_ACCOUNT`
   - `TF_BACKEND_CONTAINER`
6. Add integration secrets if needed:
   - `AZURE_HARNESS_API_KEY`
   - `AZURE_STORAGE_CONNECTION_STRING`
   - `AZURE_KEYVAULT_NAME`
7. Run workflow:
   - `.github/workflows/first-use-bootstrap.yml`
   - Provide `harness_resource_group`, `sample_app_resource_group`, and container image inputs.

### Azure Portal step-by-step
1. In Azure Portal, open **Resource groups** → **Create** and create:
   - `rg-sdlcdocs-harness`
   - `rg-sdlcdocs-sample-app`
   - `rg-sdlcdocs-tfstate`
2. Open **Storage accounts** → **Create**:
   - Resource group: `rg-sdlcdocs-tfstate`
   - Name: globally unique name (example `sdlcdocstfstate001`)
3. Open the new storage account → **Data storage** → **Containers** → **+ Container**:
   - Name: `tfstate`
4. Open **Microsoft Entra ID** → **App registrations** → **New registration**:
   - Name: `sp-sdlcdocs-github`
   - Supported account type: Single tenant
5. Open the app registration:
   - Copy **Application (client) ID** and **Directory (tenant) ID**
   - Open **Certificates & secrets** → **New client secret** and copy the secret value
6. Grant RBAC for deployment resource groups:
   - Open `rg-sdlcdocs-harness` → **Access control (IAM)** → **Add role assignment**
   - Role: **Contributor**
   - Assign access to: User, group, or service principal
   - Select: `sp-sdlcdocs-github`
   - Repeat for `rg-sdlcdocs-sample-app`
7. Grant RBAC for Terraform state container:
   - Open storage account `sdlcdocstfstate001` → container `tfstate`
   - Open **Access control (IAM)** → **Add role assignment**
   - Role: **Storage Blob Data Contributor**
   - Select: `sp-sdlcdocs-github`
8. In GitHub repo settings, add secrets using values collected above.

### Azure CLI (`az`) equivalent
```bash
# Set your values
SUBSCRIPTION_ID="<azure-subscription-id>"
LOCATION="australiaeast"
HARNESS_RG="rg-sdlcdocs-harness"
SAMPLE_APP_RG="rg-sdlcdocs-sample-app"
TF_BACKEND_RG="rg-sdlcdocs-tfstate"
TF_BACKEND_STORAGE_ACCOUNT="sdlcdocstfstate001"   # must be globally unique
TF_BACKEND_CONTAINER="tfstate"
SP_NAME="sp-sdlcdocs-github"

az login
az account set --subscription "$SUBSCRIPTION_ID"

# Resource groups
az group create --name "$HARNESS_RG" --location "$LOCATION"
az group create --name "$SAMPLE_APP_RG" --location "$LOCATION"
az group create --name "$TF_BACKEND_RG" --location "$LOCATION"

# Terraform backend storage account + container
az storage account create \
  --name "$TF_BACKEND_STORAGE_ACCOUNT" \
  --resource-group "$TF_BACKEND_RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2

az storage container create \
  --name "$TF_BACKEND_CONTAINER" \
  --account-name "$TF_BACKEND_STORAGE_ACCOUNT" \
  --auth-mode login

# Service principal (no default role assignment)
SP_JSON=$(az ad sp create-for-rbac --name "$SP_NAME" --skip-assignment -o json)
AZURE_CLIENT_ID=$(echo "$SP_JSON" | jq -r .appId)
AZURE_CLIENT_SECRET=$(echo "$SP_JSON" | jq -r .password)
AZURE_TENANT_ID=$(echo "$SP_JSON" | jq -r .tenant)
SP_OBJECT_ID=$(az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv)

# Least-privilege role assignments for deployment RGs
HARNESS_SCOPE=$(az group show --name "$HARNESS_RG" --query id -o tsv)
SAMPLE_SCOPE=$(az group show --name "$SAMPLE_APP_RG" --query id -o tsv)
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal --role Contributor --scope "$HARNESS_SCOPE"
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal --role Contributor --scope "$SAMPLE_SCOPE"

# Storage Blob Data Contributor on Terraform backend container
STORAGE_ACCOUNT_ID=$(az storage account show --resource-group "$TF_BACKEND_RG" --name "$TF_BACKEND_STORAGE_ACCOUNT" --query id -o tsv)
CONTAINER_SCOPE="${STORAGE_ACCOUNT_ID}/blobServices/default/containers/${TF_BACKEND_CONTAINER}"
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope "$CONTAINER_SCOPE"

echo "Set GitHub secrets:"
echo "AZURE_CLIENT_ID=$AZURE_CLIENT_ID"
echo "AZURE_CLIENT_SECRET=<value from command output>"
echo "AZURE_TENANT_ID=$AZURE_TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "TF_BACKEND_RESOURCE_GROUP=$TF_BACKEND_RG"
echo "TF_BACKEND_STORAGE_ACCOUNT=$TF_BACKEND_STORAGE_ACCOUNT"
echo "TF_BACKEND_CONTAINER=$TF_BACKEND_CONTAINER"
```

## How to contribute
- Product Owners: open issues for new features using the intake template.
- Developers: follow the Developer checklist in AGENT_PROMPT.txt.
- Squad leader: review and merge PRs that update SDLC workflows.

End of README.
