
$global:testScriptPath = Split-path $MyInvocation.MyCommand.Definition
$global:backupScriptPath = Split-Path (Get-Command backup.ps1).Definition

# make sure we're in the test directory
$prevWorkingPath = Get-Location
cd $global:testScriptPath

# Functions ========================================================================================================
# ==================================================================================================================

$rand = new-object System.Random

function ResetSandbox {
    # re setup source dirs
    rm .\source -Recurse -Force
    mkdir .\source | Out-Null
    mkdir .\source\a | Out-Null
    mkdir .\source\a\1 | Out-Null
    mkdir .\source\b | Out-Null

    rm .\backups -Recurse -Force
}

# silently executes backup .\source .\backups
function RunBackup {
    backup.ps1 .\source .\backups -Confirm | Out-Null
}

# return 
function GetDiff {
    & $global:backupScriptPath\Compare-Directories.ps1 .\source .\backups\_latest
}

# interprets objects returned from tests as errors
function Test($name, $testScript) {
    $result = @(&$testScript)

    if ($result.Length -gt 0) {
        foreach ($err in $result) {
            Write-Warning "FAILED: $($name): $err"            
        }
    }
    else {
        "PASSED: $name"
    }
}

function RandomString {
    [guid]::NewGuid().ToString()
}

function RandomNewFilePath {
    $filename = RandomString
    
    $dirs = ls .\source -Recurse -Directory
    $dirs += @(get-item .\source)

    join-path $dirs[$rand.Next($dirs.Length)].Fullname $filename
}

function RandomSourceFile {
    $allfiles = @(ls .\source -Recurse -File)    
    if ($allfiles) {
        $allfiles[$rand.Next($allfiles.Length)]
    }
}

function AddRandomFile {
    $filename = RandomNewFilePath
    RandomString > $filename
    $filename
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
    }
}

# Tests ============================================================================================================
# ==================================================================================================================

Test 'EXPECT FAILURE' {
    'this self test must show up as failed'
}

ResetSandbox

Test 'run without backup dir existing should create backup dir, copy of source, and log' {
    RunBackup

    if (-not (Test-Path .\backups)) { 'target dir missing' }
    if (-not (Test-Path .\backups\_latest)) { '_latest dir missing' }
    if (@(ls .\backups -Recurse -File 'log.txt').Length -ne 1) { 'log file missing' }
    $diff = GetDiff
    if($diff.Total -gt 0) { '_latest is not a copy of source' }
}

Test 'add file: should find backup in _latest' {
    $filePath = AddRandomFile
    Write-Debug $filePath

    RunBackup

    $backedUpFile = ls .\backups\_latest -Recurse -File | ?{$_.Name -eq (split-path -leaf $filePath) }
    if(-not $backedUpFile) { 'nope' }
}

Test 'dont change a thing, expect 0 in log file' {
    RunBackup

    if((ls .\backups\*\log.txt | Select-String '0 new files, 0 files changed, 0 files deleted').Length -ne 2) { # first Test report, and this one
        'found something else'
    }
}

Test 'add a bunch of files : should report file count in log file' {
    for ($i = 0; $i -lt 20; $i++) {
        AddRandomFile | Out-Null
    }

    RunBackup

    if(-not (ls .\backups\*\log.txt | Select-String '20 new files')) {
        'nope'
    }
}

Test 'edit file: should find both versions in backup' {
    $testFile = RandomSourceFile

    $oldContent = gc $testFile.Fullname
    $newContent = RandomString

    $newContent > $testFile.Fullname
    
    RunBackup

    $testContent = (ls .\backups\_latest -Recurse -File | ?{$_.name -eq $testFile.name} | gc )
    if($newContent -ne $testContent) {
        "updated content not found in _latest (expected '$newContent', found '$testContent')"
    }

    $testContent = (ls .\backups -Recurse -File | ?{($_.name -eq $testFile.name) -and ($_.FullName -notmatch '\\_latest\\') } | gc )
    if($oldContent -ne $testContent) {
        "prior content not found in log file (expected '$oldContent', found '$testContent')"
    }
}

Test 'copy empty directory' {
    'NotImplemented'
}

$leftover = DeleteRandomFile
while ($leftover) {
    $leftover = DeleteRandomFile
}

# restore working path
cd $prevWorkingPath