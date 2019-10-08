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

# expects 'True' or $true to be returned on success, else is failed
function Test($name, $testScript) {
    $result = &$testScript
    if ($result.ToString() -eq 'True') {
        "PASSED: $name"
    }
    else {
        Write-Error "FAILED: $name"
    }
}

# interprets objects returned from tests as errors
function TestV2($name, $testScript) {
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

function Diff($sourceDir, $targetDir) {
    $sourceDir = get-item $sourceDir
    $targetDir = get-item $targetDir

    $result = New-Object psobject -Property @{
        'Total' = 0; 
        'Enter' = @(); 
        'Exit'  = @()
    };

    # get sorted lists of both directories
    # remove common root path (including '\' that was not part of the dir.FullName) to get comparable relative names. 
    # They come sorted from ls, but for good measure, ensure alphabetic sorting.
    $sourceFiles = @(ls -Recurse $sourceDir) | % { $_.FullName.Substring($sourceDir.FullName.Length + 1) } | sort
    $targetFiles = @(ls -Recurse $targetDir) | % { $_.FullName.Substring($targetDir.FullName.Length + 1) } | sort
    
    # step through both sorted lists in sync, sorting mismatches on the go
    $sIdx = 0;
    $tIdx = 0;
    $hasNext = ($sourceFiles.Length -gt 0) -and ($targetFiles.Length -gt 0)   
    while ($hasNext) {
        $compares = $sourceFiles[$sIdx].CompareTo($targetFiles[$tIdx])

        if ($compare -eq 0) {
            $sIdx++;
            $tIdx++;
        }
        elseif ($compare -gt 0) {
            # 1 == 'b'.CompareTo('a') => source is ahead of target, indicating a file in target that's missing in source
            $result.Exit += @($targetFiles[$tIdx])
            $tIdx++;
        }
        elseif ($compare -lt 0) {
            # -1 == 'a'.CompareTo('b') => source is behind on target, indicating an extra file in source
            $result.Enter += @($sourceFiles[$sIdx])
            $sIdx++;
        }
        
        $hasNext = ($sourceFiles.Length -gt $sIdx) -and ($targetFiles.Length -gt $tIdx)
    }

    # flush remainder
    $remainingSourceFiles = $sourceFiles[$sIdx..$sourceFiles.Length]
    if ($remainingSourceFiles) {
        $result.Enter += @($remainingSourceFiles)
    }
    
    $remainingTargetFiles = $targetFiles[$tIdx..$targetFiles.Length]
    if ($remainingTargetFiles) {
        $result.Exit += @($remainingTargetFiles)
    }

    $result
}

# Tests ============================================================================================================
# ==================================================================================================================

ResetSandbox

TestV2 'run without backup dir existing should create backup dir, copy of source, and journal' {
    RunBackup

    if (-not (Test-Path .\backups)) { 'target dir missing' }
    if (-not (Test-Path .\backups\_latest)) { '_latest dir missing' }
}

Test 'add file: should find backup in _latest' {
    RunBackup
    $file = AddRandomFile
    RunBackup

    @(ls .\backups\_latest -Recurse -File (split-path -leaf $file)).Length -eq 1
}

Test 'edit file: should find both versions in backup' {
    $false
}

$leftover = DeleteRandomFile
while ($leftover) {
    $leftover = DeleteRandomFile
}

# restore working path
cd $prevWorkingPath