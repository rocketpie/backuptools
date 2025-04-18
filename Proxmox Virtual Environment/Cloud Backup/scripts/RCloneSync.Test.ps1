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

$config = Get-Content -Raw -Path $defaultConfigFile | ConvertFrom-Json
$config.wat = "nope"
$config | ConvertTo-Json | Set-Content -Path $testConfigFile

TryRun -SystemUnderTest { & $sut } -ExpectedError 'none'

"Done."
Read-Host "press return to remove test directory..."
Remove-Item $testDirectory -Recurse -Force
