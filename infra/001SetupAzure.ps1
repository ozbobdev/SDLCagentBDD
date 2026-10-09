function Initialize-SdlcDocsEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$GitHubRepo
    )

    $HARNESS_RG = "rg-sdlcdocs-harness"
    $SAMPLE_APP_RG = "rg-sdlcdocs-sample-app"
    $TF_BACKEND_RG = "rg-sdlcdocs-tfstate"
    $TF_BACKEND_STORAGE_ACCOUNT = "sdlcdocstfstate001"
    $TF_BACKEND_CONTAINER = "tfstate"
    $SP_NAME = "sp-sdlcdocs-github"

    function Ensure-Command {
        param([string]$Name)
        if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
            throw "Required command '$Name' is not installed or not on PATH."
        }
    }

    function Ensure-ResourceGroup {
        param([string]$Name, [string]$Region)

        $exists = az group exists --name $Name
        if ($exists -eq "true") {
            Write-Host "Resource group '$Name' already exists."
        }
        else {
            Write-Host "Creating resource group '$Name'..."
            az group create --name $Name --location $Region | Out-Null
        }
    }

    function Ensure-RoleAssignment {
        param(
            [string]$ObjectId,
            [string]$Role,
            [string]$Scope
        )

        $assigned = az role assignment list `
            --assignee-object-id $ObjectId `
            --scope $Scope `
            --query "[?roleDefinitionName=='$Role']" -o tsv

        if ($assigned) {
            Write-Host "Role '$Role' already assigned at scope '$Scope'."
        }
        else {
            Write-Host "Assigning role '$Role' at scope '$Scope'..."
            az role assignment create `
                --assignee-object-id $ObjectId `
                --assignee-principal-type ServicePrincipal `
                --role $Role `
                --scope $Scope | Out-Null
        }
    }

    Ensure-Command az
    Ensure-Command gh

    Write-Host "Logging into Azure..."
    az login --tenant $TenantId | Out-Null
    az account set --subscription $SubscriptionId

    Ensure-ResourceGroup -Name $HARNESS_RG -Region $Location
    Ensure-ResourceGroup -Name $SAMPLE_APP_RG -Region $Location
    Ensure-ResourceGroup -Name $TF_BACKEND_RG -Region $Location

    $saAvailable = az storage account check-name --name $TF_BACKEND_STORAGE_ACCOUNT --query nameAvailable -o tsv
    if ($saAvailable -eq "false") {
        Write-Host "Storage account '$TF_BACKEND_STORAGE_ACCOUNT' already exists."
    }
    else {
        Write-Host "Creating storage account '$TF_BACKEND_STORAGE_ACCOUNT'..."
        az storage account create `
            --name $TF_BACKEND_STORAGE_ACCOUNT `
            --resource-group $TF_BACKEND_RG `
            --location $Location `
            --sku Standard_LRS `
            --kind StorageV2 | Out-Null
    }

    $containerExists = az storage container exists `
        --name $TF_BACKEND_CONTAINER `
        --account-name $TF_BACKEND_STORAGE_ACCOUNT `
        --auth-mode login `
        --query exists -o tsv

    if ($containerExists -eq "true") {
        Write-Host "Container '$TF_BACKEND_CONTAINER' already exists."
    }
    else {
        Write-Host "Creating container '$TF_BACKEND_CONTAINER'..."
        az storage container create `
            --name $TF_BACKEND_CONTAINER `
            --account-name $TF_BACKEND_STORAGE_ACCOUNT `
            --auth-mode login | Out-Null
    }

    $existingSP = az ad sp list --display-name $SP_NAME -o json | ConvertFrom-Json

    if ($existingSP.Count -gt 0) {
        Write-Host "Service principal '$SP_NAME' already exists."
        $AZURE_CLIENT_ID = $existingSP[0].appId
        $SP_OBJECT_ID = $existingSP[0].id
        $AZURE_TENANT_ID = $TenantId

        Write-Host "Resetting service principal credentials to produce a fresh client secret..."
        $NEW_SECRET = az ad app credential reset --id $AZURE_CLIENT_ID -o json | ConvertFrom-Json
        $AZURE_CLIENT_SECRET = $NEW_SECRET.password
    }
    else {
        Write-Host "Creating service principal '$SP_NAME'..."
        $SP_JSON = az ad sp create-for-rbac --name $SP_NAME --skip-assignment -o json | ConvertFrom-Json
        $AZURE_CLIENT_ID = $SP_JSON.appId
        $AZURE_CLIENT_SECRET = $SP_JSON.password
        $AZURE_TENANT_ID = $SP_JSON.tenant
        $SP_OBJECT_ID = az ad sp show --id $AZURE_CLIENT_ID --query id -o tsv
    }

    $HARNESS_SCOPE = az group show --name $HARNESS_RG --query id -o tsv
    $SAMPLE_SCOPE = az group show --name $SAMPLE_APP_RG --query id -o tsv

    Ensure-RoleAssignment -ObjectId $SP_OBJECT_ID -Role "Contributor" -Scope $HARNESS_SCOPE
    Ensure-RoleAssignment -ObjectId $SP_OBJECT_ID -Role "Contributor" -Scope $SAMPLE_SCOPE

    $STORAGE_ACCOUNT_ID = az storage account show --resource-group $TF_BACKEND_RG --name $TF_BACKEND_STORAGE_ACCOUNT --query id -o tsv
    $CONTAINER_SCOPE = "$STORAGE_ACCOUNT_ID/blobServices/default/containers/$TF_BACKEND_CONTAINER"
    Ensure-RoleAssignment -ObjectId $SP_OBJECT_ID -Role "Storage Blob Data Contributor" -Scope $CONTAINER_SCOPE

    Write-Host "Setting GitHub secrets in $GitHubRepo..."
    gh secret set AZURE_CLIENT_ID --body $AZURE_CLIENT_ID --repo $GitHubRepo
    gh secret set AZURE_CLIENT_SECRET --body $AZURE_CLIENT_SECRET --repo $GitHubRepo
    gh secret set AZURE_TENANT_ID --body $AZURE_TENANT_ID --repo $GitHubRepo
    gh secret set AZURE_SUBSCRIPTION_ID --body $SubscriptionId --repo $GitHubRepo
    gh secret set TF_BACKEND_RESOURCE_GROUP --body $TF_BACKEND_RG --repo $GitHubRepo
    gh secret set TF_BACKEND_STORAGE_ACCOUNT --body $TF_BACKEND_STORAGE_ACCOUNT --repo $GitHubRepo
    gh secret set TF_BACKEND_CONTAINER --body $TF_BACKEND_CONTAINER --repo $GitHubRepo

    Write-Host "Initialization complete."
}
