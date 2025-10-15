#Requires -Version 7
<#
    .SYNOPSIS
        Watch backup source directories for changes and trigger the backup process
        Drop sources: 
            directories where any process may drop an *entire* backup set
            after a timeout, the entire directory is snapshot and then emptied again.

        Hosted sources:
            directories where any process may store files persistently.
            periodically, snapshots of the directory are taken
        
#>
[CmdletBinding()]
Param(
    [switch]$Start
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$thisFileName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
$thisFileVersion = "4.1"
Set-Variable -Name "ThisFileName" -Value $thisFileName -Scope Script
Set-Variable -Name "ThisFileVersion" -Value $thisFileVersion -Scope Script
"$($thisFileName) $($thisFileVersion)"

function Main {
    $thisFileName = Get-Variable -Name "ThisFileName" -ValueOnly
    $config = ReadConfigFile

    # very first thing: enable logging
    Initialize-WritableDirectory -Path $config.LogPath
    $logFilePath = Join-Path $config.LogPath "$($thisFileName)-$(Get-Date -AsUTC -Format 'yyyy-MM-dd').log"
    Add-LogInitHeader -LogfilePath $logFilePath

    # then continue initializing other infrastructure
    Initialize-WritableDirectory -Path $config.BackupsetAssemblyPath *>&1 | ForEach-Object { $_; Add-Content -LiteralPath $logFilePath -Encoding utf8NoBOM -Value "$(Get-Date -AsUTC -Format "HH:mm:ss") $_" }
    Initialize-WritableDirectory -Path $config.BackupsetStorePath *>&1 | ForEach-Object { $_; Add-Content -LiteralPath $logFilePath -Encoding utf8NoBOM -Value "$(Get-Date -AsUTC -Format "HH:mm:ss") $_" }
    $TickInterval = [timespan]::Parse($config.TickInterval)
    
    foreach ($path in $config.DropPath) {
        Test-ReadAccess -Path $path *>&1 | ForEach-Object { $_; Add-Content -LiteralPath $logFilePath -Encoding utf8NoBOM -Value "$(Get-Date -AsUTC -Format "HH:mm:ss") $_" }
    }
    foreach ($item in $config.HostedSources) {
        Test-ReadAccess -Path $item.Path *>&1 | ForEach-Object { $_; Add-Content -LiteralPath $logFilePath -Encoding utf8NoBOM -Value "$(Get-Date -AsUTC -Format "HH:mm:ss") $_" }
    }
    
    # initialize Hosted path watchers
    foreach ($item in $config.HostedSources) {
        Start-DirectoryWatch -Path $item.Path -IdleTimeout $item.IdleTimeout *>&1 | ForEach-Object { $_; Add-Content -LiteralPath $logFilePath -Encoding utf8NoBOM -Value "$(Get-Date -AsUTC -Format "HH:mm:ss") $_" }
    }

    # then loop-wait for changes
    $lastLogFilePath = $logFilePath
    while ($true) {
        $logFilePath = Join-Path $config.LogPath "$($thisFileName)-$(Get-Date -AsUTC -Format 'yyyy-MM-dd').log"
        if ($lastLogFilePath -ne $logFilePath) {
            Add-LogInitHeader -LogfilePath $logFilePath
            $lastLogFilePath = $logFilePath
        }

        RunLoop -Config $config *>&1 | ForEach-Object { $_; Add-Content -LiteralPath $logFilePath -Encoding utf8NoBOM -Value "$(Get-Date -AsUTC -Format "HH:mm:ss") $_" }
        Start-Sleep -Duration $TickInterval
    }
}

function RunLoop {
    param ($Config)
    try {        
        Remove-FinishedJobs # or broken ones
  
        Start-NewBackupSetJobs -Config $Config
        Start-NewHostedJobs

        Remove-ExpiredLogFiles -Config $Config
    }
    catch {
        "[ERROR] RunLoop: $($_.Exception)"
    }
}

function AssembleBackupsetLogged {
    Param(
        [string]$DropPath,
        $Config
    )

    $sourceName = Split-Path -Leaf -Path $DropPath
    $logFilePath = Join-Path $Config.LogPath "backupset-$($sourceName)-$(Get-date -AsUTC -Format 'yyyy-MM-ddTHH-mm').log"
    Add-LogInitHeader -LogfilePath $logFilePath
    AssembleBackupset -DropPath $DropPath -Config $Config *>&1 | ForEach-Object { $_; Add-Content -LiteralPath $logFilePath -Encoding utf8NoBOM -Value "$(Get-Date -AsUTC -Format "HH:mm:ss") $_" }
}


function AssembleBackupset {
    Param(
        [string]$DropPath,
        $Config
    )

    # immediate directory name below DropPath
    $sourceName = Split-Path -Leaf -Path $DropPath
    $backupsetName = "$($sourceName)-$(Get-date -AsUTC -Format 'yyyy-MM-ddTHH-mm')"

    "[STARTED] AssembleBackupset '$($backupsetName)'"
    $backupsetPath = Join-Path $Config.BackupsetAssemblyPath $backupsetName
    "creating '$($backupsetPath)'..."
    New-Item -ItemType Directory -Path $backupsetPath | Out-Null

    try {
        $TickInterval = [timespan]::Parse($Config.TickInterval)
        $fileDropWriteTimeout = [timespan]::Parse($Config.DropFileWriteTimeout)
        $setAssemblyTimeout = [timespan]::Parse($Config.BackupSetAssemblyTimeout)
        Write-Debug "TickInterval: '$($TickInterval)'"
        Write-Debug "fileDropWriteTimeout: '$($fileDropWriteTimeout)'"
        Write-Debug "setAssemblyTimeout: '$($setAssemblyTimeout)'"

        $lastSeenAFile = Get-Date -AsUTC
        $fileWatchList = @{}
        while ($true) {
            $droppedFiles = @(Get-ChildItem $DropPath -File -Recurse -Force)
            Write-Debug "$($droppedFiles.Count) files in '$($sourceName)'"
            foreach ($dropFile in $droppedFiles) {
                $lastSeenAFile = Get-Date -AsUTC

                if (-not $fileWatchList.ContainsKey($dropFile.FullName)) {
                    "start watching new file '$([System.IO.Path]::GetRelativePath($DropPath, $dropFile.FullName))'"
                    $fileWatchList.Add($dropFile.FullName, (New-FileWatch -FileItem $dropFile)) | Out-Null
                    continue
                }

                $watch = $fileWatchList[$dropFile.FullName]

                if ($dropFile.Length -gt $watch.LastLength) {
                    "'$($watch.File.Name)' grew to $(Format-ByteSize $dropFile.Length)"
                    $watch.LastLength = $dropFile.Length
                    $watch.LastWriteTime = $dropFile.LastWriteTime
                    $watch.LastChanged = (Get-Date -AsUTC)
                    continue
                }

                if ($dropFile.LastWriteTime -ne $watch.LastWriteTime) {
                    "'$($watch.File.Name)' was modified since $($watch.LastWriteTime.ToString('HH:mm:ss'))"
                    $watch.LastLength = $dropFile.Length
                    $watch.LastWriteTime = $dropFile.LastWriteTime
                    $watch.LastChanged = (Get-Date -AsUTC)
                    continue
                }

                if ($watch.LastChanged.Add($fileDropWriteTimeout) -gt (Get-Date -AsUTC)) {
                    Write-Debug "file unchanged, waiting for file write timeout..."
                    # file hasn't changed, but timeout hasn't passed yet
                    continue
                }

                Write-Debug "file unchanged, timeout elapsed. moving file..."
                $relativeFilePath = [System.IO.Path]::GetRelativePath($DropPath, $dropFile.FullName)
                $backupsetFile = Join-Path $backupsetPath $relativeFilePath
                Write-Debug "relativeFilePath: '$($relativeFilePath)'"
                Write-Debug "backupsetFile: '$($backupsetFile)'"

                if (Test-path $backupsetFile) {
                    Write-Warning "conflict: '$($backupsetFile)' already exists"
                    $backupsetFile += "$(Get-Date -AsUTC -Format 'yy-MM-ddTHH-mm-ss').conflict"
                }

                "didnt see '$($relativeFilePath)' change in the last $($fileDropWriteTimeout.TotalSeconds)s. moving to '$($backupsetFile)'..."
                Move-Item -LiteralPath $dropFile.FullName -Destination $backupsetFile
                $hashFilePath = "$($backupsetFile).sha256"
                "calculating '$($hashFilePath)'..."
                (Get-FileHash -LiteralPath $backupsetFile -Algorithm SHA256).Hash | Set-Content -LiteralPath $hashFilePath

                $fileWatchList.Remove($dropFile.FullName) | Out-Null
            }

            if ($lastSeenAFile.Add($setAssemblyTimeout) -gt (Get-Date -AsUTC)) {
                # files are still being processed
                Start-Sleep -Duration $TickInterval
                continue
            }

            "no files have been processed for $($setAssemblyTimeout.TotalSeconds)s in '$($DropPath)'"
            "moving backupset '$($backupsetName)' to '$($Config.BackupsetStorePath)'..."
            Move-Item -LiteralPath $backupsetPath $Config.BackupsetStorePath
            break
        }

        "[COMPLETED] AssembleBackupset '$($backupsetName)'"
    }
    catch {
        "[ERROR] AssembleBackupset '$($backupsetName)': $($_.Exception)"
    }

    RunBackupSetFinishedCommand -Config $Config -BackupsetName $backupsetName
}

function RunBackupSetFinishedCommand {
    Param(
        $Config,
        [string]$BackupsetName
    )

    try {
        $commandParameter = $Config.BackupSetFinishedCommand
        if ([string]::IsNullOrWhiteSpace($commandParameter)) {
            "no BackupSetFinishedCommand configured"
            return
        }

        "[STARTED] RunBackupSetFinishedCommand '$($BackupsetName)'"

        $backupsetPath = Join-Path $Config.BackupsetStorePath $BackupsetName
        $command = $commandParameter.Replace("{BackupSetPath}", $backupsetPath)
        if ($command -eq $commandParameter) {
            "Hint: use placeholder '{BackupSetPath}' in BackupSetFinishedCommand"
        }

        "invoking `"$($command)`"..."
        Invoke-Expression -Command $command

        "[COMPLETED] RunBackupSetFinishedCommand '$($BackupsetName)'"
    }
    catch {
        "[ERROR] RunBackupSetFinishedCommand '$($BackupsetName)': $($_.Exception)"
    }
}

function Get-ActiveJobs {     
    $activeJobs = @{}
    Get-Job | Where-Object { $_.State -eq 'Running' } | ForEach-Object {
        $activeJobs.Add($_.Name, $_) | Out-Null
    }
    Write-Debug "$($activeJobs.Count) active backupset assembly jobs:"
    Write-Debug "'$($activeJobs.Keys -join "', '")'"
           
    return $activeJobs
}

function Get-NewDropSources {
    param ($Config)
    if ($null -eq $Config.DropPath) {
        return
    }

    $activeJobs = Get-ActiveJobs

    # look for new source drops
    $sourceDirectories = [System.Collections.ArrayList]::new()
    foreach ($path in $Config.DropPath) {
        $droppedDirectories = @(Get-ChildItem $path -Directory -ErrorAction SilentlyContinue | Where-Object { -not $activeJobs.ContainsKey($_.FullName) })
        if ($droppedDirectories.Count -gt 0) {
            $sourceDirectories.AddRange($droppedDirectories) | Out-Null
            Write-Debug "found $($droppedDirectories.Count) drop sources in '$($path)'"
        }
    }

    return $sourceDirectories
}

function Start-NewBackupSetJobs {
    param ($Config)            
    $dropSources = @(Get-NewDropSources -Config $Config)
    if ($null -eq $dropSources) {
        return
    }

    Write-Debug "looking into $($dropSources.Count) drop sources..."
    foreach ($sourceDir in $dropSources) {
        if (@(Get-ChildItem -LiteralPath $sourceDir.FullName -Force).Count -lt 1) {
            Write-Debug "source '$($sourceDir.Name)' is still empty"
            # nothing was dropped here
            continue
        }
                
        "detected items in drop source '$($sourceDir.Name)', starting backupset assembly job..."
        $thisScriptFile = Join-Path $PSScriptRoot "$(Get-Variable -Name "ThisFileName" -ValueOnly).ps1"
        Start-Job -ArgumentList @($thisScriptFile, $sourceDir.FullName, $Config) -Name $sourceDir.FullName -ScriptBlock {
            Param($ThisScriptFile, $DropPath, $Config)
            . $ThisScriptFile
            AssembleBackupsetLogged -DropPath $DropPath -Config $Config
        } | Out-Null
    }
}

function Remove-FinishedJobs {
    param ()
    $stoppedJobs = @(Get-Job | Where-Object { $_.State -ne 'Running' })
    Write-Debug "removing $($stoppedJobs.Count) stopped backupset assembly jobs..."
    foreach ($job in $stoppedJobs) {
        "$($job.State) '$($job.Name)'"
        if ($job.State -eq 'Failed') {
            "Job Failed. receiving Output:"
            @($job | Receive-Job | ForEach-Object { "> $($_)" }) -join "`n"
        }
  
        "removing Job '$($job.Name)'..."
        $job | Remove-Job
    }
}

function Remove-ExpiredLogFiles {
    param ($Config)
            
    $logfileRetentionDuration = [timespan]::Parse($Config.LogfileRetentionDuration)
    Write-Debug "logfileRetentionDuration: '$($logfileRetentionDuration)'"
    
    $allLogfiles = Get-ChildItem -LiteralPath $Config.LogPath -File -Filter *.log
    $expiredLogfiles = $allLogfiles | Where-Object { $_.LastWriteTime.Add($logfileRetentionDuration) -lt (Get-Date) }
    foreach ($expiredLogfile in $expiredLogfiles) {
        "removing expired logfile '$($expiredLogfile.Name)'..."
        Remove-Item -LiteralPath $expiredLogfile.FullName
    }
}

function Add-LogInitHeader {
    Param(
        [string]$LogfilePath
    )
    $thisFileName = Get-Variable -Name "ThisFileName" -ValueOnly
    $thisFileVersion = Get-Variable -Name "ThisFileVersion" -ValueOnly

    if (Test-Path $LogfilePath) {
        Add-Content -LiteralPath $LogfilePath -Encoding utf8NoBOM -Value "`n`n`n`n`n$(Join-Path $PSScriptRoot $thisFileName).ps1 $($thisFileVersion)"
    }
    else {
        Set-Content -LiteralPath $LogfilePath -Encoding utf8NoBOM -Value "$(Join-Path $PSScriptRoot $thisFileName).ps1 $($thisFileVersion)"
    }
    Add-Content -LiteralPath $LogfilePath -Value "log time $(Get-Date -AsUTC -Format "HH:mm:ss") UTC is $(Get-Date -Format "HH:mm:ss") local time"
}


# read the .json config file
function ReadConfigFile {
    # Workaround: MyInvocation.MyCommand.Definition only contains the path to this file when it's not dot-loaded
    $configFile = Join-Path $PSScriptRoot "$(Get-Variable -Name "ThisFileName" -ValueOnly).json"
    $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
    Write-Debug "using config from file '$($configFile)':`n$($config | ConvertTo-Json)"
    return $config
}


function Test-ReadAccess {
    Param(
        $Path
    )
    try {
        if (-not (Test-path -LiteralPath $Path -PathType Container)) {
            Write-Error "'$($Path)' does not exist"
            return
        }
        Get-ChildItem -Recurse -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        Write-Error "cannot read from '$($Path)': $($_.Exception)"
    }
}


# make sure the -Path is a directory, and can be written to
function Initialize-WritableDirectory {
    param (
        [string]$Path
    )

    if ((Test-path -LiteralPath $Path -PathType Leaf)) {
        Write-Error "cannot create directory '$($Path)': a file with this path exists." -ErrorAction Stop
    }
    try {
        if (-not (Test-path -LiteralPath $Path -PathType Container)) {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        }
    }
    catch {
        Write-Error "cannot create directory '$($Path)': $($_.Exception)"
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


function New-FileWatch {
    param (
        $FileItem
    )

    return [PSCustomObject]@{
        File          = $FileItem
        LastLength    = $FileItem.Length
        LastWriteTime = $FileItem.LastWriteTime
        LastChanged   = (Get-Date -AsUTC)
    }
}

# "Path": "/media/backups/sftp-share/lc3win/",
# "IdleTimeout": "00:10:00"
function Start-DirectoryWatch {
    param (
        $Path,
        $IdleTimeout
    )

    Write-Debug "initially analyzing '$($Path)'..."
    $lastWriteTime = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1 -ExpandProperty LastWriteTimeUtc
    )
    if (-not $lastWriteTime) { $lastWriteTime = [datetime]::MinValue }
    
    $watcher = [System.IO.FileSystemWatcher]::new($Path)
    $watcher.IncludeSubdirectories = $true
    $watcher.InternalBufferSize = 64KB  # larger buffer reduces overflow risk (Linux: up to ~64KB)
    $watcherId = "watcher:$([Guid]::NewGuid())"
    $watcherEvents = @()
    
    $directoryWatch = [PSCustomObject]@{
        Path          = $Path
        IdleTimeout   = [timespan]::Parse($IdleTimeout)
        Watcher       = $watcher
        WatcherEvents = $watcherEvents
        LastWriteTime = $lastWriteTime
        LastSnapShot  = (Get-LastSnapshot -Path $Path)
    }

    # watcher event handler
    $watcherHandler = {
        param($EventSource, $EventArguments)
        try {
            # for simplicity, any change event should just move our latest pointer to 'now'
            Write-Debug "watcherHandler:'$($Path)'($($directoryWatch.Path))"
            $directoryWatch.LastWriteTime = (Get-Date -AsUTC)
        }
        catch {
            Write-Warning "watcherHandler error: $($_.Exception)"
        }
    }.GetNewClosure()
        
    $watcherEvents += Register-ObjectEvent -InputObject $watcher -EventName Changed -SourceIdentifier "$($watcherId):Changed" -Action $watcherHandler
    $watcherEvents += Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier "$($watcherId):Created" -Action $watcherHandler
    $watcherEvents += Register-ObjectEvent -InputObject $watcher -EventName Deleted -SourceIdentifier "$($watcherId):Deleted" -Action $watcherHandler
    $watcherEvents += Register-ObjectEvent -InputObject $watcher -EventName Renamed -SourceIdentifier "$($watcherId):Renamed" -Action $watcherHandler
    
    $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        try {
            Get-EventSubscriber | Where-Object { $_.SourceIdentifier -like "$($srcBase)*" } | Unregister-Event
            $watcher.Dispose()
        }
        catch { }
    }.GetNewClosure()

    $DIRECTORY_WATCH_LIST = "DIRECTORY_WATCH_LIST"
    $directoryWatchList = Get-Variable -Name $DIRECTORY_WATCH_LIST -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $directoryWatchList) {
        $directoryWatchList = @{}
    }

    $directoryWatchList.Add($directoryWatch.Path, $directoryWatch) | Out-Null
    Set-Variable -Name $DIRECTORY_WATCH_LIST -Scope Script -Value $directoryWatchList

    $watcher.EnableRaisingEvents = $true
}

function Get-DirectoryWatch {
    $DIRECTORY_WATCH_LIST = "DIRECTORY_WATCH_LIST"
    $directoryWatchList = Get-Variable -Name $DIRECTORY_WATCH_LIST -Scope Script -ValueOnly -ErrorAction SilentlyContinue
  
    if ($null -eq $directoryWatchList) {
        return 
    }

    return $directoryWatchList.GetEnumerator() | ForEach-Object { $_.Value }
}

function Get-LastSnapshot {
    param (
        [string]$Path
    )
    # TODO: remove Mock
    return (Get-Date "2025-10-15" -AsUTC)

    # Ensure restic is available
    $restic = Get-Command 'restic' -ErrorAction SilentlyContinue
    if (-not $restic) {
        throw "restic not found in PATH."
    }

    try {
        # Ask restic for snapshots matching the path, in JSON
        $json = & $restic.Source snapshots --json --path $Path 2>$null

        if ([string]::IsNullOrWhiteSpace($json)) {
            return [datetime]::MinValue
        }

        $snapshots = $json | ConvertFrom-Json
        if (-not $snapshots) {
            return [datetime]::MinValue
        }

        # Extract, parse to DateTimeOffset, normalize to UTC, select latest
        $latestUtc =
        $snapshots |
        ForEach-Object {
            # .time is RFC3339/ISO-8601 with offset, e.g. 2023-11-02T09:41:25.123456789+01:00
            try {
                ([datetimeoffset]::Parse($_.time, [Globalization.CultureInfo]::InvariantCulture)).UtcDateTime
            }
            catch {
                $null
            }
        } |
        Where-Object { $_ -is [datetime] } |
        Sort-Object -Descending |
        Select-Object -First 1

        if ($null -eq $latestUtc) {
            return [datetime]::MinValue
        }

        # Ensure the return is a [datetime] (Kind=Utc)
        if ($latestUtc.Kind -ne [System.DateTimeKind]::Utc) {
            return [datetime]::SpecifyKind($latestUtc, [System.DateTimeKind]::Utc)
        }

        return $latestUtc
    }
    catch {
        throw "Failed to query restic snapshots for path '$Path': $($_.Exception)"
    }
}

function  Start-NewHostedJobs {
    Param()

    $hostDirectoryWatchers = @(Get-DirectoryWatch)
    if ($null -eq $hostDirectoryWatchers) {
        return
    }

    foreach ($watch in $hostDirectoryWatchers) {
        if ($watch.LastWriteTime -lt $watch.LastSnapShot) {
            Write-Debug "change detected in '$($watch.Path)'"
            if ($watch.LastWriteTime -lt ((Get-Date -AsUTC).Add(-$watch.IdleTimeout))) {
                Write-Debug "idle timeout exceeded in '$($watch.Path)'"                
                Start-Job -ArgumentList @($thisScriptFile, $watch.Path, $Config) -Name $watch.Path -ScriptBlock {
                    Param($ThisScriptFile, $Path, $Config)
                    "calling `"restic backup '$($Path)'`"..." 
                } | Out-Null                
            }
        }
    }
}

function Format-ByteSize {
    param (
        $Size
    )

    $magnitude = [System.Math]::Floor([System.Math]::Log($Size, 1024))
    $readableSize = [System.Math]::Round(($Size / [System.Math]::Pow(1024, $magnitude)), 1)
    return "$($readableSize)$(@('B', 'KB', 'MB', 'GB', 'TB', 'EB')[$magnitude])"
}


if ($Start) {
    Main
}