<#
.EXAMPLE
    .\infra\003ConfigureBYOK.ps1 -Organization "OzBobDev"

Checks GitHub CLI authentication and guides an organization owner through
configuring Copilot custom models. Provider keys must be entered in GitHub
settings; this script never accepts or logs keys.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9-]+$')]
    [string]$Organization,

    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path ([System.IO.Path]::GetTempPath()) "003ConfigureBYOK-$Organization.log"
}

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)

    $entry = "{0} {1}" -f [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"), $Message
    Add-Content -LiteralPath $LogPath -Value $entry -Encoding utf8
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $commandLine = "$Executable $($Arguments -join ' ')"
    Write-Log "COMMAND: $commandLine"

    $output = & $Executable @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Host ([string]$line)
    }

    Write-Log "EXIT CODE: $exitCode"
    if ($exitCode -ne 0) {
        throw "Command failed with exit code $exitCode. See log: $LogPath"
    }
}

Write-Log "Starting Copilot BYOK setup guidance for organization '$Organization'."

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Write-Log "ERROR: GitHub CLI (gh) is not installed or not on PATH."
    throw "Install GitHub CLI and authenticate with 'gh auth login' before running this script."
}

Invoke-LoggedCommand -Executable $gh.Source -Arguments @("auth", "status", "--hostname", "github.com")

$settingsUrl = "https://github.com/organizations/$Organization/settings/copilot"
Write-Host ""
Write-Host "Open Copilot settings for ${Organization}: $settingsUrl"
Write-Host "As an organization owner, open Configure custom models and add the provider key and model there."
Write-Host "If the organization belongs to an enterprise, the enterprise owner may need to enable custom models or grant organization access first."
Write-Host "GitHub currently documents enterprise BYOK models for Copilot Chat, Copilot CLI, and IDEs."
Write-Host "Cloud Agent supports model selection in documented entrypoints, but its model documentation does not list BYOK custom models as supported."
Write-Host "Verify custom-model availability in the Cloud Agent model picker and with your admin before relying on it."
Write-Host "Never put provider keys in this script, command-line arguments, or this repository."
Write-Host ""
Write-Host "Command log: $LogPath"
Write-Log "Displayed manual setup guidance; no provider key or model setting was changed."
