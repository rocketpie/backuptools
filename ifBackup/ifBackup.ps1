#!/usr/bin/pwsh
#Requires -Version 7.3
<#
    .SYNOPSIS
        make a restic snapshot of all directories if the contents have been modified since the last snapshot.
#>
[CmdletBinding()]
Param(
    # read the configuration file and set the restic environment variables
    [Parameter(Mandatory, ParameterSetName = "SetResticEnvironmentVariables")]
    [switch]$SetResticEnvironmentVariables,

    [Parameter(ParameterSetName = "Start")]
    [switch]$Start
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

$thisFileName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
$thisFileVersion = "0.4"
Set-Variable -Name "ThisFileName" -Value $thisFileName -Scope Script
Set-Variable -Name "ThisFileVersion" -Value $thisFileVersion -Scope Script
"$($thisFileName) $($thisFileVersion)"

function Main {
    "checking config..."
    $config = Read-ConfigFile
    
    "Test-WriteAccess '$($config.log.path)'"
    Test-WriteAccess -Path $config.log.path

    $logFilePath = Initialize-LogFile -LogPath $config.log.path

    Initialize *>&1 | Out-Logged -LogfilePath $logFilePath    
    if ($true -ne (Get-Variable -Name "Initialized" -ValueOnly -ErrorAction SilentlyContinue)) {
        return 
    }

    Invoke-CheckAndSnapshot *>&1 | Out-Logged -LogfilePath $logFilePath
    Remove-ExpiredLogFiles  *>&1 | Out-Logged -LogfilePath $logFilePath
}

function Initialize {
    try {
        foreach ($source in $config.snapshots) {
            $sourcePaths = Get-ChildDirectories -Path $source.path -Recuresdepth $source.recurseDepth
            foreach ($path in $sourcePaths) {
                "Test-ReadAccess '$($path)'..."
                Test-ReadAccess -Path $path
            }
        }
        
        # set restic environment variables
        $env:RESTIC_REPOSITORY = $config.restic.repositoryPath
        $env:RESTIC_PASSWORD = $config.restic.password
        Test-Restic 

        Set-Variable -Name "Initialized" -Value $true -Scope Script
    }
    catch {
        "[ERROR] Initialize: $($_.Exception)"
    }
}

function Test-Restic {
    "testing command 'restic'..."
    if ($null -eq (Get-Command 'restic' -ErrorAction SilentlyContinue)) {
        Write-Error "[ERROR] cannot find command 'restic'"
        return
    }
    
    # https://restic.readthedocs.io/en/stable/075_scripting.html
    "calling 'restic cat config'..."
    restic cat config
}

function Invoke-CheckAndSnapshot {
    $config = Get-Config

    foreach ($source in $config.snapshots) {
        $sourcePaths = Get-ChildDirectories -Path $source.path -Recuresdepth $source.recurseDepth
        foreach ($path in $sourcePaths) {
            try {
                $lastWrite = Get-LastWriteTimeUtc -Path $path
                $lastSnapshot = Get-LastSnapshotUtc -Path $path

                $idleTime = [timespan]::Parse($source.idleTimeout)
                $idleThreshold = (Get-Date -AsUTC).Add(-$idleTime)
                
                "checking for changes '$(PrintDate $lastWrite)' > '$(PrintDate $lastSnapshot)'"
                if ($lastWrite -le $lastSnapshot) {
                    "no changes."
                    continue
                }
            
                "checking idle '$(PrintDate $lastWrite)' < '$(PrintDate $idleThreshold)'"
                if ($lastWrite -gt $idleThreshold) {
                    "write still in progress?"
                    continue
                }

                Invoke-Snapshot -Path $path          
            }
            catch {
                "[ERROR] '$($path)': '$($_.Exception)'"
            }
        }
    }    
}

function Out-Logged {
    [CmdletBinding()]
    param(
        [string]$LogFilePath,

        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )
    begin {
        $fileStream = [System.IO.File]::Open($LogFilePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $encoding = New-Object System.Text.UTF8Encoding($false) # no BOM
        $writer = New-Object System.IO.StreamWriter($fileStream, $encoding)
        $writer.AutoFlush = $true
    }

    process {
        foreach ($obj in @($InputObject)) {
            if ($null -eq $obj) { continue }

            # Normalize, remove trailing newlines
            if ($obj -is [string]) {
                $text = $obj.TrimEnd("`r", "`n")
            }
            else {
                $text = ($obj | Out-String -Width ([int]::MaxValue)).TrimEnd("`r", "`n")
            }

            $writer.WriteLine("$(Get-Date -AsUTC -Format "HH:mm:ss") $($text)" );

            # always pass through
            $obj
        }
    }

    end {
        try { $writer.Flush() } finally { $writer.Dispose() }
    }
}

function Remove-ExpiredLogFiles {
    $config = Get-Config

    Write-Debug "Remove-ExpiredLogFiles ($($config.log.retainLogs))..."    
    $allLogfiles = Get-ChildItem -LiteralPath $config.log.path -File -Filter *.log
    
    $logfileRetentionDuration = [timespan]::Parse($config.log.retainLogs)
    $expirationThreshold = (Get-Date).Add(-$logfileRetentionDuration)
    $expiredLogfiles = $allLogfiles | Where-Object { $_.LastWriteTime -lt $expirationThreshold }
    foreach ($expiredLogfile in $expiredLogfiles) {
        "removing expired logfile '$($expiredLogfile.Name)'..."
        Remove-Item -LiteralPath $expiredLogfile.FullName
    }
}

function Initialize-LogFile {
    Param(
        [string]$LogPath
    )
    $thisFileName = Get-Variable -Name "ThisFileName" -ValueOnly
    $logFilePath = Join-Path $LogPath "$($thisFileName)-$(Get-Date -AsUTC -Format 'yyyy-MM-dd').log"

    $thisFileVersion = Get-Variable -Name "ThisFileVersion" -ValueOnly
    if (Test-Path $LogfilePath) {
        # a logfile from a previous run on the same day exists. eg. restart, reboot, etc.
        Add-Content -LiteralPath $LogfilePath -Encoding utf8NoBOM -Value "`n`n`n`n`n$(Join-Path $PSScriptRoot $thisFileName).ps1 $($thisFileVersion)" | Out-Null
    }
    else {
        # create a new file
        Set-Content -LiteralPath $LogfilePath -Encoding utf8NoBOM -Value "$(Join-Path $PSScriptRoot $thisFileName).ps1 $($thisFileVersion)" | Out-Null
    }
    Add-Content -LiteralPath $LogfilePath -Encoding utf8NoBOM -Value "log time $(Get-Date -AsUTC -Format "HH:mm:ss") UTC is $(Get-Date -Format "HH:mm:ss") local time"

    return $logFilePath
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

    Set-Variable -Name "Config" -Value $config -Scope Script
    return $config # default pass-through
}

function Get-Config { return Get-Variable -Name "Config" -ValueOnly }


function Test-ReadAccess {
    Param(
        $Path
    )
    try {
        if (-not (Test-path -LiteralPath $Path -PathType Container)) {
            Write-Error "'$($Path)' does not exist"
            return
        }
        Get-ChildItem -Recurse -LiteralPath $Path -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "cannot read from '$($Path)': $($_.Exception)"
        return
    }    
}


# make sure the -Path is a directory, and can be written to
function Test-WriteAccess {
    param (
        [string]$Path
    )

    if ((Test-path -LiteralPath $Path -PathType Leaf)) {
        Write-Error "cannot use directory '$($Path)': a file with this path exists." -ErrorAction Stop
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Error "cannot use directory '$($Path)': no such directory" -ErrorAction Stop
    }

    $testFile = (Join-Path $Path 'file-write-test-5636bb')
    try {
        New-Item -ItemType File -Path $testFile -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $testFile -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Error "cannot write to directory '$($Path)': $($_.Exception)"
        Remove-Item -LiteralPath $testFile -ErrorAction SilentlyContinue | Out-Null
    }
}


function Get-NormalizedPath([string]$Path) { return $Path.Replace('\', '/').TrimEnd('/') }

function Get-ChildDirectories {
    param(
        # directory to enumerate
        [string]$Path,
        # 0 = return $Path
        [int]$RecurseDepth = 0
    )

    if ($RecurseDepth -eq 0) {
        return @($Path)
    }

    return @(Get-ChildItem -LiteralPath $Path -Directory -Recurse -Depth $RecurseDepth -Force | Select-Object -ExpandProperty FullName)
}

# Get the latest LastWriteTimeUtc of all files within a directory
function Get-LastWriteTimeUtc {
    param(
        [string]$Path
    )

    $lastWriteTime = [datetime]::MinValue    
    Get-ChildItem -LiteralPath $Path -Recurse -Depth 100 -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { 
        if ($lastWriteTime -lt $_.LastWriteTimeUtc) {
            $lastWriteTime = $_.LastWriteTimeUtc
        }
    }
    
    return $lastWriteTime
}

# Get the timestamp (UTC) of the most recent restic snapshot for a path.
function Get-LastSnapshotUtc {
    param(
        [string]$Path
    )
    try { 
        # Query snapshots for the given path in JSON
        # TODO: restic snapshots --path matches paths as stored in snapshots. Ensure you pass the same absolute, normalized path you used for backup.
        $json = restic snapshots --json --path $Path 2>$null
        if ([string]::IsNullOrWhiteSpace($json)) {
            return [datetime]::MinValue
        }

        $snapshots = @($json | ConvertFrom-Json)
        if ($null -eq $snapshots -or $snapshots.Count -eq 0) {
            return [datetime]::MinValue
        }

        $times = @($snapshots | ForEach-Object { Convert-ResticDateToUtc $_.time })
        
        if (-not $times -or $times.Count -eq 0) {
            return [datetime]::MinValue
        }

        # Return the latest snapshot time (UTC)
        return ($times | Measure-Object -Maximum).Maximum
    }
    catch {
        Write-Error "Get-LastSnapshotUtc error: $($_.Exception)"
    }
}

# Normalize times (restic can emit up to 9 fractional digits; .NET supports up to 7)
function Convert-ResticDateToUtc {
    param($resticTime)
    
    if (-not $resticTime) { return $null }
    $normalized = $resticTime -replace '(\.\d{1,9})Z$', {
        param($m)
        $frac = $m.Groups[1].Value.TrimStart('.')
        '.' + $frac.PadRight(7, '0').Substring(0, 7) + 'Z'
    }
    try {
        ([datetimeoffset]::Parse(
            $normalized,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal
        )).UtcDateTime
    }
    catch { $null }
}

function Invoke-Snapshot {
    Param($Path)
    $config = Get-Config

    $backupParams = @($config.restic.backupOptions)
    $backupParams += @($Path)
    "calling `"restic backup $((JoinParameterString $backupParams))`"..."
    #restic backup @backupParams

    $forgetParams = @($config.restic.forgetOptions)
    "calling `"restic forget $((JoinParameterString $forgetParams))`"..."
    #restic forget @forgetParams
}


function JoinParameterString {
    param (
        [array]$Parameters
    )

    $paramsText = [System.Text.StringBuilder]::new()
    $first = $true
    foreach ($param in $Parameters) {
        if ($first) { $first = $false }
        else { $paramsText.Append(' ') | Out-Null }

        if ($param.ToString().Trim() -match '\s') {
            $paramsText.Append("'$($param)'") | Out-Null
        }
        else {
            $paramsText.Append($param) | Out-Null
        }
    }

    return $paramsText.ToString()
}

function PrintDate {
    param (
        [datetime]$date
    )
    $date.ToString('yyyy-MM-ddTHH:mm:ss')
}

function Format-ByteSize {
    param (
        $Size
    )

    $magnitude = [System.Math]::Floor([System.Math]::Log($Size, 1024))
    $readableSize = [System.Math]::Round(($Size / [System.Math]::Pow(1024, $magnitude)), 1)
    return "$($readableSize)$(@('B', 'KB', 'MB', 'GB', 'TB', 'PB')[$magnitude])"
}

switch ($PSCmdlet.ParameterSetName) {
    SetResticEnvironmentVariables {
        $config = Read-ConfigFile
        
        # set restic environment variables
        $env:RESTIC_REPOSITORY = $config.restic.repositoryPath
        $env:RESTIC_PASSWORD = $config.restic.password
    }

    Start {
        if ($Start) { 
            Main 
        }
    }
}