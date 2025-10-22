#Requires -Version 7
[CmdletBinding()]
Param(
    # read the configuration file and set the restic environment variables
    [Parameter(Mandatory, ParameterSetName = "SetResticEnvironmentVariables")]
    [switch]
    $SetResticEnvironmentVariables,

    # create a snapshot of a path **And then remove that path**
    [Parameter(Mandatory, ParameterSetName = "RunBackupset")]
    [string]
    $BackupsetPath,

    # create a snapshot of a path **and then leave it**
    [Parameter(Mandatory, ParameterSetName = "RunHosted")]
    [string]
    $HostedPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

$thisFileName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
$thisFileVersion = "1.9"
Set-Variable -Name "ThisFileName" -Value $thisFileName -Scope Script
Set-Variable -Name "ThisFileVersion" -Value $thisFileVersion -Scope Script
"$($thisFileName) $($thisFileVersion)"

function Get-Constants {
    return [PSCustomObject]@{
        # literal output ouf restic check when repo is ok.
        RESTIC_OUTPUT_NO_ERRORS              = "no errors were found"
        RESTIC_OUTPUT_MATCH_SUCCESS          = "snapshot (\w{8}) saved"
        RESTIC_OUTPUT_MATCH_FORGOT_SNAPSHOTS = "remove (\d+) snapshots:"
    }
}


function Invoke-Backupset {
    Param(
        # eg. /media/backups/backupsets/immich-2025-10-15T02-00-00
        [string]$Path
    )
    $const = Get-Constants
    $config = Read-ConfigFile
    Test-Restic

    # eg. immich-2025-10-15T02-00-00
    $backupsetName = Split-Path -Leaf $Path
    $sourceNameMatch = [regex]::Match($backupsetName, '^(.*)-([\d-]{10})T([\d-]{5})$')
    if (-not $sourceNameMatch.Success) {
        Write-Error "cannot find sourceName from backupSetName '$($backupsetName)'"
    }
    # eg. paperless / immich / ...
    $sourceName = $sourceNameMatch.Groups[1].Value
        
    # eg. /media/backups/backupsets/immich
    $backupLocation = Join-Path (Split-Path $Path) $sourceName
    if (Test-Path -Path $backupLocation) {
        Write-Error "[ERROR] backupset '$($backupLocation)' is still present (LastWriteTime: '$((Get-Item -Path $backupLocation).LastWriteTime)')"
        return
    }

    Move-Item $Path $backupLocation

    "calling `"restic backup '$backupLocation'`"..."
    $outputSaysSnapshotSaved = $false
    & restic backup $backupLocation | ForEach-Object { $_
        if ([regex]::IsMatch("$_", $const.RESTIC_OUTPUT_MATCH_SUCCESS)) {
            $outputSaysSnapshotSaved = $true
        }
    }
    if (-not $outputSaysSnapshotSaved) {
        Write-Error "ResticBackup.ps1: cannot continue unless 'restic backup' returns '$const.RESTIC_OUTPUT_MATCH_SUCCESS'"
        return
    }

    "removing '$backupLocation'..."
    Remove-Item -Path $backupLocation -Recurse -Force

    if (($null -ne $config.ResticForgetOptions) -and ($config.ResticForgetOptions.Count -gt 0)) {
        $forgetParams = $config.ResticForgetOptions
        "calling `"restic forget --prune $((JoinParameterString $forgetParams))`"..."
        $forgottenSnapshotCount = 0
        & restic forget @forgetParams | ForEach-Object { $_
            $outputMatch = [regex]::Match($_, $const.RESTIC_OUTPUT_MATCH_FORGOT_SNAPSHOTS)
            if ($outputMatch.Success) {
                [int]::TryParse($outputMatch.Groups[1].Value, [ref]$forgottenSnapshotCount) | Out-Nulls
            }
        }

        if ($forgottenSnapshotCount -lt 1) {
            Write-Warning "ResticBackup.ps1: looks like restic didn't remove anything (?)"
        }
    }

    "Done."
    RunBackupSuccessCommand -Config $config
}

function Invoke-Hosted {
    Param(
        # eg. /media/backups/hosted/lc3win
        [string]$Path
    )
    $const = Get-Constants
    $config = Read-ConfigFile
    Test-Restic


    "calling `"restic backup '$($Path)'`"..."
    $outputSaysSnapshotSaved = $false
    & restic backup $Path | ForEach-Object { $_
        if ([regex]::IsMatch("$_", $const.RESTIC_OUTPUT_MATCH_SUCCESS)) {
            $outputSaysSnapshotSaved = $true
        }
    }
    if (-not $outputSaysSnapshotSaved) {
        Write-Error "ResticBackup.ps1: cannot continue unless 'restic backup' returns '$const.RESTIC_OUTPUT_MATCH_SUCCESS'"
        return
    }

    if (($null -ne $config.ResticForgetOptions) -and ($config.ResticForgetOptions.Count -gt 0)) {
        $forgetParams = $config.ResticForgetOptions
        "calling `"restic forget --prune $((JoinParameterString $forgetParams))`"..."
        $forgottenSnapshotCount = 0
        & restic forget @forgetParams | ForEach-Object { $_
            $outputMatch = [regex]::Match($_, $const.RESTIC_OUTPUT_MATCH_FORGOT_SNAPSHOTS)
            if ($outputMatch.Success) {
                [int]::TryParse($outputMatch.Groups[1].Value, [ref]$forgottenSnapshotCount) | Out-Nulls
            }
        }

        if ($forgottenSnapshotCount -lt 1) {
            Write-Warning "ResticBackup.ps1: looks like restic didn't remove anything (?)"
        }
    }

    "Done."
    RunBackupSuccessCommand -Config $config
}

function RunBackupSuccessCommand {
    Param(
        $Config
    )

    try {
        $command = $Config.BackupSuccessCommand
        if ([string]::IsNullOrWhiteSpace($command)) {
            "no BackupSuccessCommand configured"
            return
        }

        "[STARTED] RunBackupSuccessCommand"

        "invoking '$($command)'..."
        Invoke-Expression -Command $command

        "[COMPLETED] RunBackupSuccessCommand"
    }
    catch {
        "[ERROR] RunBackupSuccessCommand: $($_.Exception)"
    }
}


function JoinParameterString {
    param (
        [array]$Parameters
    )

    $paramsText = [System.Text.StringBuilder]::new()
    $first = $true
    foreach ($param in $Parameters) {
        if ($first) { $first = $false }
        else { $paramsText.Append(' ') }

        if ($param.ToString().Trim() -match '\s') {
            $paramsText.Append("'$($param)'")
        }
        else {
            $paramsText.Append($param)
        }
    }

    return $paramsText.ToString()
}

function Test-Restic {
    "testing command 'restic'..."
    if ($null -eq (Get-Command 'restic' -ErrorAction SilentlyContinue)) {
        Write-Error "[ERROR] cannot find command 'restic'"
        return
    }
    
    # https://restic.readthedocs.io/en/stable/075_scripting.html
    "calling 'restic cat config'..."
    $outputSaysNoErrorsFound = $false
    restic cat config

    "calling 'restic check'..."
    $outputSaysNoErrorsFound = $false
    "$(restic check)".Split([System.Environment]::NewLine) | ForEach-Object {
        $_
        if ("$($_)".ToLower().Trim() -eq $const.RESTIC_OUTPUT_NO_ERRORS) {
            $outputSaysNoErrorsFound = $true
        }
    }
    if (-not $outputSaysNoErrorsFound) {
        Write-Error "ResticBackup.ps1: cannot continue unless 'restic check' returns '$($const.RESTIC_OUTPUT_NO_ERRORS)'"
        return
    }
}

# read the .json config file
function Read-ConfigFile {
    # Workaround: MyInvocation.MyCommand.Definition only contains the path to this file when it's not dot-loaded
    $configFile = Join-Path $PSScriptRoot "$(Get-Variable -Name "ThisFileName" -ValueOnly).json"
    $schemaFile = Join-Path $PSScriptRoot "$(Get-Variable -Name "ThisFileName" -ValueOnly).schema.json"

    Write-Debug "testing config file schema..."
    Test-Json -LiteralPath $configFile -SchemaFile $schemaFile | Out-Null

    $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
    Write-Debug "using config from file '$($configFile)':`n$($config | ConvertTo-Json)"

    if ($config.ResticRepositoryPath -match '^/|[A-Z]:[/\\]') {
        Write-Debug "identified ResticRepositoryPath to be a local Path"
        if (-not (Test-Path -Path $config.ResticRepositoryPath -PathType Container)) {
            Write-Error "[ERROR] cannot find ResticRepositoryPath '$($config.ResticRepositoryPath)'"
            return
        }
    }
    else {
        Write-Warning "ATTENTION: unkown type of ResticRepositoryPath. Untested behaviour ahead!"
    }

    if ([string]::IsNullOrWhiteSpace($config.ResticPassword)) {
        Write-Error "[ERROR] empty ResticPassword '$($config.ResticRepositoryPath)'"
        return
    }

    # set restic environment variables
    $env:RESTIC_REPOSITORY = $config.ResticRepositoryPath
    $env:RESTIC_PASSWORD = $config.ResticPassword

    Set-Variable -Name "Config" -Value $config -Scope Script
    return $config # default pass-through
}

function Get-Config { return Get-Variable -Name "Config" -ValueOnly }



<#
##     ##    ###    #### ##    ##     ######     ###    ##       ##
###   ###   ## ##    ##  ###   ##    ##    ##   ## ##   ##       ##
#### ####  ##   ##   ##  ####  ##    ##        ##   ##  ##       ##
## ### ## ##     ##  ##  ## ## ##    ##       ##     ## ##       ##
##     ## #########  ##  ##  ####    ##       ######### ##       ##
##     ## ##     ##  ##  ##   ###    ##    ## ##     ## ##       ##
##     ## ##     ## #### ##    ##     ######  ##     ## ######## ########
#>

switch ($PSCmdlet.ParameterSetName) {
    SetResticEnvironmentVariables {
        Read-ConfigFile | Out-Null
    }

    RunBackupset {
        Invoke-Backupset -Path $BackupsetPath
    }

    RunHosted {
        Invoke-Hosted -Path $HostedPath
    }
}

