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
        [string]$OrchestratorImage = "ghcr.io/ozbobdev/orchestrator:latest",
        [string]$BddAgentImage = "ghcr.io/ozbobdev/bdd-agent:latest",
        [string]$TerraformStateKey = "sdlcdocs.tfstate"
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

    Write-Host "Logging into Azure..."
    az login --tenant $TenantId | Out-Null
    az account set --subscription $SubscriptionId

    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    $tfDir = Join-Path $repoRoot "azure-harness/infra"

    Push-Location $tfDir
    try {
        terraform init `
            -backend-config="resource_group_name=$TerraformBackendResourceGroup" `
            -backend-config="storage_account_name=$TerraformBackendStorageAccount" `
            -backend-config="container_name=$TerraformBackendContainer" `
            -backend-config="key=$TerraformStateKey"

        terraform init -input=false | Out-Null

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
                    -var="orchestrator_image=$OrchestratorImage" `
                    -var="bdd_agent_image=$BddAgentImage" `
                    azurerm_resource_group.agents "/subscriptions/$SubscriptionId/resourceGroups/$HarnessResourceGroup"
                if ($LASTEXITCODE -ne 0) { throw "terraform import of resource group failed." }
            }
        }

        terraform plan `
            -var="subscription_id=$SubscriptionId" `
            -var="tenant_id=$TenantId" `
            -var="resource_group_name=$HarnessResourceGroup" `
            -var="location=$Location" `
            -var="orchestrator_image=$OrchestratorImage" `
            -var="bdd_agent_image=$BddAgentImage" `
            -out=tfplan

        terraform apply -auto-approve tfplan

        $outputsJson = terraform output -json
        $outputs = $outputsJson | ConvertFrom-Json
    }
    finally {
        Pop-Location
    }

    $kvName = "kv-sdlcdocs-harness"
    $kvExists = az keyvault list --resource-group $HarnessResourceGroup --query "[?name=='$kvName'] | length(@)" -o tsv
    if ($kvExists -eq "0") {
        Write-Host "Creating Key Vault '$kvName'..."
        az keyvault create --name $kvName --resource-group $HarnessResourceGroup --location $Location --enable-rbac-authorization true | Out-Null
    }

    # Ensure the current caller can write secrets (role assignment may be missing on an existing vault)
    $kvId = az keyvault show --name $kvName --resource-group $HarnessResourceGroup --query id -o tsv
    $callerObjectId = az ad signed-in-user show --query id -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($callerObjectId)) {
        $callerObjectId = az account show --query user.name -o tsv
    }
    $roleCount = az role assignment list --assignee $callerObjectId --scope $kvId --role "Key Vault Secrets Officer" --query "length(@)" -o tsv
    if ($roleCount -eq "0") {
        Write-Host "Assigning 'Key Vault Secrets Officer' on '$kvName'..."
        az role assignment create --assignee $callerObjectId --role "Key Vault Secrets Officer" --scope $kvId | Out-Null
        Write-Host "Waiting for role assignment propagation..."
        Start-Sleep -Seconds 30
    }

    $harnessApiKey = ""
    if ($outputs -and $outputs.PSObject.Properties.Name -contains "harness_api_key") {
        $harnessApiKey = [string]$outputs.harness_api_key.value
    }

    if ([string]::IsNullOrWhiteSpace($harnessApiKey)) {
        $harnessApiKey = [guid]::NewGuid().ToString("N")
        az keyvault secret set --vault-name $kvName --name "harness-api-key" --value $harnessApiKey | Out-Null
    }

    $storageConnectionString = ""
    if ($outputs -and $outputs.PSObject.Properties.Name -contains "storage_connection_string") {
        $storageConnectionString = [string]$outputs.storage_connection_string.value
    }

    if ([string]::IsNullOrWhiteSpace($storageConnectionString)) {
        $storageConnectionString = az storage account show-connection-string `
            --name $TerraformBackendStorageAccount `
            --resource-group $TerraformBackendResourceGroup `
            --query connectionString -o tsv
    }

    Set-GitHubSecretIfValue -Name "AZURE_HARNESS_API_KEY" -Value $harnessApiKey
    Set-GitHubSecretIfValue -Name "AZURE_STORAGE_CONNECTION_STRING" -Value $storageConnectionString
    Set-GitHubSecretIfValue -Name "AZURE_KEYVAULT_NAME" -Value $kvName

    Write-Host "Harness deployment and optional secret setup complete."
}
