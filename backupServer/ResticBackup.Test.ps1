#!/usr/bin/pwsh
#Requires -Version 7
[CmdletBinding()]
Param(
    [switch]$Cleanup
)

Set-StrictMode -Version Latest

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

$testContext = [PSCustomObject]@{
    RootDirectory   = ""
    ResticBackupPs1 = "" # system under test // the ResticBackup.ps1
    ConfigFile      = ""
    Config          = $null
}

Set-Variable "TestContext" -Scope Script -Value $testContext
function Get-TestContext { return (Get-Variable "TestContext" -ValueOnly) }


function Invoke-Tests([string]$TestFilter) {
    Initialize-TestRootDirectory

    Invoke-TestBackupsetPath
    Invoke-TestHostedPath
    Invoke-TestSetEnvironmentVariables
    "TODO: test BackupSuccessCommand call"


    "Done."
    Read-Host "press return to remove test directory..."
    Remove-TestRootDirectory
}


<#
######## ########  ######  ########  ######
   ##    ##       ##    ##    ##    ##    ##
   ##    ##       ##          ##    ##
   ##    ######    ######     ##     ######
   ##    ##             ##    ##          ##
   ##    ##       ##    ##    ##    ##    ##
   ##    ########  ######     ##     ######
#>
function Invoke-TestSetEnvironmentVariables {
    $testContext = Get-TestContext
    Reset-DefaultTestConfig
  
    "TEST ResticBackup -SetResticEnvironmentVariables..."
    Invoke-SUT -TestScript { & $testContext.ResticBackupPs1 -SetResticEnvironmentVariables }.GetNewClosure()
}

function Invoke-TestBackupsetPath {
    $testContext = Get-TestContext
    Reset-DefaultTestConfig

    $testBackupsetsDirectoryPath = Join-Path $testContext.RootDirectory 'backupsets'
    New-Item -ItemType Directory $testBackupsetsDirectoryPath -ErrorAction SilentlyContinue | Out-Null

    $testSourceName = 'app1'
    $testBackupsetPath = Join-Path $testBackupsetsDirectoryPath "$($testSourceName)-$(Get-date -AsUTC -Format 'yyyy-MM-ddTHH-mm')"
    New-Item -ItemType Directory $testBackupsetPath -ErrorAction SilentlyContinue | Out-Null

    "TEST missing repositoy directory..."
    Remove-Item $testContext.Config.ResticRepositoryPath -ErrorAction SilentlyContinue | Out-Null
    Invoke-SUT -TestScript { & $testContext.ResticBackupPs1 -BackupsetPath $testBackupsetPath }.GetNewClosure() -ExpectedError 'ResticRepositoryPath'
    
    "re-creating '$($testContext.Config.ResticRepositoryPath)'..."
    New-Item -ItemType Directory $testContext.Config.ResticRepositoryPath -ErrorAction SilentlyContinue | Out-Null

    "testing empty password..."
    $testContext.Config.ResticPassword = ""
    Invoke-SUT -TestScript { & $testContext.ResticBackupPs1 -BackupsetPath $testBackupsetPath }.GetNewClosure() -ExpectedError 'ResticPassword'
    
    Reset-DefaultTestConfig
    Invoke-SUT -TestScript { & $testContext.ResticBackupPs1 -BackupsetPath $testBackupsetPath }.GetNewClosure()

    Wait -Seconds 1
    "verify backupset has moved..."
    "from '$(Split-Path -Leaf $testBackupsetPath)':"
    PrintResult -TestResult (-not (Test-Path $testBackupsetPath))
    "to '...$($testSourceName)'?: (TODO: test that restic took the snapshot)"
    PrintResult -TestResult ((Test-Path (Join-Path $testContext.Config.ResticRepositoryPath $testSourceName)))

}

function Invoke-TestHostedPath {
    $testContext = Get-TestContext
    Reset-DefaultTestConfig

    $testHostedDirectoryPath = Join-Path $testContext.RootDirectory 'hosted'
    New-Item -ItemType Directory $testHostedDirectoryPath -ErrorAction SilentlyContinue | Out-Null

    $testSourceName = 'laptop'
    $testSourcePath = Join-Path $testHostedDirectoryPath "$($testSourceName)"
    New-Item -ItemType Directory $testSourcePath -ErrorAction SilentlyContinue | Out-Null
    
    "TEST missing repositoy directory..."
    Remove-Item $testContext.Config.ResticRepositoryPath -ErrorAction SilentlyContinue | Out-Null   
    Invoke-SUT -TestScript { & $testContext.ResticBackupPs1 -HostedPath $testSourcePath }.GetNewClosure() -ExpectedError 'ResticRepositoryPath'
    
    "re-creating '$($testContext.Config.ResticRepositoryPath)'..."
    New-Item -ItemType Directory $testContext.Config.ResticRepositoryPath -ErrorAction SilentlyContinue | Out-Null

    "testing empty password..."
    $testContext.Config.ResticPassword = ""
    Invoke-SUT -TestScript { & $testContext.ResticBackupPs1 -HostedPath $testSourcePath }.GetNewClosure() -ExpectedError 'ResticPassword'
        
    Reset-DefaultTestConfig
    Invoke-SUT -TestScript { & $testContext.ResticBackupPs1 -HostedPath $testSourcePath }.GetNewClosure()
    
    'TODO: test missing source path?'
    
    Wait -Seconds 1
    "verify soure path stays untouced..."
    PrintResult -TestResult ((Test-Path $testSourcePath))

    'TODO: test all files left untouched...'
}


<#
88  88 888888 88     88""Yb 888888 88""Yb .dP"Y8
88  88 88__   88     88__dP 88__   88__dP `Ybo."
888888 88""   88  .o 88"""  88""   88"Yb  o.`Y8b
88  88 888888 88ood8 88     888888 88  Yb 8bodP'
#>

function PrintResult {
    param (
        [bool]$TestResult
    )

    if ($TestResult) { return "PASS" }
    return "FAIL      <--------------        !!!!!!!!"
}

function Wait([int]$Seconds) {
    "waiting $($Seconds)s..."
    Start-Sleep -Seconds $Seconds
}

function Invoke-SUT {
    param (
        $TestScript,
        [string]$ExpectedError
    )
    $testContext = Get-TestContext

    "updating config file..."
    $testContext.Config | ConvertTo-Json | Set-Content -Path $testContext.ConfigFile
    
    $caughtError = $false
    try {
        & $TestScript | Out-Null
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


<#
 ######  ########    ###    ######## ########     ######   #######  ##    ## ######## ########   #######  ##
##    ##    ##      ## ##      ##    ##          ##    ## ##     ## ###   ##    ##    ##     ## ##     ## ##
##          ##     ##   ##     ##    ##          ##       ##     ## ####  ##    ##    ##     ## ##     ## ##
 ######     ##    ##     ##    ##    ######      ##       ##     ## ## ## ##    ##    ########  ##     ## ##
      ##    ##    #########    ##    ##          ##       ##     ## ##  ####    ##    ##   ##   ##     ## ##
##    ##    ##    ##     ##    ##    ##          ##    ## ##     ## ##   ###    ##    ##    ##  ##     ## ##
 ######     ##    ##     ##    ##    ########     ######   #######  ##    ##    ##    ##     ##  #######  ########
#>

function Initialize-TestRootDirectory {
    $testContext = Get-TestContext
    $testContext.RootDirectory = Join-Path $PSScriptRoot 'test'

    "initializing test directory '$($testContext.RootDirectory)'..."
    Remove-Item $testContext.RootDirectory -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory $testContext.RootDirectory -ErrorAction SilentlyContinue | Out-Null

    "copy original test files..."
    Copy-Item -Path (Join-Path $PSScriptRoot 'ResticBackup*.*') -Destination $testContext.RootDirectory    

    $testContext.ResticBackupPs1 = Join-Path $testContext.RootDirectory 'ResticBackup.ps1'
    $testContext.ConfigFile = Join-Path $testContext.RootDirectory 'ResticBackup.json'
   
    $testContext.Config = Get-Content -Raw -LiteralPath $testContext.ConfigFile | ConvertFrom-Json
    Reset-DefaultTestConfig
}

function Remove-TestRootDirectory {
    $testRootDirectory = (Join-Path $PSScriptRoot 'test')

    $testContext = Get-TestContext
    if (($null -ne $testContext) -and ![string]::IsNullOrWhiteSpace($testContext.RootDirectory)) {        
        $testRootDirectory = $testContext.RootDirectory
    }

    Remove-Item $testRootDirectory -Recurse -Force
}
    
function Reset-DefaultTestConfig {
    "Resetting test config to default..."
    $testContext = Get-TestContext
    
    $testContext.Config.ResticRepositoryPath = (Join-Path $testContext.RootDirectory 'restic-repo')
    $testContext.Config.ResticPassword = [guid]::NewGuid().ToString()
    $testContext.Config.ResticBackupOptions = @()
    $testContext.Config.ResticForgetOptions = @()
    $testContext.Config.BackupSuccessCommand = $null
}  


<#
##     ##    ###    #### ##    ##     ######     ###    ##       ##
###   ###   ## ##    ##  ###   ##    ##    ##   ## ##   ##       ##
#### ####  ##   ##   ##  ####  ##    ##        ##   ##  ##       ##
## ### ## ##     ##  ##  ## ## ##    ##       ##     ## ##       ##
##     ## #########  ##  ##  ####    ##       ######### ##       ##
##     ## ##     ##  ##  ##   ###    ##    ## ##     ## ##       ##
##     ## ##     ## #### ##    ##     ######  ##     ## ######## ########
#>

if ($Cleanup) {
    Remove-TestRootDirectory
    return
}

Invoke-Tests
