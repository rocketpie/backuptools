#Requires -Version 7
[CmdletBinding()]
Param(
    [string]$BackupsetPath
)

$ErrorActionPreference = 'Stop'

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

$thisFileName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
$thisFileVersion = "1.6"
Set-Variable -Name "ThisFileName" -Value $thisFileName -Scope Script
Set-Variable -Name "ThisFileVersion" -Value $thisFileVersion -Scope Script
"$($thisFileName) $($thisFileVersion)"

function Main {
    Param(
        [string]$BackupsetPath
    )

    # literal output ouf restic check when repo is ok.
    $RESTIC_OUTPUT_NO_ERRORS = 'no errors were found'
    $RESTIC_OUTPUT_MATCH_SUCCESS = 'snapshot (\w{8}) saved'
    $RESTIC_OUTPUT_MATCH_FORGOT_SNAPSHOTS = 'remove (\d+) snapshots:'


    $config = ReadConfigFile
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


    $backupsetName = Split-Path -Leaf $BackupsetPath
    $sourceNameMatch = [regex]::Match($backupsetName, '^(.*)-([\d-]{10})T([\d-]{5})$')
    if (-not $sourceNameMatch.Success) {
        Write-Error "cannot find sourceName from backupSetName '$($backupsetName)'"
    }
    $sourceName = $sourceNameMatch.Groups[1].Value

    $backupLocation = Join-Path (Split-Path $BackupsetPath) $sourceName
    if (Test-Path -Path $backupLocation) {
        Write-Error "[ERROR] backup location '$($backupLocation)' is still present (LastWriteTime: '$((Get-Item -Path $backupLocation).LastWriteTime)')"
        return
    }


    "testing command 'restic'..."
    if ($null -eq (Get-Command 'restic' -ErrorAction SilentlyContinue)) {
        Write-Error "[ERROR] cannot find command 'restic'"
        return
    }

    $env:RESTIC_REPOSITORY = $config.ResticRepositoryPath
    $env:RESTIC_PASSWORD = $config.ResticPassword

    # https://restic.readthedocs.io/en/stable/075_scripting.html
    "calling 'restic cat config'..."
    $outputSaysNoErrorsFound = $false
    & restic cat config
    if ($LASTEXITCODE -ne 0) {
        Write-Error "ResticBackup.ps1: cannot continue unless 'restic cat config' exits with code 0"
        return
    }

    "calling 'restic check'..."
    $outputSaysNoErrorsFound = $false
    & restic check | ForEach-Object { $_
        if ("$($_)".ToLower().Trim() -eq $RESTIC_OUTPUT_NO_ERRORS) {
            $outputSaysNoErrorsFound = $true
        }
    }
    if (-not $outputSaysNoErrorsFound) {
        Write-Error "ResticBackup.ps1: cannot continue unless 'restic check' returns '$($RESTIC_OUTPUT_NO_ERRORS)'"
        return
    }


    Move-Item $BackupsetPath $backupLocation

    "calling `"restic backup '$backupLocation'`"..."
    $outputSaysSnapshotSaved = $false
    & restic backup $backupLocation | ForEach-Object { $_
        if ([regex]::IsMatch("$_", $RESTIC_OUTPUT_MATCH_SUCCESS)) {
            $outputSaysSnapshotSaved = $true
        }
    }
    if (-not $outputSaysSnapshotSaved) {
        Write-Error "ResticBackup.ps1: cannot continue unless 'restic backup' returns '$RESTIC_OUTPUT_MATCH_SUCCESS'"
        return
    }

    "removing '$backupLocation'..."
    Remove-Item -Path $backupLocation -Recurse -Force


    if (($null -ne $config.ResticForgetOptions) -and ($config.ResticForgetOptions.Count -gt 0)) {
        $forgetParams = $config.ResticForgetOptions
        "calling `"restic forget --prune $((JoinParameterString $forgetParams))`"..."
        $forgottenSnapshotCount = 0
        & restic forget @forgetParams | ForEach-Object { $_
            $outputMatch = [regex]::Match($_, $RESTIC_OUTPUT_MATCH_FORGOT_SNAPSHOTS)
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
    foreach ($param in $resticParams) {
        if ($first) { $first = $false; }
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


# read the .json config file
function ReadConfigFile {
    # Workaround: MyInvocation.MyCommand.Definition only contains the path to this file when it's not dot-loaded
    $configFile = Join-Path $PSScriptRoot "$(Get-Variable -Name "ThisFileName" -ValueOnly).json"
    $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
    Write-Debug "using config from file '$($configFile)':`n$($config | ConvertTo-Json)"
    return $config
}

Main -BackupsetPath $BackupsetPath