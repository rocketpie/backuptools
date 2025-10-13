#Requires -Version 7
[CmdletBinding()]
Param(
    [switch]$Start
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$thisFileName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
$thisFileVersion = "4.0"
Set-Variable -Name "ThisFileName" -Value $thisFileName -Scope Script
Set-Variable -Name "ThisFileVersion" -Value $thisFileVersion -Scope Script
"$($thisFileName) $($thisFileVersion)"

function Main {
    $thisFileName = Get-Variable -Name "ThisFileName" -ValueOnly
    $config = ReadConfigFile

    foreach ($path in $config.DropPath) {
        Test-ReadAccess -Path $config.DropPath
    }
    Initialize-WritableDirectory -Path $config.LogPath
    Initialize-WritableDirectory -Path $config.BackupsetAssemblyPath
    Initialize-WritableDirectory -Path $config.BackupsetStorePath
    $TickInterval = [timespan]::Parse($config.TickInterval)

    $lastLogFilePath = $null
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
    param (
        $Config
    )

    try {
        # remove finished / broken jobs
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

        $activeJobs = @{}
        Get-Job | Where-Object { $_.State -eq 'Running' } | ForEach-Object {
            $activeJobs.Add($_.Name, $_) | Out-Null
        }
        Write-Debug "$($activeJobs.Count) active backupset assembly jobs:"
        Write-Debug "'$($activeJobs.Keys -join "', '")'"

        $sourceDirectories = [System.Collections.ArrayList]::new()
        foreach ($path in $Config.DropPath) {
            $droppedDirectories = @(Get-ChildItem $path -Directory -ErrorAction SilentlyContinue | Where-Object { -not $activeJobs.ContainsKey($_.FullName) })
            if ($droppedDirectories.Count -gt 0) {
                $sourceDirectories.AddRange($droppedDirectories)
                Write-Debug "found $($droppedDirectories.Count) drop sources in '$($path)'"
            }
        }
        Write-Debug "looking into $($sourceDirectories.Count) drop sources..."
        foreach ($sourceDir in $sourceDirectories) {
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

        $logfileRetentionDuration = [timespan]::Parse($Config.LogfileRetentionDuration)
        Write-Debug "logfileRetentionDuration: '$($logfileRetentionDuration)'"

        $allLogfiles = Get-ChildItem -LiteralPath $Config.LogPath -File -Filter *.log
        $expiredLogfiles = $allLogfiles | Where-Object { $_.LastWriteTime.Add($logfileRetentionDuration) -lt (Get-Date) }
        foreach ($expiredLogfile in $expiredLogfiles) {
            "removing expired logfile '$($expiredLogfile.Name)'..."
            Remove-Item -LiteralPath $expiredLogfile.FullName
        }
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