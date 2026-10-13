<#
.EXAMPLE
    . .\infra\002SetupAzure.ps1
    Invoke-SdlcDocsHarnessDeployment -TenantId $tenant -SubscriptionId $subscription -Location "australiaeast" -GitHubRepo "OzBob/AudioDownloadEpisode"
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

        [string]$HarnessResourceGroup = "rg-sdlcdocs-harness-aue",
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
        [string]$TerraformStateKey = "sdlcdocs-prompt-agent.tfstate",

        # Orchestrator (Container Apps) + dispatch identity. Off by default so existing runs are unchanged.
        [switch]$DeployOrchestrator,
        [string]$ContainerRegistryName = "acrsdlcdocsharness001",
        [string]$OrchestratorImageTag = (Get-Date -Format "yyyyMMddHHmmss"),
        [string]$GitHubAppId = "",
        [string]$GitHubAppInstallationId = "",
        [string]$DispatchEnvironment = "azure-harness-dispatch",
        # Opt-in: create the GitHub environment and set its secrets/variables with gh. Default only prints the commands.
        [switch]$ConfigureGitHubEnvironment
    )

    function Ensure-EntraApp {
        param([string]$DisplayName)
        $id = az ad app list --display-name $DisplayName --query "[0].appId" -o tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($id)) {
            $id = az ad app create --display-name $DisplayName --sign-in-audience AzureADMyOrg --query appId -o tsv
            if ($LASTEXITCODE -ne 0) { throw "Failed to create app registration '$DisplayName'." }
        }
        $sp = az ad sp list --filter "appId eq '$id'" --query "[0].id" -o tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($sp)) {
            $sp = az ad sp create --id $id --query id -o tsv
            if ($LASTEXITCODE -ne 0) { throw "Failed to create service principal for '$DisplayName'." }
        }
        return @{ AppId = $id; SpId = $sp }
    }

    # Creates the orchestrator API app (audience + 'Dispatch' role) and the dispatch app trusted via GitHub OIDC.
    function Initialize-DispatchIdentity {
        param([string]$Repo, [string]$Environment)
        $api = Ensure-EntraApp "sdlc-orchestrator-api"
        $audience = "api://$($api.AppId)"
        $roles = az ad app show --id $api.AppId --query "appRoles[?value=='Dispatch'].id | [0]" -o tsv
        if ([string]::IsNullOrWhiteSpace($roles)) {
            $roleId = [guid]::NewGuid().ToString()
            $manifest = @(@{ id = $roleId; allowedMemberTypes = @("Application"); displayName = "Dispatch"; description = "Dispatch work items to the SDLC orchestrator"; value = "Dispatch"; isEnabled = $true }) | ConvertTo-Json -Depth 5 -AsArray
            $tmp = New-TemporaryFile
            try {
                Set-Content -Path $tmp -Value $manifest -Encoding utf8
                az ad app update --id $api.AppId --identifier-uris $audience --app-roles "@$tmp" | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Failed to configure the Dispatch app role." }
            }
            finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
        }
        else {
            $roleId = $roles
            az ad app update --id $api.AppId --identifier-uris $audience | Out-Null
        }

        $dispatch = Ensure-EntraApp "sdlc-dispatch"
        $subject = "repo:${Repo}:environment:${Environment}"
        $existing = az ad app federated-credential list --id $dispatch.AppId --query "[?subject=='$subject'].name | [0]" -o tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($existing)) {
            $cred = @{ name = "github-$Environment"; issuer = "https://token.actions.githubusercontent.com"; subject = $subject; audiences = @("api://AzureADTokenExchange") } | ConvertTo-Json -Compress
            $tmp = New-TemporaryFile
            try {
                Set-Content -Path $tmp -Value $cred -Encoding utf8
                az ad app federated-credential create --id $dispatch.AppId --parameters "@$tmp" | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Failed to create the federated credential." }
            }
            finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
        }

        $assigned = az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($api.SpId)/appRoleAssignedTo" --query "value[?principalId=='$($dispatch.SpId)' && appRoleId=='$roleId'].id | [0]" -o tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($assigned)) {
            $body = @{ principalId = $dispatch.SpId; resourceId = $api.SpId; appRoleId = $roleId } | ConvertTo-Json -Compress
            $tmp = New-TemporaryFile
            try {
                Set-Content -Path $tmp -Value $body -Encoding utf8
                az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($dispatch.SpId)/appRoleAssignments" --headers "Content-Type=application/json" --body "@$tmp" | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Failed to assign the Dispatch role (needs Application.ReadWrite.All / admin consent rights)." }
            }
            finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
        }
        return @{ Audience = $audience; DispatchClientId = $dispatch.AppId }
    }

    function Ensure-Command {
        param([string]$Name)
        if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
            throw "Required command '$Name' is not installed or not on PATH."
        }
    }

    Ensure-Command az
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

        $planVars = @(
            "-var=subscription_id=$SubscriptionId",
            "-var=tenant_id=$TenantId",
            "-var=resource_group_name=$HarnessResourceGroup",
            "-var=location=$Location",
            "-var=ai_services_account_name=$AiServicesAccountName",
            "-var=model_deployment_name=$ModelDeploymentName",
            "-var=model_name=$ModelName",
            "-var=model_version=$ModelVersion",
            "-var=model_capacity=$ModelCapacity",
            "-var=model_sku_name=$ModelSkuName",
            "-var=container_registry_name=$ContainerRegistryName"
        )
        $dispatchIdentity = $null

        if ($DeployOrchestrator) {
            if ([string]::IsNullOrWhiteSpace($GitHubAppId) -or [string]::IsNullOrWhiteSpace($GitHubAppInstallationId)) {
                Write-Warning "GitHubAppId/GitHubAppInstallationId not provided: the orchestrator will start but cannot comment, label or open PRs (/work-items returns 503)."
            }
            Write-Host "Configuring Entra apps and GitHub OIDC trust for '$GitHubRepo' environment '$DispatchEnvironment'..."
            $dispatchIdentity = Initialize-DispatchIdentity -Repo $GitHubRepo -Environment $DispatchEnvironment

            # The App private key lives in Key Vault (secret 'github-app-private-key'); 'unset' keeps the app unconfigured.
            $appKey = "unset"
            $kvPre = "kv-sdlcdocs-$($SubscriptionId.Substring(0,8))"
            $fromKv = az keyvault secret show --vault-name $kvPre --name "github-app-private-key" --query value -o tsv 2>$null
            if (-not [string]::IsNullOrWhiteSpace($fromKv)) { $appKey = $fromKv }
            $env:TF_VAR_github_app_private_key = $appKey

            # Build the image first: create only the registry, build in ACR, then deploy the app.
            terraform apply -auto-approve -input=false -target=azurerm_container_registry.orchestrator @planVars
            if ($LASTEXITCODE -ne 0) { throw "terraform apply of the container registry failed." }
            $acrLogin = az acr show --name $ContainerRegistryName --query loginServer -o tsv
            $image = "$acrLogin/orchestrator:$OrchestratorImageTag"
            az acr build --registry $ContainerRegistryName --image "orchestrator:$OrchestratorImageTag" --file orchestrator/Dockerfile (Join-Path $repoRoot "azure-harness")
            if ($LASTEXITCODE -ne 0) { throw "az acr build failed." }

            $planVars += @(
                "-var=orchestrator_image=$image",
                "-var=orchestrator_audience=$($dispatchIdentity.Audience)",
                "-var=orchestrator_allowed_client_ids=[`"$($dispatchIdentity.DispatchClientId)`"]",
                "-var=orchestrator_allowed_repos=[`"$GitHubRepo`"]",
                "-var=github_app_id=$GitHubAppId",
                "-var=github_app_installation_id=$GitHubAppInstallationId"
            )
        }

        terraform plan @planVars -out=tfplan
        if ($LASTEXITCODE -ne 0) { throw "terraform plan failed." }

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
    if ($outputs -and $outputs.PSObject.Properties.Name -contains "model_deployment_names") {
        $allDeployments = ($outputs.model_deployment_names.value -join ",")
        az keyvault secret set --vault-name $kvName --name "harness-model-deployments" --value $allDeployments | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to store harness-model-deployments in Key Vault '$kvName'." }
        if ($SetLocalUserEnvironment) {
            [Environment]::SetEnvironmentVariable("AZURE_HARNESS_MODEL_DEPLOYMENTS", $allDeployments, "User")
        }
    }

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

    if ($SetLocalUserEnvironment) {
        [Environment]::SetEnvironmentVariable("AZURE_HARNESS_API_KEY", $harnessApiKey, "User")
        [Environment]::SetEnvironmentVariable("AZURE_HARNESS_ENDPOINT", $harnessEndpoint, "User")
        [Environment]::SetEnvironmentVariable("AZURE_HARNESS_MODEL_DEPLOYMENT", $resolvedModelDeploymentName, "User")
        [Environment]::SetEnvironmentVariable("AZURE_FOUNDRY_PROJECT_NAME", $foundryProjectName, "User")
        [Environment]::SetEnvironmentVariable("AZURE_FOUNDRY_PROJECT_ID", $foundryProjectId, "User")
        Write-Host "Set user environment variables: AZURE_HARNESS_API_KEY, AZURE_HARNESS_ENDPOINT, AZURE_HARNESS_MODEL_DEPLOYMENT, AZURE_FOUNDRY_PROJECT_NAME, AZURE_FOUNDRY_PROJECT_ID"
    }

    # Orchestrator / monitoring outputs: stored in Key Vault and user environment variables
    $stored = [ordered]@{}
    foreach ($pair in @(
            @{ Output = "orchestrator_url"; Secret = "orchestrator-url"; Env = "ORCHESTRATOR_URL" },
            @{ Output = "appinsights_connection_string"; Secret = "appinsights-connection-string"; Env = "APPLICATIONINSIGHTS_CONNECTION_STRING" },
            @{ Output = "appinsights_name"; Secret = "appinsights-name"; Env = "AZURE_APPINSIGHTS_NAME" },
            @{ Output = "container_registry_login_server"; Secret = "container-registry-login-server"; Env = "AZURE_CONTAINER_REGISTRY" }
        )) {
        if ($outputs -and $outputs.PSObject.Properties.Name -contains $pair.Output) {
            $v = [string]$outputs.($pair.Output).value
            if (-not [string]::IsNullOrWhiteSpace($v)) { $stored[$pair.Secret] = @{ Value = $v; Env = $pair.Env } }
        }
    }
    if ($dispatchIdentity) {
        $stored["orchestrator-audience"] = @{ Value = $dispatchIdentity.Audience; Env = "ORCHESTRATOR_AUDIENCE" }
        $stored["dispatch-client-id"] = @{ Value = $dispatchIdentity.DispatchClientId; Env = "AZURE_DISPATCH_CLIENT_ID" }
    }
    foreach ($name in $stored.Keys) {
        az keyvault secret set --vault-name $kvName --name $name --value $stored[$name].Value | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to store $name in Key Vault '$kvName'." }
        if ($SetLocalUserEnvironment) { [Environment]::SetEnvironmentVariable($stored[$name].Env, $stored[$name].Value, "User") }
    }
    if ($stored.Count -gt 0) {
        Write-Host "Stored in Key Vault '$kvName' (and user env vars): $($stored.Keys -join ', ')"
    }

    if ($dispatchIdentity -and $stored.Contains("orchestrator-url")) {
        $orchestratorUrl = $stored["orchestrator-url"].Value
        $cmds = @(
            "gh api -X PUT repos/$GitHubRepo/environments/$DispatchEnvironment",
            "gh secret set AZURE_CLIENT_ID --env $DispatchEnvironment --repo $GitHubRepo --body $($dispatchIdentity.DispatchClientId)",
            "gh secret set AZURE_TENANT_ID --env $DispatchEnvironment --repo $GitHubRepo --body $TenantId",
            "gh variable set ORCHESTRATOR_URL --env $DispatchEnvironment --repo $GitHubRepo --body $orchestratorUrl",
            "gh variable set ORCHESTRATOR_AUDIENCE --env $DispatchEnvironment --repo $GitHubRepo --body $($dispatchIdentity.Audience)"
        )
        if ($ConfigureGitHubEnvironment) {
            Ensure-Command gh
            foreach ($c in $cmds) {
                Invoke-Expression $c | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Command failed: $c" }
            }
            Write-Host "Configured GitHub environment '$DispatchEnvironment' on '$GitHubRepo'. Add required reviewers in the repo settings."
        }
        else {
            Write-Host "To configure the GitHub environment '$DispatchEnvironment' (none of this was changed), run:"
            $cmds | ForEach-Object { Write-Host "  $_" }
        }
    }

    if ($ConfigureGitHubEnvironment -and $dispatchIdentity) {
        Write-Host "Harness deployment complete. GitHub environment '$DispatchEnvironment' was configured for '$GitHubRepo'; no Agents secrets were changed."
    }
    else {
        Write-Host "Harness deployment complete. No GitHub Actions or Agents secrets were changed for '$GitHubRepo'."
    }
    Write-Host "Use 003ConfigureBYOK.ps1 only when configuring the protected foundry-byok Actions environment."
}
