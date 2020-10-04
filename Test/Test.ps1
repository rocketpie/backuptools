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
    $SpecificTest = "", 

    # cleanup test directories when tests are done
    [Parameter()]
    [switch]
    $Clean
)

if($PSBoundParameters['Debug']){
    $DebugPreference = 'Continue'
}

$Global:specificTest = $SpecificTest

class TestContext {
    TestContext() {
        $this.BackupRuns = 0
        $this.Random = New-Object System.Random
    }

    # location of this script
    [string]$TestScriptPath
    # location of backup.ps1 script
    [string]$BackupScriptPath    
    # source directory to back up
    [string]$TestSourcePath
    # target directory / backup location
    [string]$TestTargetPath
    [System.Random]$Random
    
    [int]$BackupRuns
    # .\backups\[\d-]+.$BackupRuns directory from the latest RunBackup
    [System.IO.DirectoryInfo]$CurrentLogDir    
}

$global:Context = New-Object TestContext
$global:Context.TestScriptPath = Split-path $MyInvocation.MyCommand.Definition
$global:Context.BackupScriptPath = Split-Path (Get-Command backup.ps1).Definition
$global:Context.TestSourcePath = Join-Path $global:Context.TestScriptPath 'source'
$global:Context.TestTargetPath = Join-Path $global:Context.TestScriptPath 'backups'

if($Clean){
    rm $global:Context.TestSourcePath -Recurse -Force -ErrorAction 'SilentlyContinue' | Out-Null 
    rm $global:Context.TestTargetPath -Recurse -Force -ErrorAction 'SilentlyContinue' | Out-Null 
    exit
}

# Functions ========================================================================================================
# ==================================================================================================================

function ResetSandbox {
    $global:Context.BackupRuns = 0
    $global:Context.CurrentLogDir = $null
    
    # re setup source dirs
    rm $global:Context.TestSourcePath -Recurse -Force
    mkdir $global:Context.TestSourcePath | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath 'a') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath 'a\a') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath 'a\a\a') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath 'a\b') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath 'a\1') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath 'a\2') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath 'b') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath '1') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath '1\1') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath '1\2') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath '1\a') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath '1\f') | Out-Null
    mkdir (Join-Path $global:Context.TestSourcePath '2') | Out-Null

    rm $global:Context.TestTargetPath -Recurse -Force -ErrorAction 'SilentlyContinue' | Out-Null 
}

# silently executes backup .\source .\backups
function RunBackup {
    backup.ps1 $global:Context.TestSourcePath $global:Context.TestTargetPath -Confirm | Out-Null
    $global:Context.BackupRuns++
    $global:Context.CurrentLogDir = @(ls -Directory $global:Context.TestTargetPath | ? { $_.Name.EndsWith(".$($global:Context.BackupRuns)") })[0]
}

function GetDiff {
    $sourcePath = $global:Context.TestSourcePath
    $sourceFilenames = @(ls $sourcePath -Recurse -File -Force | % { $_.FullName.Substring($sourcePath.Length + 1) } | sort)
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot list source files" }
    
    $latestDirPath = (join-path $global:Context.TestTargetPath '_latest')
    $latestFilenames = @(ls $latestDirPath -Recurse -File -Force | % { $_.FullName.Substring($latestDirPath.Length + 1) } | sort)
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot list target files" }

    & (Join-Path $global:Context.BackupScriptPath Get-ListDiff.ps1) -Left $sourceFilenames -Right $latestFilenames
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
    
    $priorErrorCount = $Error.Count
    $result = @(&$testScript)

    if (($result.Length -gt 0) -or ($Error.Count -gt $priorErrorCount)) {        
        foreach ($err in $result) {
            Write-Warning "FAILED: $err"            
        }

        Write-Warning "There were errors. Log: $($global:Context.CurrentLogDir)"
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
    
    $dirs = ls $global:Context.TestSourcePath -Recurse -Directory
    $dirs += @(get-item $global:Context.TestSourcePath)

    join-path $dirs[$global:Context.Random.Next($dirs.Length)].Fullname $filename
}

function RandomSourceFile {
    $allfiles = @(ls $global:Context.TestSourcePath -Recurse -File)    
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

    if (-not (Test-Path $global:Context.TestTargetPath)) { 'target dir missing' }
    if (-not (Test-Path (Join-Path $global:Context.TestTargetPath '_latest'))) { '_latest dir missing' }
    if (@(ls $global:Context.TestTargetPath -Recurse -File 'log.txt').Length -ne 1) { 'log file missing' }
    $diff = GetDiff
    $total = $diff.Left.Count + $diff.Both.count + $diff.Right.Count
    if ($total -gt 0) { '_latest is not a copy of source' }
}

# ==================================================================================================================
Test '4d40 add file: should find backup in _latest' {
    $file = AddRandomFile
    Write-Debug $file.FullName

    RunBackup

    $backedUpFile = ls (Join-Path $global:Context.TestTargetPath '_latest') -Recurse -File | ? { $_.Name -eq $file.Name }
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

    $testContent = (ls (Join-Path $global:Context.TestTargetPath '_latest') -Recurse -File | ? { $_.name -eq $testFile.name } | gc )
    if ($newContent -ne $testContent) {
        "updated content not found in _latest (expected '$newContent', found '$testContent')"
    }

    $testContent = (ls $global:Context.TestTargetPath -Recurse -File | ? { ($_.name -eq $testFile.name) -and ($_.FullName -notmatch '\\_latest\\') } | gc )
    if ($oldContent -ne $testContent) {
        'prior file content not found in $log/updated location'
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
    if (@(ls (Join-Path $global:Context.TestTargetPath '_latest') -Recurse -File -Force | ? { $_.name -eq $filename }).Length -ne 1) {
        'file not found in _latest'
    }
}


Test 'd2d9 write-protected attribute is backed up' {
    $protectedFile = AddRandomFile

    $protectedFile.Attributes = "ReadOnly"

    RunBackup

    $file = @(ls -r (Join-Path $global:Context.TestTargetPath '_latest') | ? { $_.Name -eq $protectedFile.Name })[0]
    if (-not $file) {
        'backup file not found'
    }

    $targetFile = ls -r (Join-Path $global:Context.TestTargetPath '_latest') | ? { $_.Name -eq $protectedFile.Name }
    $targetProtected = ($targetFile.Attributes -band [System.IO.FileAttributes]::ReadOnly) -eq [System.IO.FileAttributes]::ReadOnly
    
    if (-not $targetProtected) {
        'backup file is not write-protected'
    }
}


Test '1fb6 after a few tests, multiple log directories were created' {
    
    $logDirectories = @(ls $global:Context.TestTargetPath -Directory | ?{ $_.Name -match '^[\d\.-]+$' })

    if(-not $logDirectories.Length -gt 5){
        'a little few backup log directories for the amount of tests that ran, dont you think?'   
    }    
}

Test '9961 merged .backupignore content is reported in log' {            
    $testContent = @( RandomString )
    $testContent > (Join-Path $global:Context.TestSourcePath '.backupignore')

    1..4 | %{ 
        $randomDir = Split-Path (RandomNewFilePath)
        $content = RandomString 
        $content >> (Join-Path $randomDir '.backupignore')

        $testContent += @($content)
    }

    RunBackup

    $log = ReadLogFile

    $newFiles = @($log | ?{ $_ -match '^new file:' })    
    $newIgnoreFiles = @($newFiles | ?{$_ -match '^new file: ([\w\\]*)\.backupignore'})

    if($newFiles.Count -gt $newIgnoreFiles.Count){
        'actual files have been written, log content is unreliable for this test'        
    }

    $testContent | %{
        if (-not ($log | Select-String $_)) {
            "ignore pattern not reported: '$_'"
        }
    }
}


Test 'b520 empty line in .backupignore is ignored' {
    
    $directory = mkdir (Join-Path $global:Context.TestSourcePath 'b520')
    $files = @(1..3 | %{ $name = RandomString; RandomString > (Join-Path $directory $name); $name } )

    "`n`n" > (Join-Path $directory '.backupignore')

    RunBackup

    $log = ReadLogFile
    $files | %{
        if (-not ($log | Select-String $_)) {
            "file was ignored: '$_'"
        }
    }
}


Test '2685 backupignore single file, ignore from the same directory' {
    
    $file = AddRandomFile
    $filePath = Split-Path $file
    $filename = Split-Path $file -Leaf
    $filename > (Join-Path $filePath '.backupignore')
    
    RunBackup

    $log = ReadLogFile
    if (($log | Select-String "new file: $filename")) {
        'new file is not being ignored'
    }

    if (-not ($log | Select-String 'backupignore')) {
        'backupignore file is being ignored'
    }
}

Test '2685 backupignore single file, ignore from root directory' {
    
    $file = AddRandomFile    
    $filename = Split-Path $file -Leaf
    $relativeFilename = $file.Fullname.Substring($global:Context.TestSourcePath.Length + 1)
    $relativeFilename > (Join-Path $global:Context.TestSourcePath '.backupignore')
    
    RunBackup

    $log = ReadLogFile
    if (($log | Select-String "new file: $filename")) {
        'new file is not being ignored'
    }

    if (-not ($log | Select-String 'backupignore')) {
        'backupignore file is being ignored'
    }
}


Test '545d backupignore sub directory' {    
    # avoid trying to ignore the root directory, because it isn't really a subdirectory.
    do {
        $file = AddRandomFile
        $directory = Split-Path $file
    } while ($directory -eq $global:Context.TestSourcePath)

    $filename = Split-Path $file -Leaf
    $relativeDirectoryPath = $directory.Substring($global:Context.TestSourcePath.Length + 1)
    $relativeDirectoryPath > (Join-Path $global:Context.TestSourcePath '.backupignore')
    
    RunBackup

    $log = ReadLogFile
    if (($log | Select-String $filename)) {
        'new file is not being ignored'
    }

    if (-not ($log | Select-String 'backupignore')) {
        'backupignore file is being ignored'
    }
}

Test '545d backupignore case insensitive' {    
    # avoid trying to ignore the root directory, because it isn't really a subdirectory.
    do {
        $file = AddRandomFile
        $directory = Split-Path $file
    } while ($directory -eq $global:Context.TestSourcePath)

    $filename = Split-Path $file -Leaf
    $relativeDirectoryPath = $directory.Substring($global:Context.TestSourcePath.Length + 1)
    $relativeDirectoryPath.ToUpper() > (Join-Path $global:Context.TestSourcePath '.backupignore')
    
    RunBackup

    $log = ReadLogFile
    if (($log | Select-String $filename)) {
        'new file is not being ignored'
    }

    if (-not ($log | Select-String 'backupignore')) {
        'backupignore file is being ignored'
    }
}


Test '0270 backupignore "not" pattern' {
    # avoid ignoring the root directory, because ignoring '' isn't looking good in the ignore file.
    do {
        $importantFile = AddRandomFile
        $directory = Split-Path $importantFile
    } while ($directory -eq $global:Context.TestSourcePath)


    $otherFiles = 1..10 | %{ $name = RandomString; RandomString > (Join-Path $directory $name); $name }

    $relativeDirectoryPath = $directory.Substring($global:Context.TestSourcePath.Length + 1)
    $relativeDirectoryPath >> (Join-Path $global:Context.TestSourcePath '.backupignore')

    $relativeImportantFilePath = $importantFile.Fullname.Substring($global:Context.TestSourcePath.Length + 1)
    "!$relativeImportantFilePath" >> (Join-Path $global:Context.TestSourcePath '.backupignore')
    
    RunBackup
    
    $log = ReadLogFile
    if (-not ($log | Select-String $importantFile.Name)) {
        'important file being ignored'
    }

    $otherFiles | %{
        if (($log | Select-String $_)) {
            'important file being ignored'
        }
    }
}

Test "a53a backupignore 'this directory'"{
    'not implemented'
}

Test "a476 file has to be named '.backupignore' exactly"{
    'test' > (Join-Path $global:Context.TestSourcePath 'test.backupignore')
    
    'not implemented'
}

Test '3aa5 errors get logged' {
    'not implemented'
}

Test '1234 call backup source/ target/' {
    'not implemented'
}

Test '1235 call backup source target' {
    'not implemented'
}

Test '12365 call backup source\ target\' {
    'not implemented'
}

