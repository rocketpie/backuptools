#Requires -Version 7
[CmdletBinding()]
Param(
)

$ErrorActionPreference = 'Stop'

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

$thisFileName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
Set-Variable -Name "ThisFileName" -Value $thisFileName -Scope Script
"$($thisFileName) 0.1"

function Main {

    $config = ReadConfigFile

    "Done."
    
    RunSyncSuccessCommand -Config $config
}

function RunSyncSuccessCommand {
    Param(
        $Config
    )

    try {
        $command = $Config.SyncSuccessCommand
        if ([string]::IsNullOrWhiteSpace($command)) {
            "no SyncSuccessCommand configured"
            return
        }

        "[STARTED] RunSyncSuccessCommand"

        "invoking '$($command)'..."
        Invoke-Expression -Command $command

        "[COMPLETED] RunSyncSuccessCommand"
    }
    catch {
        "[ERROR] RunSyncSuccessCommand: $($_.Exception)"
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


function Format-ByteSize {
    param (
        $Size
    )

    $magnitude = [System.Math]::Floor([System.Math]::Log($Size, 1024))
    $readableSize = [System.Math]::Round(($Size / [System.Math]::Pow(1024, $magnitude)), 1)
    return "$($readableSize)$(@('B', 'KB', 'MB', 'GB', 'TB', 'EB')[$magnitude])"
}

Main 