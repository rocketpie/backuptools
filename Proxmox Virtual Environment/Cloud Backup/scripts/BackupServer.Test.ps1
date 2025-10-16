[CmdletBinding()]
Param(
    [switch]$Stop,
    [switch]$Cleanup
)

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

function AssertEqual {
    param (
        $Expected,
        $Actual
    )
    
    if ($Actual -isnot $Expected.GetType()) {
        return "FAIL (expected [$($Expected.GetType().Name)] but got [$($Actual.GetType().Name)])   <---------------------- !!!!!"    
    }
    elseif ($Expected -ne $Actual) {
        return "FAIL (expected '$($Expected)' but got '$($Actual)')     <---------------------- !!!!!"
    }
    
    return "PASS"
}


function Test-LogfileMatch {
    param ([string]$logPath, [string]$Pattern)
    $logMatches = @(Select-String -Path (Join-Path $logPath "backupserver-*.log") -Pattern $Pattern)
    Write-Debug "Test-LogfileMatch '$($Pattern)': $($logMatches.Count) hits"
    return $logMatches.Count -gt 0
}

function Wait([int]$Seconds) {
    "waiting $($Seconds)s..."
    Start-Sleep -Seconds $Seconds
}

$testDirectory = Join-Path $PSScriptRoot 'test'

if ($Stop) {
    Get-Job | Stop-Job -PassThru | Remove-Job    
    return
}
if ($Cleanup) {
    Remove-Item $testDirectory -Recurse -Force
    return
}

"stopping all jobs..."
Get-Job | Stop-Job -PassThru | Remove-Job

"initializing test directory '$($testDirectory)'..."
Remove-Item $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $testDirectory -ErrorAction SilentlyContinue | Out-Null

$thisFileName = [System.IO.Path]::GetFileName($MyInvocation.MyCommand.Definition)
$scriptName = $thisFileName.Replace('.Test', '')
$sut = Join-Path $testDirectory $scriptName
Copy-Item -path (Join-Path $PSScriptRoot $scriptName) -Destination $sut

$schemaFilename = $thisFileName.Replace('.Test.ps1', '.schema.json')
Copy-Item -path (Join-Path $PSScriptRoot $schemaFilename) -Destination (Join-Path $testDirectory $schemaFilename)

$testDropDirectory = Join-Path $testDirectory 'drop'
New-Item -ItemType Directory $testDropDirectory -ErrorAction SilentlyContinue | Out-Null

$testDropDirectory2 = Join-Path $testDirectory 'drop2'
New-Item -ItemType Directory $testDropDirectory2 -ErrorAction SilentlyContinue | Out-Null

$testHostedDirectory = Join-Path $testDirectory 'host1'
New-Item -ItemType Directory $testHostedDirectory -ErrorAction SilentlyContinue | Out-Null

$defaultConfigFile = Join-Path $PSScriptRoot $scriptName.Replace('.ps1', '.json')
$testConfigFile = $sut.Replace('.ps1', '.json')
"writing test config file '$($testConfigFile)'..."

$testAssemblyDirectory = Join-Path $testDirectory 'setassembly'
$testTargetDirectory = Join-Path $testDirectory 'target'

$config = Get-Content -Raw -Path $defaultConfigFile | ConvertFrom-Json
$config.TickInterval = "00:00:01"
$config.DropPath = @($testDropDirectory)
$config.HostedSources = @(
    [PSCustomObject]@{
        Path        = $testHostedDirectory
        IdleTimeout = "00:10:00"
    }
)
$config.DropFileWriteTimeout = "00:00:02"
$config.BackupsetAssemblyPath = $testAssemblyDirectory
$config.BackupsetAssemblyTimeout = "00:00:04"
$config.BackupsetStorePath = $testTargetDirectory
$config.LogPath = $testDirectory
$config.LogfileRetentionDuration = "00:00:00:03"
$config.BackupSetFinishedCommand = "Set-Content -Path '{BackupSetPath}\finished.txt' -Value 'a36e26'"
$config | ConvertTo-Json | Set-Content -Path $testConfigFile


"starting main job..."
Start-Job -ArgumentList @($sut, $DebugPreference) -ScriptBlock {
    Param($Sut, $DebugPref)
    $DebugPreference = $DebugPref
    . $Sut

    Main
} | Out-Null
Wait -Seconds 1

"assembly directory should be created:"
AssertEqual $true (Test-Path $testAssemblyDirectory)
"target directory should be created:"
AssertEqual $true (Test-Path $testTargetDirectory)
"logfile should exist:"
AssertEqual $true (Test-Path (Join-Path $testDirectory '*.log'))
"logfile should indicate directoryWatch started"
AssertEqual $true (Test-LogfileMatch -logPath $testDirectory -Pattern "Start-DirectoryWatch.*?host1")


"creating test app directory..."
$testAppName = 'test-app-name-1'
$appdirectory = (Join-Path $testDropDirectory $testAppName)
New-Item -ItemType Directory -Path $appdirectory | Out-Null

$testFile1 = (Join-Path $appdirectory 'test1.txt')
$testFile2 = (Join-Path $appdirectory 'test2.txt')
"writing to file 1..."
Set-Content -path $testFile1 -Value 'bla'
Wait -Seconds 1
"file should still be present:"
AssertEqual $true (Test-Path $testFile1)
"backupset should exist:"
AssertEqual $true (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName)-*"))
"logfile for backupset should exist:"
AssertEqual 1 (Get-ChildItem $testDirectory -File -Filter "backupset-$($testAppName)*.log").Count

"writing to file 2..."
Set-Content -path $testFile2 -Value 'bla'

"adding to file 1..."
Add-Content -path $testFile1 -Value 'bla2'

Wait -Seconds 3
"file 1 should no longer be present:"
AssertEqual $false (Test-Path $testFile1)
"file 2 should no longer be present:"
AssertEqual $false (Test-Path $testFile2)
"files and their .sha256 sholud be present in a backupset folder:"
AssertEqual 4 (Get-ChildItem $testAssemblyDirectory -Recurse -File | Where-Object { $_.FullName -match $testAppName }).Count 

Wait -Seconds 5
"backup set should have been moved"
"from assembly:"
AssertEqual $false (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName)-*"))
"to target:"
AssertEqual $true (Test-Path (Join-Path $testTargetDirectory "$($testAppName)-*"))

Wait -Seconds 3
"BackupSetFinishedCommand should have run:"
AssertEqual 1 (Get-ChildItem $testTargetDirectory -File -Recurse -Filter "finished.txt").Count 
Wait -Seconds 2
"logfile should have expired:"
AssertEqual 0 (Get-ChildItem $testDirectory -File -Filter "backupset-$($testAppName)*.log").Count 

"stopping all jobs..."
Get-Job | Stop-Job -PassThru | Remove-Job


"change to multi-drop config..."
$config.DropPath = @($testDropDirectory, $testDropDirectory2)
$config | ConvertTo-Json | Set-Content -Path $testConfigFile
"restarting main job..."
Start-Job -ArgumentList @($sut, $DebugPreference) -ScriptBlock {
    Param($Sut, $DebugPref)
    $DebugPreference = $DebugPref
    . $Sut

    Main
} | Out-Null
Wait -Seconds 1

"creating test app directories..."
$testAppName2 = 'test-app-name-2'
$testAppName3 = 'test-app-name-3'
$appdirectory2 = (Join-Path $testDropDirectory $testAppName2)
$appdirectory3 = (Join-Path $testDropDirectory2 $testAppName3)
New-Item -ItemType Directory -Path $appdirectory2 | Out-Null
New-Item -ItemType Directory -Path $appdirectory3 | Out-Null

$testFile2 = (Join-Path $appdirectory2 'test2.txt')
$testFile3 = (Join-Path $appdirectory3 'test1.txt')
"writing to files..."
Set-Content -path $testFile2 -Value 'bla'
Set-Content -path $testFile3 -Value 'bla'

Wait -Seconds 2
"backupsets should exist:"
AssertEqual $true (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName2)-*"))
AssertEqual $true (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName3)-*"))
"logfile for backupsets should exist:"
AssertEqual 1 (Get-ChildItem $testDirectory -File -Filter "backupset-$($testAppName2)*.log").Count
AssertEqual 1 (Get-ChildItem $testDirectory -File -Filter "backupset-$($testAppName3)*.log").Count

Wait -Seconds 4
"files and their .sha256 sholud be present in a backupset folder:"
AssertEqual 2 (Get-ChildItem $testAssemblyDirectory -Recurse -File | Where-Object { $_.FullName -match $testAppName2 }).Count 
AssertEqual 2 (Get-ChildItem $testAssemblyDirectory -Recurse -File | Where-Object { $_.FullName -match $testAppName3 }).Count

Wait -Seconds 5
"backup set should have been moved"
"from assembly:"
AssertEqual $false (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName2)-*"))
AssertEqual $false (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName3)-*"))
"to target:"
AssertEqual $true (Test-Path (Join-Path $testTargetDirectory "$($testAppName2)-*"))
AssertEqual $true (Test-Path (Join-Path $testTargetDirectory "$($testAppName3)-*"))

"stopping all jobs..."
Get-Job | Stop-Job -PassThru | Remove-Job


"Done."
Read-Host "press return to remove test directory..."
Remove-Item $testDirectory -Recurse -Force
