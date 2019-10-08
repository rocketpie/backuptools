# make sure we're in the test directory
$prevWorkingPath = Get-Location
cd (Split-path $MyInvocation.MyCommand.Definition)

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
    backup.ps1 .\source .\backups | Out-Null
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

function RandomNewFileName {
    $filename = RandomString
    
    $dirs = ls .\source -Recurse -Directory
    $dirs += @(get-item .\source)

    join-path $dirs[$rand.Next($dirs.Length)].Fullname $filename
}

function RandomSourceFileName {
    $allfiles = @(ls .\source -Recurse -File)    
    if ($allfiles) {
        $allfiles[$rand.Next($allfiles.Length)].Fullname 
    }
}

function AddRandomFile {
    $filename = RandomNewFileName
    RandomString > $filename
    $filename
}

function DeleteRandomFile {
    $filename = RandomSourceFileName
    if ($file) {
        rm $filename
        $filename
    }
}

function EditRandomFile {
    $filename = RandomSourceFileName 
    if ($filename) { 
        RandomString > $filename
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
    $diff = .\Compare-Directories.ps1 .\source .\backups\_latest
    if($diff.Total -gt 0) { '_latest is not a copy of source' }
}

Test 'add file: should find backup in _latest' {
    $filePath = AddRandomFile
    RunBackup

    $backedUpFile = (ls .\backups\_latest -Recurse -File (split-path -leaf $filePath))
    if(-not $backedUpFile) { 'nope' }
}

Test 'edit file: should find both versions in backup' {
    'not implemented'
}

Test 'directory is not to be confused with file' {
    'content' > .\source\5
    RunBackup

    rm .\source\5
    mkdir .\source\5 | Out-Null
    RunBackup

    $diff = .\Compare-Directories.ps1 .\source .\backups\_latest
    if($diff.Total -ne 2) { "$($diff.Total) => this is why backup.ps1 should do a more elaborate diff than this simple test diff function" }
}

exit

$leftover = DeleteRandomFile
while ($leftover) {
    $leftover = DeleteRandomFile
}

# restore working path
cd $prevWorkingPath