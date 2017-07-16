[CmdletBinding()]
Param(
    [Parameter()]
    [string]
    $Source = 'C:\D\tmp\test\src',

    [Parameter()]
    [string]
    $Target = 'C:\D\tmp\test\target'
)

$Debug = $false; if($PSBoundParameters['Debug']) { $Debug = $true }
if($Debug){ $DebugPreference = 'Continue' }

$jid = 0
$next = -1
$testContent = [String[]]::new(100)
for( $i = 0; $i -lt $testContent.Length; $i++){
    $testContent[$i] = [guid]::NewGuid().ToString() 
}

function Test ($isOk, $message) {
    if($isOk) {
        "OK: $message"
    }
    else {
        Write-Error "FAIL: $message"
    }
}

# Cleanup =============================================================================================================
# =====================================================================================================================

rm -Recurse -Force $Source
mkdir $Source | Out-Null

rm -Recurse -Force $Target
mkdir $Target | Out-Null

# Test initial backup =================================================================================================
# =====================================================================================================================

# Prepare some Test data
$testContent[($next++)] > (join-path $Source 'root dir file.txt')         

mkdir (join-path $Source 'subfolder') | Out-Null
$testContent[($next++)] > (join-path $Source (join-path 'subfolder' 'subfolder file.txt'))

Test ((ls $Target).Length -eq 0) "empty '$Target' before testing"
$jid++; Create-Backup $Source $Target | Out-Null
Test ((ls -r $Target).Length -eq 11) 'expect right number of files after initial backup' # _journal and dir, _latest, content (3) and checksum, backup and content 

# Add/rm dirs/files ===================================================================================================
# =====================================================================================================================

#add new file
$testContent[($next++)] > (join-path $Source 'new file.txt')         

# deleted file
rm (join-path $Source 'root dir file.txt')   

$jid++; Create-Backup $Source $Target -Debug -Verbose | Out-Null
Test (-not [System.IO.File]::Exists((join-path $Target '_latest\root dir file.txt'))) '_latest entry is removed'
Test ((ls -r $Target | ?{ $_.FullName -match "_journal.+\.$jid" } | gc | Select-String -SimpleMatch 'removed 1 files, added 1 files, updated 0 files').Length -eq 1) "journal tracks removed / added files" 

# add/rm subdir 
# add/rm new file in subdir 
# add/rm new file in new subdir 
# debug and verbose output

# update files ========================================================================================================
# =====================================================================================================================

# update file    
# move file inside dir
# move file across dir (up/down)
# move dir
# debug and verbose output

# hidden files, .git, ...
# debug and verbose output

$testContent[($next++)] > (join-path $Source 'ignored file.txt')     
'ignored file.txt' > (Join-Path $Target '_ignore')
$jid++; Create-Backup $Source $Target -Debug -Verbose | Out-Null
Test (-not [System.IO.File]::Exists((Join-Path $Target "$(Get-Date -Format 'yyyyMMdd').$jid\ignored file.txt"))) '_gnored file is not backed up'
Test ((ls -r $Target | ?{ $_.FullName -match "_journal.+\.$jid" } | gc | Select-String "VERBOSE: _ignore '.+?ignored file.txt'").Length -eq 1) 'verbose lists ignored file'

# ignore directories
# debug and verbose output

# special cases
New-Item -ItemType File -Value $testContent[($next++)] -Path (join-path $Source 'file with [].txt') | Out-Null
New-Item -ItemType Directory -Path (join-path $Source 'folder[]') | Out-Null
New-Item -ItemType File -Value $testContent[($next++)] -Path (join-path $Source 'folder[]\file2.txt') | Out-Null
New-Item -ItemType File -Value $testContent[($next++)] -Path (join-path $Source 'folder[]\file3 with [].txt') | Out-Null
$jid++; Create-Backup $Source $Target -Debug | Out-Null
Test ([System.IO.File]::Exists((Join-Path $Target "$(Get-Date -Format 'yyyyMMdd').$jid\file with [].txt"))) "files with '[]' in their name get backed up"
Test ([System.IO.File]::Exists((Join-Path $Target "$(Get-Date -Format 'yyyyMMdd').$jid\folder[]\file3 with [].txt"))) "folders with '[]' in their name get backed up"

# test -VerifyHash
