[CmdletBinding()]
Param(
    [switch]$Stop,
    [switch]$Cleanup,
    [string]$TestFilter
)

Set-StrictMode -Version Latest

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

Set-Variable "TestFilterVariable" -Scope Script -Value $TestFilter

$testContext = [PSCustomObject]@{
    RootDirectory   = ""
    BackupServerPs1 = "" # system under test // the backupserver.ps1
    ConfigFile      = ""
    Config          = $null
}

Set-Variable "TestContext" -Scope Script -Value $testContext
function Get-TestContext { return (Get-Variable "TestContext" -ValueOnly) }


function Main([string]$TestFilter) {
    Initialize-TestRootDirectory


    if (Test-FilterMatch @('single', 'drop')) { Invoke-SingleDirectoryDropTest }
    if (Test-FilterMatch @('multi', 'drop')) { Invoke-MultiDirectoryDropTest }

    if (Test-FilterMatch @('single', 'host')) { Invoke-SingleDirectoryHostTest }


    "Done."
    Read-Host "press return to remove test directory..."
    Remove-TestRootDirectory
}

function Test-FilterMatch {
    Param(
        [string[]]$TestTags
    )
    $testFilter = Get-Variable "TestFilterVariable" -ValueOnly
    $result = $false
    
    if ([string]::IsNullOrWhiteSpace($testFilter)) { $result = $true }#NOFILTER    
    elseif ($TestTags.Contains($testFilter)) { $result = $true }  # filter match
    
    Write-Debug "Test-FilterMatch '$($TestTags -join ',')' -TestFilter '$testFilter' => $($result)"
    return $result
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

function Invoke-SingleDirectoryDropTest {
    "TEST: Single drop folder configuration"
    Reset-DefaultTestConfig
    $testContext = Get-TestContext
    
    $testDropDirectory = Join-Path $testContext.RootDirectory 'drop'
    New-Item -ItemType Directory $testDropDirectory -ErrorAction SilentlyContinue | Out-Null
    $testContext.Config.DropPath = @(
        $testDropDirectory
    )
    
    Start-TestServer

    "set assembly directory should be created:"
    Assert-Equal $true (Test-Path $testContext.Config.BackupsetAssemblyPath)
    "set store directory should be created:"
    Assert-Equal $true (Test-Path $testContext.Config.BackupsetStorePath)
    "logfile should exist:"
    Assert-Equal 1 @(Get-ChildItem $testContext.Config.LogPath -Filter '*.log').Count

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
    Assert-Equal $true (Test-Path $testFile1)
    "backupset should exist:"
    Assert-Equal $true (Test-Path (Join-Path $testContext.Config.BackupsetAssemblyPath "$($testAppName)-*"))
    "logfile for backupset should exist:"
    Assert-Equal 1 @(Get-ChildItem $testContext.RootDirectory -File -Filter "backupset-$($testAppName)*.log").Count

    "writing to file 2..."
    Set-Content -path $testFile2 -Value 'bla'

    "adding to file 1..."
    Add-Content -path $testFile1 -Value 'bla2'

    Wait -Seconds 3
    "file 1 should no longer be present:"
    Assert-Equal $false (Test-Path $testFile1)
    "file 2 should no longer be present:"
    Assert-Equal $false (Test-Path $testFile2)
    "files and their .sha256 sholud be present in a backupset folder:"
    Assert-Equal 4 @(Get-ChildItem $testContext.Config.BackupsetAssemblyPath -Recurse -File | Where-Object { $_.FullName -match $testAppName }).Count 

    Wait -Seconds 5
    "backup set should have been moved"
    "from assembly:"
    Assert-Equal $false (Test-Path (Join-Path $testContext.Config.BackupsetAssemblyPath "$($testAppName)-*"))
    "to target:"
    Assert-Equal $true (Test-Path (Join-Path $testContext.Config.BackupsetStorePath "$($testAppName)-*"))

    Wait -Seconds 3
    "BackupSetFinishedCommand should have run:"
    Assert-Equal 1 @(Get-ChildItem $testContext.Config.BackupsetStorePath -File -Recurse -Filter "finished.txt").Count 
    Wait -Seconds 2
    "logfile should have expired:"
    Assert-Equal 0 @(Get-ChildItem $testContext.RootDirectory -File -Filter "backupset-$($testAppName)*.log").Count 


    Stop-TestServer
}

function Invoke-MultiDirectoryDropTest {
    "TEST: multiple drop folder configuration"
    Reset-DefaultTestConfig
    $testContext = Get-TestContext
    
    $testDropDirectory = Join-Path $testContext.RootDirectory 'drop'
    $testDropDirectory2 = Join-Path $testContext.RootDirectory 'drop2'

    New-Item -ItemType Directory $testDropDirectory -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory $testDropDirectory2 -ErrorAction SilentlyContinue | Out-Null
    $testContext.Config.DropPath = @(
        $testDropDirectory
        $testDropDirectory2
    )
      
    Start-TestServer
    
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
    Assert-Equal $true (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName2)-*"))
    Assert-Equal $true (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName3)-*"))
    "logfile for backupsets should exist:"
    Assert-Equal 1 @(Get-ChildItem $testDirectory -File -Filter "backupset-$($testAppName2)*.log").Count
    Assert-Equal 1 @(Get-ChildItem $testDirectory -File -Filter "backupset-$($testAppName3)*.log").Count

    Wait -Seconds 4
    "files and their .sha256 sholud be present in a backupset folder:"
    Assert-Equal 2 @(Get-ChildItem $testAssemblyDirectory -Recurse -File | Where-Object { $_.FullName -match $testAppName2 }).Count 
    Assert-Equal 2 @(Get-ChildItem $testAssemblyDirectory -Recurse -File | Where-Object { $_.FullName -match $testAppName3 }).Count

    Wait -Seconds 5
    "backup set should have been moved"
    "from assembly:"
    Assert-Equal $false (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName2)-*"))
    Assert-Equal $false (Test-Path (Join-Path $testAssemblyDirectory "$($testAppName3)-*"))
    "to target:"
    Assert-Equal $true (Test-Path (Join-Path $testTargetDirectory "$($testAppName2)-*"))
    Assert-Equal $true (Test-Path (Join-Path $testTargetDirectory "$($testAppName3)-*"))

    Stop-TestServer
}

function Invoke-SingleDirectoryHostTest {    
    "TEST: Single Host folder configuration"
    Reset-DefaultTestConfig
    $testContext = Get-TestContext

    $hostDirectory = New-TestDirectory $testContext.RootDirectory 'hosted'
        
    $testContext.Config.HostedSources = @(
        [PSCustomObject]@{
            Path        = $hostDirectory.FullName
            IdleTimeout = "00:00:03"
        }
    )

    Start-TestServer

    "logfile should indicate directoryWatch started"
    Assert-Equal $true (Test-LogfileMatch -Pattern "Start-DirectoryWatch.*?$($hostDirectory.Name)")

    "new file should trigger Change-Event..."
    $newFile = New-TestFile $hostDirectory.FullName -Name 'new'
    Wait -Seconds 1
    Assert-Equal $true (Test-LogfileMatch -Pattern $newFile.Name)

    "elapsed IdleTimeout shoud trigger Snapshot..."
    Wait -Seconds 4
    Assert-Equal $true (Test-LogfileMatch -Pattern "$($hostDirectory.Name).*?Snapshot")

    "snapshot should show up in restic..."
    Assert-Equal $true $false

    Stop-TestServer
}


<#
88  88 888888 88     88""Yb 888888 88""Yb .dP"Y8
88  88 88__   88     88__dP 88__   88__dP `Ybo."
888888 88""   88  .o 88"""  88""   88"Yb  o.`Y8b
88  88 888888 88ood8 88     888888 88  Yb 8bodP'
#>

function New-Id {
    return [guid]::NewGuid().ToString().Substring(31)    
}

function New-TestDirectory([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$name) {
    $fullname = Join-Path $Path "$($name)-$(New-Id)"
    return (New-Item -ItemType Directory -Path $fullname)
}

function New-TestFile([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$name) {
    $fullName = Join-Path $Path "$($name)-$(New-Id)"
    Set-Content -LiteralPath $fullName -Value (New-Id)
    return (Get-Item $fullName)
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
    Copy-Item -Path (Join-Path $PSScriptRoot 'BackupServer*.*') -Destination $testContext.RootDirectory    

    $testContext.BackupServerPs1 = Join-Path $testContext.RootDirectory 'BackupServer.ps1'
    $testContext.ConfigFile = Join-Path $testContext.RootDirectory 'BackupServer.json'
   
    $testContext.Config = Get-Content -Raw -LiteralPath $testContext.ConfigFile | ConvertFrom-Json
    Reset-DefaultTestConfig
}

function Remove-TestRootDirectory {
    $testContext = Get-TestContext
    Remove-Item $testContext.RootDirectory -Recurse -Force
}

    
function Reset-DefaultTestConfig {
    "Resetting test config to default..."
    $testContext = Get-TestContext

    $testContext.Config.TickInterval = "00:00:01"
    $testContext.Config.LogPath = $testContext.RootDirectory
    $testContext.Config.LogfileRetentionDuration = "00:00:00:03"
    
    $testContext.Config.DropPath = @()
    $testContext.Config.DropFileWriteTimeout = "00:00:02"
    $testContext.Config.BackupsetAssemblyPath = (Join-Path $testContext.RootDirectory 'setassembly')
    $testContext.Config.BackupsetAssemblyTimeout = "00:00:04"
    $testContext.Config.BackupsetStorePath = (Join-Path $testContext.RootDirectory 'target-store')
    $testContext.Config.BackupSetFinishedCommand = "Set-Content -Path '{BackupSetPath}\finished.txt' -Value 'a36e26'"
    
    $testContext.Config.HostedSources = @()
}  


<#
######## ##        #######  ##      ##     ######   #######  ##    ## ######## ########   #######  ##
##       ##       ##     ## ##  ##  ##    ##    ## ##     ## ###   ##    ##    ##     ## ##     ## ##
##       ##       ##     ## ##  ##  ##    ##       ##     ## ####  ##    ##    ##     ## ##     ## ##
######   ##       ##     ## ##  ##  ##    ##       ##     ## ## ## ##    ##    ########  ##     ## ##
##       ##       ##     ## ##  ##  ##    ##       ##     ## ##  ####    ##    ##   ##   ##     ## ##
##       ##       ##     ## ##  ##  ##    ##    ## ##     ## ##   ###    ##    ##    ##  ##     ## ##
##       ########  #######   ###  ###      ######   #######  ##    ##    ##    ##     ##  #######  ########
#>

function Wait([int]$Seconds) {
    "waiting $($Seconds)s..."
    Start-Sleep -Seconds $Seconds
}

function Start-TestServer {
    $testContext = Get-TestContext

    "updating config file..."
    $testContext.Config | ConvertTo-Json | Set-Content -Path $testContext.ConfigFile

    "starting BackupServer..."
    Start-Job -ArgumentList @($testContext.BackupServerPs1, $DebugPreference) -ScriptBlock {
        Param($Sut, $DebugPref)
        $DebugPreference = $DebugPref
        . $Sut
        Main
    } | Out-Null
    Wait -Seconds 1
}

function Stop-TestServer {
    "stopping BackupServer..."
    Get-Job | Stop-Job -PassThru | Remove-Job
}


<#
   ###     ######   ######  ######## ########  ######## ####  #######  ##    ##  ######
  ## ##   ##    ## ##    ## ##       ##     ##    ##     ##  ##     ## ###   ## ##    ##
 ##   ##  ##       ##       ##       ##     ##    ##     ##  ##     ## ####  ## ##
##     ##  ######   ######  ######   ########     ##     ##  ##     ## ## ## ##  ######
#########       ##       ## ##       ##   ##      ##     ##  ##     ## ##  ####       ##
##     ## ##    ## ##    ## ##       ##    ##     ##     ##  ##     ## ##   ### ##    ##
##     ##  ######   ######  ######## ##     ##    ##    ####  #######  ##    ##  ######
#>

function Assert-Equal {
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
    param (
        [string]$Pattern
    )

    $testContext = Get-TestContext
        
    $logMatches = @(Select-String -Path (Join-Path $testContext.RootDirectory "backupserver-*.log") -Pattern $Pattern)
    Write-Debug "Test-LogfileMatch '$($Pattern)': $($logMatches.Count) hit(s)"
    return $logMatches.Count -gt 0
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

if ($Stop) {
    Stop-TestServer
    return
}

if ($Cleanup) {
    Remove-TestRootDirectory
    return
}

Main
