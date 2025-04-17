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

function TryRun {
    param (
        [string]$SUT,
        [string]$Path,
        [switch]$ExpectError
    )
    
    $caughtError = $false
    try {
        & $SUT -BackupsetPath $Path
    }
    catch {
        $caughtError = $true
        if ($ExpectError) {
            "PASS: as expeted, error: $($_.Exception.Message)"
            return
        }
        "ERROR: $($_.Exception)"
    }

    if ($ExpectError -and (-not $caughtError)) {
        "FAIL: expected error, but didn't get one"
    }
}

$testDirectory = Join-Path $PSScriptRoot 'test'
"initializing test directory '$($testDirectory)'..."
Remove-Item $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $testDirectory -ErrorAction SilentlyContinue | Out-Null

$thisFileName = [System.IO.Path]::GetFileName($MyInvocation.MyCommand.Definition)
$scriptName = $thisFileName.Replace('.Test', '')
$sut = Join-Path $testDirectory $scriptName
Copy-Item -path (Join-Path $PSScriptRoot $scriptName) -Destination $sut

$defaultConfigFile = Join-Path $PSScriptRoot $scriptName.Replace('.ps1', '.json')
$testConfigFile = $sut.Replace('.ps1', '.json')
"writing test config file '$($testConfigFile)'..."

$resticRepoPath = Join-Path $testDirectory 'restic-repo'

$config = Get-Content -Raw -Path $defaultConfigFile | ConvertFrom-Json
$config.ResticRepositoryPath = $resticRepoPath
$config | ConvertTo-Json | Set-Content -Path $testConfigFile

$testBackupsetsDirectoryPath = Join-Path $testDirectory 'backupsets'
New-Item -ItemType Directory $testBackupsetsDirectoryPath -ErrorAction SilentlyContinue | Out-Null

$testSourceName = 'app1'
$testBackupsetPath = Join-Path $testBackupsetsDirectoryPath "$($testSourceName)-$(Get-date -AsUTC -Format 'yyyy-MM-ddTHH-mm')"
New-Item -ItemType Directory $testBackupsetPath -ErrorAction SilentlyContinue | Out-Null

TryRun -SUT $sut -Path $testBackupsetPath -ExpectError

"creating '$($resticRepoPath)'..."
New-Item -ItemType Directory $resticRepoPath -ErrorAction SilentlyContinue | Out-Null
TryRun -SUT $sut -Path $testBackupsetPath

Wait -Seconds 1
"verify backupset has moved..."
"from '$(Split-Path -Leaf $testBackupsetPath)': $(PrintResult -TestResult (-not (Test-Path $testBackupsetPath)))"
"to '$($testSourceName)': $(PrintResult -TestResult ((Test-Path (Join-Path $testBackupsetsDirectoryPath $testSourceName))))"

"Done."
Read-Host "press return to remove test directory..."
Remove-Item $testDirectory -Recurse -Force
