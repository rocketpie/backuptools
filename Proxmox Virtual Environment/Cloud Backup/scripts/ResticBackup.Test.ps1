#Requires -Version 7
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
    return "FAIL    <------- !!!"
}

function Wait([int]$Seconds) {
    "waiting $($Seconds)s..."
    Start-Sleep -Seconds $Seconds
}

function TryRun {
    param (
        [scriptblock]$SystemUnderTest,
        [string]$ExpectedError
    )
    
    $caughtError = $false
    try {
        & $SystemUnderTest
    }
    catch {
        $caughtError = $true
        $errorText = $_.Exception.ToString()
        if ([string]::IsNullOrWhiteSpace($ExpectedError)) {
            "FAIL: $($errorText)"
            return
        }

        if ($errorText -match $ExpectedError) {
            "PASS: as expeted: $($_.Exception.Message)"
            return
        }
        else {
            "FAIL: unexpeted error: $($_.Exception)"
        }
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedError)) {
        "PASS: no error"
        return
    }

    if ((-not $caughtError)) {
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
$config.BackupSuccessCommand = $null
$config | ConvertTo-Json | Set-Content -Path $testConfigFile

$testBackupsetsDirectoryPath = Join-Path $testDirectory 'backupsets'
New-Item -ItemType Directory $testBackupsetsDirectoryPath -ErrorAction SilentlyContinue | Out-Null

$testSourceName = 'app1'
$testBackupsetPath = Join-Path $testBackupsetsDirectoryPath "$($testSourceName)-$(Get-date -AsUTC -Format 'yyyy-MM-ddTHH-mm')"
New-Item -ItemType Directory $testBackupsetPath -ErrorAction SilentlyContinue | Out-Null

TryRun -SystemUnderTest { & $sut -BackupsetPath $testBackupsetPath } -ExpectedError 'ResticRepositoryPath'
"creating '$($resticRepoPath)'..."
New-Item -ItemType Directory $resticRepoPath -ErrorAction SilentlyContinue | Out-Null

TryRun -SystemUnderTest { & $sut -BackupsetPath $testBackupsetPath } -ExpectedError 'ResticPassword'
"setting ResticPassword..."
$config.ResticPassword = [guid]::NewGuid().ToString()
$config | ConvertTo-Json | Set-Content -Path $testConfigFile

TryRun -SystemUnderTest { & $sut -BackupsetPath $testBackupsetPath }

Wait -Seconds 1
"verify backupset has moved..."
"from '$(Split-Path -Leaf $testBackupsetPath)':"
PrintResult -TestResult (-not (Test-Path $testBackupsetPath))
"to '...$($testSourceName)'?: (TODO: test that restic took the snapshot)"
PrintResult -TestResult ((Test-Path (Join-Path $resticRepoPath $testSourceName)))

"TODO: test BackupSuccessCommand call"

"Done."
Read-Host "press return to remove test directory..."
Remove-Item $testDirectory -Recurse -Force
