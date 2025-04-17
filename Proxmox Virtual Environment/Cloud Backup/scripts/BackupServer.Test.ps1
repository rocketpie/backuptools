[CmdletBinding()]
Param(
)

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

function PrintResult {
    param (
        [bool]$TestResult
    )

    if ($TestResult) { return "PASS" }
    return "FAIL"
}

function Wait([int]$Seconds) {
    "waiting $($Seconds)s..."
    Start-Sleep -Seconds $Seconds
}

$testDirectory = Join-Path $PSScriptRoot 'test'
"initializing test directory '$($testDirectory)'..."
Remove-Item $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $testDirectory -ErrorAction SilentlyContinue | Out-Null

$thisFileName = [System.IO.Path]::GetFileName($MyInvocation.MyCommand.Definition)
$scriptName = $thisFileName.Replace('.Test', '')
$sut = Join-Path $testDirectory $scriptName
Copy-Item -path (Join-Path $PSScriptRoot $scriptName) -Destination $sut

$testSourceDirectory = Join-Path $testDirectory 'source'
New-Item -ItemType Directory $testSourceDirectory -ErrorAction SilentlyContinue | Out-Null

$defaultConfigFile = Join-Path $PSScriptRoot $scriptName.Replace('.ps1', '.json')
$testConfigFile = $sut.Replace('.ps1', '.json')
"writing test config file '$($testConfigFile)'..."

$testAssemblyDirectory = Join-Path $testDirectory 'setassembly'
$testTargetDirectory = Join-Path $testDirectory 'target'

$config = Get-Content -Raw -Path $defaultConfigFile | ConvertFrom-Json
$config.TickInterval = "00:00:01"
$config.SourcePath = $testSourceDirectory
$config.SourceFileWriteTimeout = "00:00:02"
$config.BackupsetAssemblyPath = $testAssemblyDirectory
$config.BackupsetAssemblyTimeout = "00:00:4"
$config.BackupsetStorePath = $testTargetDirectory
$config.LogPath = $testDirectory
$config.LogfileRetentionDuration = "00:00:02"
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
"assembly directory should be created: $(PrintResult (Test-Path $testAssemblyDirectory))"
"target directory should be created: $(PrintResult (Test-Path $testTargetDirectory))"
"logfile should exist: $(PrintResult (Test-Path (Join-Path $testDirectory '*.log')))"

"creating test app directory..."
$testAppName = 'app1'
$appdirectory = (Join-Path $testSourceDirectory $testAppName)
New-Item -ItemType Directory -Path $appdirectory | Out-Null

$testFile = (Join-Path $appdirectory 'test1.txt')
"writing to file..."
Set-Content -path $testFile -Value 'bla'
Wait -Seconds 1
"file should still be present: $(PrintResult (Test-Path $testFile))"

"adding to file..."
Add-Content -path $testFile -Value 'bla2'

Wait -Seconds 3
"file should no longer be present: $(PrintResult (-not (Test-Path $testFile)))"
"backupset should exist: $(PrintResult (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName)-*")))"
"logfile for backupset should exist: $(PrintResult ((Get-ChildItem $testDirectory -File -Filter "backupset-$($testAppName)*.log").Count -gt 0))"

Wait -Seconds 5
"backup set should have been moved"
"from assembly: $(PrintResult (-not (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName)-*"))))"
"to target: $(PrintResult (Test-Path (Join-Path $testTargetDirectory "$($testAppName)-*")))"

Wait -Seconds 2
"logfile should have expired: $(PrintResult ((Get-ChildItem $testDirectory -File -Filter "backupset-$($testAppName)*.log").Count -eq 0))"
"BackupSetFinishedCommand should have run: $(PrintResult ((Get-ChildItem $testTargetDirectory -File -Recurse -Filter "finished.txt").Count -gt 0))"


"stopping all jobs..."
Get-Job | Stop-Job -PassThru | Remove-Job

"Done."
Read-Host "press return to remove test directory..."
Remove-Item $testDirectory -Recurse -Force
