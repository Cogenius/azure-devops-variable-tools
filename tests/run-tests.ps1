#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the Pester tests. Installs Pester 5 for the current user if it is not available.
#>
[CmdletBinding()]
param(
    [string] $OutputFile
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.5.0' })) {
    Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module Pester -MinimumVersion 5.5.0

$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
if ($OutputFile) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = $OutputFile
}

Invoke-Pester -Configuration $config
