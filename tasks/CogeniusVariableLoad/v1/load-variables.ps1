<#
.SYNOPSIS
    Loads variables from one or more JSON files (created by the Variable Save task) and sets them as
    pipeline variables.
.DESCRIPTION
    Cross-platform (Windows PowerShell 5.1 and PowerShell 7+ on Windows, Linux and macOS).
    Has no dependency on the VstsTaskSdk; logging uses Azure Pipelines ##vso logging commands.
#>
[CmdletBinding()]
param(
    # Text file containing one JSON file path per line.
    [Parameter(Mandatory = $true, ParameterSetName = 'List')]
    [string] $FileListPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
    [string[]] $Path
)

$ErrorActionPreference = 'Stop'

function Write-PipelineError([string] $Message) {
    Write-Host "##vso[task.logissue type=error]$Message"
}

function ConvertTo-CommandData([string] $Value) {
    if ($null -eq $Value) { return '' }
    return $Value.Replace('%', '%AZP25').Replace("`r", '%0D').Replace("`n", '%0A')
}

function ConvertTo-CommandProperty([string] $Value) {
    return (ConvertTo-CommandData $Value).Replace(';', '%3B').Replace(']', '%5D')
}

if ($PSCmdlet.ParameterSetName -eq 'List') {
    $Path = @(Get-Content -LiteralPath $FileListPath | Where-Object { $_.Trim() })
}

$files = @($Path | Where-Object { $_ })
Write-Host "Found $($files.Count) file(s) to load"

if ($files.Count -eq 0) {
    Write-PipelineError "There were no files found. You must specify at least one file to load."
    exit 1
}

foreach ($file in $files) {
    Write-Host "Loading $file"
    try {
        $content = Get-Content -LiteralPath $file -Raw
        $results = @()
        if ($content -and $content.Trim()) {
            # Wrap in @() and unroll so a single object and an array are handled the same way.
            $results = @(($content | ConvertFrom-Json) | ForEach-Object { $_ })
        }

        $results = @($results | Where-Object { $_ -and $_.Name })
        if ($results.Count -eq 0) {
            Write-Host "No variables were found in $file"
            continue
        }

        foreach ($result in $results) {
            Write-Host "  $($result.Name)"
            $name = ConvertTo-CommandProperty ([string]$result.Name)
            $value = ConvertTo-CommandData ([string]$result.Value)
            Write-Host "##vso[task.setvariable variable=$name]$value"
        }
    }
    catch {
        Write-PipelineError "Failed to load variables from '$file': $($_.Exception.Message)"
        exit 1
    }
}

exit 0
