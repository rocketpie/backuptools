class TestContext {
    TestContext() {
        $this.BackupRuns = 0
        $this.Random = New-Object System.Random
    }

    [string]$TestScriptPath
    [string]$BackupScriptPath
    [System.Random]$Random
    
    [int]$BackupRuns
    # .\backups\[\d-]+.$BackupRuns directory from the latest RunBackup
    [System.IO.DirectoryInfo]$CurrentLogDir    
}

$global:Context = New-Object TestContext
$global:Context.TestScriptPath = Split-path $MyInvocation.MyCommand.Definition
$global:Context.BackupScriptPath = Split-Path (Get-Command backup.ps1).Definition

# make sure we're in the test directory
$prevWorkingPath = Get-Location
cd $global:Context.TestScriptPath

# Functions ========================================================================================================
# ==================================================================================================================

function ResetSandbox {
    $global:Context.BackupRuns = 0
    $global:Context.CurrentLogDir = $null
    
    # re setup source dirs
    rm .\source -Recurse -Force
    mkdir .\source | Out-Null
    mkdir .\source\a | Out-Null
    mkdir .\source\a\a | Out-Null
    mkdir .\source\a\a\a | Out-Null
    mkdir .\source\a\b | Out-Null
    mkdir .\source\a\1 | Out-Null
    mkdir .\source\a\2 | Out-Null
    mkdir .\source\b | Out-Null
    mkdir .\source\1 | Out-Null
    mkdir .\source\1\1 | Out-Null
    mkdir .\source\1\2 | Out-Null
    mkdir .\source\1\a | Out-Null
    mkdir .\source\1\f | Out-Null
    mkdir .\source\2 | Out-Null

    rm .\backups -Recurse -Force
}

# silently executes backup .\source .\backups
function RunBackup {
    backup.ps1 .\source .\backups -Confirm | Out-Null
    $global:Context.BackupRuns++
    $global:Context.CurrentLogDir = @(ls -Directory .\backups | ? { $_.Name.EndsWith(".$($global:Context.BackupRuns)") })[0]
}

# return 
function GetDiff {
    & (Join-Path $global:Context.BackupScriptPath Compare-Directories.ps1) .\source .\backups\_latest
}

# interprets objects returned from tests as errors
function Test($name, $testScript) {
    "TEST: $name..."
    
    $result = @(&$testScript)

    if ($result.Length -gt 0) {
        foreach ($err in $result) {
            Write-Warning "FAILED: $err"            
        }
    }
    else {
        "PASSED"
    }
}

function RandomString {
    [guid]::NewGuid().ToString()
}

function RandomNewFilePath {
    $filename = RandomString
    
    $dirs = ls .\source -Recurse -Directory
    $dirs += @(get-item .\source)

    join-path $dirs[$global:Context.Random.Next($dirs.Length)].Fullname $filename
}

function RandomSourceFile {
    $allfiles = @(ls .\source -Recurse -File)    
    if ($allfiles) {
        $hm = $global:Context.Random.Next($allfiles.Length)
        Write-Debug "HMMMM $hm $($allfiles.Length)" -Debug
        $allfiles[$global:Context.Random.Next($allfiles.Length)]
    }
}

function AddRandomFile {
    $filename = RandomNewFilePath
    RandomString > $filename
    get-item $filename
}

function DeleteRandomFile {
    $file = RandomSourceFile
    if ($file) {
        rm $file.Fullname
        $file.Name
    }
}

function EditRandomFile {
    $file = RandomSourceFile
    if ($file) { 
        RandomString > $file.Fullname
        $file.Name
    }
}

# get the contents of the latest backup run's log file
function ReadLogFile {
    gc (join-path $global:Context.CurrentLogDir.FullName log.txt)
}

# Tests ============================================================================================================
# ==================================================================================================================
Test 'EXPECT FAILURE' {
    'this self test must show up as failed'
}

ResetSandbox

# ==================================================================================================================
Test 'run without backup dir existing should create backup dir, copy of source, and log' {
    RunBackup

    if (-not (Test-Path .\backups)) { 'target dir missing' }
    if (-not (Test-Path .\backups\_latest)) { '_latest dir missing' }
    if (@(ls .\backups -Recurse -File 'log.txt').Length -ne 1) { 'log file missing' }
    $diff = GetDiff
    if ($diff.Total -gt 0) { '_latest is not a copy of source' }
}

# ==================================================================================================================
Test 'add file: should find backup in _latest' {
    $file = AddRandomFile
    Write-Debug $file.FullName

    RunBackup

    $backedUpFile = ls .\backups\_latest -Recurse -File | ? { $_.Name -eq $file.Name }
    if (-not $backedUpFile) { 'nope' }
}

# ==================================================================================================================
Test 'dont change a thing, expect 0 in log file' {
    RunBackup

    if (@(ReadLogFile | Select-String '0 new files, 0 files changed, 0 files deleted').Length -ne 1) {
        # first Test report, and this one
        'found something else'
    }
}

# ==================================================================================================================
Test 'add a bunch of files : should report files and count in log file' {
    $addedFiles = @(1..20 | AddRandomFile)
    
    RunBackup

    $log = ReadLogFile

    if (($log | Select-String 'Selftest: can i search the log this way?')) {
        'SELF-TEST FAILED: Cannot search the log with if($log | Select-String ...'
    }

    if (-not ($log | Select-String '20 new files')) {
        'accurate count missing'
    }

    foreach ($file in $addedFiles) {
        if (-not ($log | Select-String $file.Name)) {
            "filename '$($file.Name)' not found in log"
        }
    }
}

# ==================================================================================================================
Test 'change a bunch of files : should report file count in log file' {    
    $fileCount = @(1..10 | EditRandomFile | sort -Unique).Length
    
    RunBackup

    $log = ReadLogFile
    if(-not ($log | Select-String "$fileCount files changed")) {
    #if (-not (ls .\backups\*\log.txt | Select-String "$fileCount files changed")) {
        'nope'
    }
}

# ==================================================================================================================
Test 'delete a bunch of files : should report file count in log file' {
    for ($i = 0; $i -lt 10; $i++) {
        DeleteRandomFile | Out-Null
    }

    RunBackup

    $log = ReadLogFile
    if(-not ($log | Select-String '10 files deleted')) {
    #if (-not (ls .\backups\*\log.txt | Select-String '10 files deleted')) {
        'nope'
    }
}

# ==================================================================================================================
Test 'edit file: should find both versions in backup' {
    $testFile = RandomSourceFile

    Write-Debug "WOOOOT $testFile" -Debug
    $oldContent = gc $testFile.FullName
    $newContent = RandomString

    $newContent > $testFile.FullName
    
    RunBackup

    $testContent = (ls .\backups\_latest -Recurse -File | ? { $_.name -eq $testFile.name } | gc )
    if ($newContent -ne $testContent) {
        "updated content not found in _latest (expected '$newContent', found '$testContent')"
    }

    $testContent = (ls .\backups -Recurse -File | ? { ($_.name -eq $testFile.name) -and ($_.FullName -notmatch '\\_latest\\') } | gc )
    if ($oldContent -ne $testContent) {
        "prior content not found in log file (expected '$oldContent', found '$testContent')"
    }
}

cd $prevWorkingPath; exit;

# ==================================================================================================================
Test 'copy empty directory' {
    ResetSandbox
    
    RunBackup

    $itemsInLatest = @(ls -Recurse .\backups\_latest).Length
    if ($itemsInLatest -lt 5) {
        "only found $itemsInLatest items in backups\_latest"
    }
}


# restore working path
cd $prevWorkingPath