[CmdletBinding()]
Param(
    [Parameter()]
    [string]
    $Source = 'C:\D\tmp\test\src',

    [Parameter()]
    [string]
    $Target = 'C:\D\tmp\test\target'
)

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
$testContent[0] > (join-path $Source 'root dir file.txt')         

mkdir (join-path $Source 'subfolder') | Out-Null
$testContent[1] > (join-path $Source (join-path 'subfolder' 'subfolder file.txt'))

Test ((ls $Target).Length -eq 0) "empty '$Target' before testing"
Create-Backup $Source $Target
Test ((ls -r $Target).Length -eq 11) 'expect right number of files after initial backup' # _journal and dir, _latest, content (3) and checksum, backup and content 

# Add/rm dirs/files ===================================================================================================
# =====================================================================================================================

#add new file
$testContent[3] > (join-path $Source 'new file.txt')         

# deleted file
rm (join-path $Source 'root dir file.txt')   

Create-Backup $Source $Target
Test (-not [System.IO.File]::Exists((join-path $Target '_latest\root dir file.txt'))) '_latest entry is removed'
Test ((ls -r $Target | ?{ $_.FullName -match '_journal.+\.2' } | gc | Select-String 'removed 1 files, added 1 files, updated 0 files').Length -eq 1) "journal reflects changes"  

# add/rm subdir 
# add/rm new file in subdir 
# add/rm new file in new subdir 

# update files ========================================================================================================
# =====================================================================================================================

# update file    
# move file inside dir
# move file across dir (up/down)
# move dir