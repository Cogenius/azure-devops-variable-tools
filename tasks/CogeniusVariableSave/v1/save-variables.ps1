<#
.SYNOPSIS
    Saves environment variables matching one or more prefixes to meta-<prefix>.json files.
.DESCRIPTION
    Cross-platform (Windows PowerShell 5.1 and PowerShell 7+ on Windows, Linux and macOS).
    Has no dependency on the VstsTaskSdk; logging uses Azure Pipelines ##vso logging commands.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Prefixes,

    [Parameter(Mandatory = $true)]
    [string] $OutPath
)

$ErrorActionPreference = 'Stop'

function Write-PipelineError([string] $Message) {
    Write-Host "##vso[task.logissue type=error]$Message"
}

$prefixList = @($Prefixes -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($prefixList.Count -eq 0) {
    Write-PipelineError "No prefixes were specified."
    exit 1
}

Write-Verbose "Prefixes: $($prefixList -join ', ')"
Write-Verbose "Output path: $OutPath"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$allVariables = [Environment]::GetEnvironmentVariables()

try {
    foreach ($prefix in $prefixList) {
        Write-Host "Saving variables for prefix '$prefix'"

        # Agents expose variables upper-cased (e.g. BUILD_BUILDID). Match case-insensitively so that
        # behaviour is identical on Windows (case-insensitive env) and Linux/macOS (case-sensitive env).
        $seen = @{}
        $variables = @(
            $allVariables.Keys |
                Where-Object { $_ -like "$prefix*" } |
                Sort-Object |
                Where-Object {
                    $key = $_.ToUpperInvariant()
                    if ($seen.ContainsKey($key)) { $false } else { $seen[$key] = $true; $true }
                } |
                ForEach-Object { [pscustomobject]@{ Name = $_; Value = [string]$allVariables[$_] } }
        )

        if ($variables.Count -eq 0) {
            Write-Host "No variable names matched the prefix '$prefix'"
            continue
        }

        $variables | ForEach-Object { Write-Host "  $($_.Name)" }

        if (-not (Test-Path -LiteralPath $OutPath -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $OutPath | Out-Null
        }

        $path = Join-Path -Path $OutPath -ChildPath "meta-$($prefix.ToLowerInvariant()).json"
        $json = ConvertTo-Json -InputObject $variables -Depth 2
        [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
        Write-Host "Saved $($variables.Count) variable(s) to $path"
    }
}
catch {
    Write-PipelineError "Failed to save variables: $($_.Exception.Message)"
    exit 1
}

exit 0
