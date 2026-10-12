[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9-]+$')]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$GitHubRepo,

    [string]$LogPath = (Join-Path $PSScriptRoot ("logs\003ConfigureBYOK-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)

$ErrorActionPreference = "Stop"

function Write-CommandLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"), $Message
    Add-Content -LiteralPath $LogPath -Value $line
    Write-Host $Message
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$InputText,
        [switch]$HasSensitiveInput
    )

    $safeCommand = "$Executable $($Arguments -join ' ')"
    if ($HasSensitiveInput) {
        Write-CommandLog "COMMAND: $safeCommand <secret via stdin>"
    }
    else {
        Write-CommandLog "COMMAND: $safeCommand"
    }

    $command = Get-Command $Executable -ErrorAction Stop
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $command.Source
    $quotedArguments = foreach ($argument in $Arguments) {
        if ($argument.Contains('"')) {
            '"' + $argument.Replace('"', '\"') + '"'
        }
        elseif ($argument -match '\s') {
            '"' + $argument + '"'
        }
        else {
            $argument
        }
    }
    $processInfo.Arguments = $quotedArguments -join " "
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    [void]$process.Start()

    if ($null -ne $InputText) {
        $process.StandardInput.Write($InputText)
    }
    $process.StandardInput.Close()

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.Result
    $stderrTask.Result | Out-Null
    $exitCode = $process.ExitCode
    $process.Dispose()

    if ($exitCode -ne 0) {
        Write-CommandLog "FAILED (exit $exitCode): $safeCommand"
        throw "A required command failed. See '$LogPath' for the redacted command log."
    }

    return $stdout.Trim()
}

$logDirectory = Split-Path -Parent $LogPath
if (-not (Test-Path -LiteralPath $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

Write-CommandLog "Starting protected Foundry Actions environment setup for '$GitHubRepo'."
Write-CommandLog "Secret values and command output are never written to this log."

$environmentName = "foundry-byok"
$environmentPath = "repos/$GitHubRepo/environments/$environmentName"
$reviewersConfigured = Invoke-LoggedCommand -Executable "gh" -Arguments @(
    "api", $environmentPath, "--jq", ".protection_rules | any(.type == `"required_reviewers`")"
)
if ($reviewersConfigured -ne "true") {
    throw "GitHub environment '$environmentName' must exist and have required reviewers configured before secrets are copied."
}

$secrets = @(
    @{ KeyVaultName = "harness-api-key"; GitHubName = "AZURE_HARNESS_API_KEY" },
    @{ KeyVaultName = "harness-endpoint"; GitHubName = "AZURE_HARNESS_ENDPOINT" },
    @{ KeyVaultName = "harness-model-deployment"; GitHubName = "AZURE_HARNESS_MODEL_DEPLOYMENT" }
)

foreach ($secret in $secrets) {
    $value = Invoke-LoggedCommand -Executable "az" -Arguments @(
        "keyvault", "secret", "show",
        "--vault-name", $KeyVaultName,
        "--name", $secret.KeyVaultName,
        "--query", "value",
        "-o", "tsv"
    )
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Key Vault secret '$($secret.KeyVaultName)' is empty."
    }

    Invoke-LoggedCommand -Executable "gh" -Arguments @(
        "secret", "set", $secret.GitHubName,
        "--env", $environmentName,
        "--repo", $GitHubRepo
    ) -InputText $value -HasSensitiveInput | Out-Null
    Write-CommandLog "Configured environment secret '$($secret.GitHubName)'."
    Remove-Variable value
}

$configuredNames = Invoke-LoggedCommand -Executable "gh" -Arguments @(
    "secret", "list",
    "--env", $environmentName,
    "--repo", $GitHubRepo,
    "--json", "name",
    "--jq", ".[].name"
)
foreach ($secret in $secrets) {
    if ($configuredNames -notcontains $secret.GitHubName) {
        throw "GitHub environment secret '$($secret.GitHubName)' was not found after configuration."
    }
}

Write-CommandLog "Foundry smoke-test secrets configured and verified by name only."
