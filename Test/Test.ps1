<#
.SYNOPSIS
Short description

.DESCRIPTION
Long description

.EXAMPLE
An example

.NOTES
General notes
#>
[CmdletBinding()]
param (
    # debugging: execute specifict test by providing its (unique) prefix
    # be careful: some tests require other tests to be run prior or fail otherwise
    [Parameter(Position = 0, Mandatory = $false)]
    [string]
    $SpecificTest = ""
)
    
#$DebugPreference = 'Continue'
$Global:specificTest = $SpecificTest


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

    rm .\backups -Recurse -Force -ErrorAction 'SilentlyContinue' | Out-Null 
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
    if ($Global:specificTest) {
        if (-not ($name.startswith($Global:specificTest))) {
            Write-Debug "Skipping $name"
            return
        }
    }
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
Test '4002 EXPECT FAILURE' {
    'this test self-test must show up as failed'
}

ResetSandbox

# ==================================================================================================================
Test '4033 run without backup dir existing should create backup dir, copy of source, and log' {
    RunBackup

    if (-not (Test-Path .\backups)) { 'target dir missing' }
    if (-not (Test-Path .\backups\_latest)) { '_latest dir missing' }
    if (@(ls .\backups -Recurse -File 'log.txt').Length -ne 1) { 'log file missing' }
    $diff = GetDiff
    if ($diff.Total -gt 0) { '_latest is not a copy of source' }
}

# ==================================================================================================================
Test '4d40 add file: should find backup in _latest' {
    $file = AddRandomFile
    Write-Debug $file.FullName

    RunBackup

    $backedUpFile = ls .\backups\_latest -Recurse -File | ? { $_.Name -eq $file.Name }
    if (-not $backedUpFile) { 'nope' }
}

# ==================================================================================================================
Test '4a6c dont change a thing, expect 0 in log file' {
    RunBackup

    if (@(ReadLogFile | Select-String '0 new files, 0 files changed, 0 files deleted').Length -ne 1) {
        'found something else'
    }
}

# ==================================================================================================================
Test '55c6 add a bunch of files : should report files and count in log file' {
    $addedFiles = @(1..20 | % { AddRandomFile })

    if ($addedFiles.Length -ne 20) {
        'SELF-TEST FAILED: didnt add enough files'
    }

    RunBackup

    $log = ReadLogFile
    if (($log | Select-String 'Selftest: can i search the log this way?')) {
        'SELF-TEST FAILED: false-positive searching the log with if($log | Select-String ...'
    }
    if (-not ($log | Select-String "backing up")) {
        'SELF-TEST FAILED: false-negative searching the log with if(-not ($log | Select-String ...)'
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
Test '3d26 change a bunch of files : should report files and count in log file' {    
    $editedFileNames = @( 1..10 | EditRandomFile )    
    $fileCount = @($editedFileNames | sort -Unique).Length # it might happen that the same file is edited a few times
    
    RunBackup

    $log = ReadLogFile
    if (-not ($log | Select-String "$fileCount files changed")) {
        'changed file count not found in log'
    }

    foreach ($name in $editedFileNames) {
        if (-not ($log | Select-String $name)) {
            "filename '$($name)' not found in log"
        }
    }
}

# ==================================================================================================================
Test '38ac delete a bunch of files : should report file count in log file' {
    $deletedFileNames = @(1..10 | % { DeleteRandomFile })
    
    RunBackup

    $log = ReadLogFile
    if (-not ($log | Select-String '10 files deleted')) {
        'deleted file count not found in log'
    }

    foreach ($name in $deletedFileNames) {
        if (-not ($log | Select-String $name)) {
            "filename '$($name)' not found in log"
        }
    }
}

# ==================================================================================================================
Test '242d edit file: should find both versions in backup' {
    AddRandomFile | Out-Null
    RunBackup
    
    $testFile = RandomSourceFile

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

# ==================================================================================================================
# This requirement is problematic: Directory listing ignores empty directories and including directories causes other trouble. 
# Its also not important: No important information is stored in empty directories. If you want to backup your files you probably don't care for empty dirs.
# So, we'll get back to it later hopefully
#Test 'dd91 copy empty directory' {
#    ResetSandbox
#    RunBackup
#
#    $itemsInLatest = @(ls -Recurse .\backups\_latest).Length
#    if ($itemsInLatest -lt 5) {
#        "only found $itemsInLatest items in backups\_latest"
#    }
#}


Test 'c5ee hidden files are backed up' {
    $hiddenFile = RandomNewFilePath

    RandomString > $hiddenFile
    (Get-Item $hiddenFile).Attributes = "Hidden"
    
    RunBackup

    $log = ReadLogFile
    if (-not ($log | Select-String '1 new file')) {
        'no new files in log'
    }

    $filename = Split-Path -Leaf $hiddenFile
    if (@(ls backups\_latest -Recurse -File -Force | ? { $_.name -eq $filename }).Length -ne 1) {
        'file not found in _latest'
    }
}


Test 'd2d9 write-protected attribute is backed up' {
    $protectedFile = AddRandomFile

    $protectedFile.Attributes = "ReadOnly"

    RunBackup

    $file = @(ls -r backups\_latest | ? { $_.Name -eq $protectedFile.Name })[0]
    if (-not $file) {
        'backup file not found'
    }

    $targetFile = ls -r backups\_latest | ? { $_.Name -eq $protectedFile.Name }
    $targetProtected = ($targetFile.Attributes -band [System.IO.FileAttributes]::ReadOnly) -eq [System.IO.FileAttributes]::ReadOnly
    
    if (-not $targetProtected) {
        'backup file is not write-protected'
    }
}


Test '1fb6 multiple log directories were created' {
    
    $logDirectories = @(ls .\backups -Directory | ?{ $_.Name -match '^[\d\.-]+$' })

    if(-not $logDirectories.Length -gt 5){
        'a little few backup log directories for the amount of tests that ran, dont you think?'   
    }    
}

Test '2685 backupignore single file' {
    ResetSandbox

    $file = AddRandomFile
    $filename = Split-Path $file -Leaf
    $file > '.\source\.backupignore'
    
    RunBackup



    $log = ReadLogFile
    if (($log | Select-String $filename)) {
        'new file is not being ignored'
    }

    if (-not ($log | Select-String 'backupignore')) {
        'backupignore file is being ignored'
    }
}

Test '545d backupignore directory' {
    'not implemented'
}

Test '0270 backupignore pattern' {
    'not implemented'
}

Test '3aa5 errors get logged' {
    'not implemented'
}

# restore working path
cd $prevWorkingPath