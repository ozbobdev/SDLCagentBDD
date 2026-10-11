<#
.EXAMPLE
    . .\infra\002SetupAzure.ps1
    Invoke-SdlcDocsHarnessDeployment -TenantId $tenant -SubscriptionId $subscription -Location "WestUS2" -GitHubRepo "OzBob/AudioDownloadEpisode"
#>
function Invoke-SdlcDocsHarnessDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$GitHubRepo,

        [string]$HarnessResourceGroup = "rg-sdlcdocs-harness",
        [string]$TerraformBackendResourceGroup = "rg-sdlcdocs-tfstate",
        [string]$TerraformBackendStorageAccount = "sdlcdocstfstate001",
        [string]$TerraformBackendContainer = "tfstate",
        [string]$AiServicesAccountName = "aisdlcdocsharness001",
        [string]$ModelDeploymentName = "gpt-4o-mini",
        [string]$ModelName = "gpt-4o-mini",
        [string]$ModelVersion = "2024-07-18",
        [int]$ModelCapacity = 10,
        [string]$ModelSkuName = "GlobalStandard",
        [switch]$SetLocalUserEnvironment = $true,
        [string]$TerraformStateKey = "sdlcdocs-prompt-agent.tfstate"
    )

    function Ensure-Command {
        param([string]$Name)
        if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
            throw "Required command '$Name' is not installed or not on PATH."
        }
    }

    function Set-GitHubSecretIfValue {
        param([string]$Name, [string]$Value)

        if ([string]::IsNullOrWhiteSpace($Value)) {
            Write-Warning "Value for secret '$Name' was empty. Skipping."
            return
        }

        gh secret set $Name --body $Value --repo $GitHubRepo
        Write-Host "Updated GitHub secret '$Name'."
    }

    Ensure-Command az
    Ensure-Command gh
    Ensure-Command terraform

    $currentTenant = az account show --query tenantId -o tsv 2>$null
    $currentSubscription = az account show --query id -o tsv 2>$null

    if ($currentTenant -eq $TenantId -and $currentSubscription -eq $SubscriptionId) {
        Write-Host "Using existing Azure CLI session for tenant '$TenantId' and subscription '$SubscriptionId'."
    }
    elseif ($currentTenant -eq $TenantId) {
        Write-Host "Using existing Azure CLI session; switching subscription to '$SubscriptionId'."
        az account set --subscription $SubscriptionId
        if ($LASTEXITCODE -ne 0) { throw "Failed to set Azure subscription '$SubscriptionId'." }
    }
    else {
        Write-Host "Logging into Azure..."
        az login --tenant $TenantId | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Azure login failed for tenant '$TenantId'." }
        az account set --subscription $SubscriptionId
        if ($LASTEXITCODE -ne 0) { throw "Failed to set Azure subscription '$SubscriptionId'." }
    }

    foreach ($ns in "Microsoft.CognitiveServices", "Microsoft.Storage", "Microsoft.KeyVault") {
        Write-Host "Registering resource provider $ns..."
        az provider register --namespace $ns --wait | Out-Null
    }

    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    $tfDir = Join-Path $repoRoot "azure-harness/infra"

    Push-Location $tfDir
    try {
        terraform init `
            -reconfigure `
            -input=false `
            -backend-config="resource_group_name=$TerraformBackendResourceGroup" `
            -backend-config="storage_account_name=$TerraformBackendStorageAccount" `
            -backend-config="container_name=$TerraformBackendContainer" `
            -backend-config="key=$TerraformStateKey"
        if ($LASTEXITCODE -ne 0) { throw "terraform init failed." }

        # Import the resource group if it already exists in Azure but not in Terraform state
        $rgExists = az group exists --name $HarnessResourceGroup
        if ($rgExists -eq "true") {
            $inState = terraform state list 2>$null | Where-Object { $_ -eq "azurerm_resource_group.agents" }
            if (-not $inState) {
                Write-Host "Importing existing resource group '$HarnessResourceGroup' into Terraform state..."
                terraform import `
                    -var="subscription_id=$SubscriptionId" `
                    -var="tenant_id=$TenantId" `
                    -var="resource_group_name=$HarnessResourceGroup" `
                    -var="location=$Location" `
                    -var="ai_services_account_name=$AiServicesAccountName" `
                    -var="model_deployment_name=$ModelDeploymentName" `
                    -var="model_name=$ModelName" `
                    -var="model_version=$ModelVersion" `
                    -var="model_capacity=$ModelCapacity" `
                    -var="model_sku_name=$ModelSkuName" `
                    azurerm_resource_group.agents "/subscriptions/$SubscriptionId/resourceGroups/$HarnessResourceGroup"
                if ($LASTEXITCODE -ne 0) { throw "terraform import of resource group failed." }
            }
        }

        terraform plan `
            -var="subscription_id=$SubscriptionId" `
            -var="tenant_id=$TenantId" `
            -var="resource_group_name=$HarnessResourceGroup" `
            -var="location=$Location" `
            -var="ai_services_account_name=$AiServicesAccountName" `
            -var="model_deployment_name=$ModelDeploymentName" `
            -var="model_name=$ModelName" `
            -var="model_version=$ModelVersion" `
            -var="model_capacity=$ModelCapacity" `
            -var="model_sku_name=$ModelSkuName" `
            -out=tfplan

        terraform apply -auto-approve tfplan
        if ($LASTEXITCODE -ne 0) { throw "terraform apply failed." }

        $outputsJson = terraform output -json
        $outputs = $outputsJson | ConvertFrom-Json
    }
    finally {
        Pop-Location
    }

    $kvName = "kv-sdlcdocs-$($SubscriptionId.Substring(0,8))"
    $existingKvRg = az keyvault show --name $kvName --query resourceGroup -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($existingKvRg)) {
        Write-Host "Creating Key Vault '$kvName' in resource group '$HarnessResourceGroup'..."
        az keyvault create --name $kvName --resource-group $HarnessResourceGroup --location $Location --enable-rbac-authorization true | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Key Vault creation failed." }
        $existingKvRg = $HarnessResourceGroup
    }
    else {
        Write-Host "Using existing Key Vault '$kvName' in resource group '$existingKvRg'."
    }

    # Ensure the current caller can write secrets (role assignment may be missing on an existing vault)
    $kvId = az keyvault show --name $kvName --query id -o tsv
    $callerObjectId = az ad signed-in-user show --query id -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($callerObjectId)) {
        $callerObjectId = az account show --query user.name -o tsv
    }
    Write-Host "Ensuring 'Key Vault Secrets Officer' on '$kvName'..."
    az role assignment create --assignee-object-id $callerObjectId --assignee-principal-type User --role "Key Vault Secrets Officer" --scope $kvId | Out-Null
    Write-Host "Waiting for role assignment propagation..."
    Start-Sleep -Seconds 45

    $harnessApiKey = ""
    if ($outputs -and $outputs.PSObject.Properties.Name -contains "harness_api_key") {
        $harnessApiKey = [string]$outputs.harness_api_key.value
    }
    if ([string]::IsNullOrWhiteSpace($harnessApiKey)) { throw "Terraform output 'harness_api_key' is empty." }
    az keyvault secret set --vault-name $kvName --name "harness-api-key" --value $harnessApiKey | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to store harness-api-key in Key Vault '$kvName'." }

    $harnessEndpoint = ""
    if ($outputs -and $outputs.PSObject.Properties.Name -contains "harness_endpoint") {
        $harnessEndpoint = [string]$outputs.harness_endpoint.value
    }
    if ([string]::IsNullOrWhiteSpace($harnessEndpoint)) { throw "Terraform output 'harness_endpoint' is empty." }
    az keyvault secret set --vault-name $kvName --name "harness-endpoint" --value $harnessEndpoint | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to store harness-endpoint in Key Vault '$kvName'." }

    $resolvedModelDeploymentName = ""
    if ($outputs -and $outputs.PSObject.Properties.Name -contains "model_deployment_name") {
        $resolvedModelDeploymentName = [string]$outputs.model_deployment_name.value
    }
    if ([string]::IsNullOrWhiteSpace($resolvedModelDeploymentName)) { throw "Terraform output 'model_deployment_name' is empty." }
    az keyvault secret set --vault-name $kvName --name "harness-model-deployment" --value $resolvedModelDeploymentName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to store harness-model-deployment in Key Vault '$kvName'." }

    $foundryProjectName = ""
    if ($outputs -and $outputs.PSObject.Properties.Name -contains "foundry_project_name") {
        $foundryProjectName = [string]$outputs.foundry_project_name.value
    }
    if ([string]::IsNullOrWhiteSpace($foundryProjectName)) { throw "Terraform output 'foundry_project_name' is empty." }
    az keyvault secret set --vault-name $kvName --name "foundry-project-name" --value $foundryProjectName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to store foundry-project-name in Key Vault '$kvName'." }

    $foundryProjectId = ""
    if ($outputs -and $outputs.PSObject.Properties.Name -contains "foundry_project_id") {
        $foundryProjectId = [string]$outputs.foundry_project_id.value
    }
    if ([string]::IsNullOrWhiteSpace($foundryProjectId)) { throw "Terraform output 'foundry_project_id' is empty." }
    az keyvault secret set --vault-name $kvName --name "foundry-project-id" --value $foundryProjectId | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to store foundry-project-id in Key Vault '$kvName'." }

    $storageConnectionString = ""
    if ($outputs -and $outputs.PSObject.Properties.Name -contains "storage_connection_string") {
        $storageConnectionString = [string]$outputs.storage_connection_string.value
    }
    if ([string]::IsNullOrWhiteSpace($storageConnectionString)) { throw "Terraform output 'storage_connection_string' is empty." }

    Set-GitHubSecretIfValue -Name "AZURE_HARNESS_API_KEY" -Value $harnessApiKey
    Set-GitHubSecretIfValue -Name "AZURE_HARNESS_ENDPOINT" -Value $harnessEndpoint
    Set-GitHubSecretIfValue -Name "AZURE_HARNESS_MODEL_DEPLOYMENT" -Value $resolvedModelDeploymentName
    Set-GitHubSecretIfValue -Name "AZURE_FOUNDRY_PROJECT_NAME" -Value $foundryProjectName
    Set-GitHubSecretIfValue -Name "AZURE_FOUNDRY_PROJECT_ID" -Value $foundryProjectId
    Set-GitHubSecretIfValue -Name "AZURE_STORAGE_CONNECTION_STRING" -Value $storageConnectionString
    Set-GitHubSecretIfValue -Name "AZURE_KEYVAULT_NAME" -Value $kvName

    if ($SetLocalUserEnvironment) {
        [Environment]::SetEnvironmentVariable("AZURE_HARNESS_API_KEY", $harnessApiKey, "User")
        [Environment]::SetEnvironmentVariable("AZURE_HARNESS_ENDPOINT", $harnessEndpoint, "User")
        [Environment]::SetEnvironmentVariable("AZURE_HARNESS_MODEL_DEPLOYMENT", $resolvedModelDeploymentName, "User")
        [Environment]::SetEnvironmentVariable("AZURE_FOUNDRY_PROJECT_NAME", $foundryProjectName, "User")
        [Environment]::SetEnvironmentVariable("AZURE_FOUNDRY_PROJECT_ID", $foundryProjectId, "User")
        Write-Host "Set user environment variables: AZURE_HARNESS_API_KEY, AZURE_HARNESS_ENDPOINT, AZURE_HARNESS_MODEL_DEPLOYMENT, AZURE_FOUNDRY_PROJECT_NAME, AZURE_FOUNDRY_PROJECT_ID"
    }

    $existing = gh secret list --repo $GitHubRepo --json name --jq ".[].name"
    foreach ($n in "AZURE_HARNESS_API_KEY", "AZURE_HARNESS_ENDPOINT", "AZURE_HARNESS_MODEL_DEPLOYMENT", "AZURE_FOUNDRY_PROJECT_NAME", "AZURE_FOUNDRY_PROJECT_ID", "AZURE_STORAGE_CONNECTION_STRING", "AZURE_KEYVAULT_NAME") {
        if ($existing -notcontains $n) { throw "GitHub secret '$n' was not found after setting." }
    }
    Write-Host "Harness deployment complete; all GitHub secrets verified."
}
