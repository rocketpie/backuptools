<#
	.SYNOPSIS
		Compare two directories

	.DESCRIPTION
        list items present in sourcePath only, as well as items in targetPath only
        
        Problem: ls lists dirs and files, so .\source\5 (dir) can be confused with .\backups\5 (file)
        Option A: ls -Directory first, then a second pass with ls -File
        Option B: git style ignore directories, compare files only
        Option C: ignore, run into derived problems later.

        Option A sounds the smartest here, but poses a few problems:
        first, the copy procedure needs to be way more elaborate, because cp src/dir bck/dir also copies all the files inside.
        So cp src/newdir might be easy, simply skipping everything under newdir, updates and rm are harder.
        rm might ignore all errors on rm newdir/file after newdir has been deleted
        update will need to ignore newdir.

        that means cp $item needs to behave differently for files and dirs requiring lots of if's.
        Option B shines here, ignoring dirs eliminates if(isDir) {} altogether.
        
        Enter Option B2: ignore directories + treat empty directories as files
        an empty directory does not pose any of the mentioned challenges.
        It needs never be included in the Update selection and can be cp'ed and rm'd like a file.

        right?
        What if the directory is only empty on one side?
        I'll leave dirs for now and stick with files only.


    .EXAMPLE
        Compare-Directories \sourcedir \targetdir
#>
[CmdletBinding()]
Param(	
    [Parameter(Mandatory = $true, Position = 0)]
    [string]
    $SourcePath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]
    $TargetPath
)

class DiffData {
    DiffData() {
        $this.Enter = [System.Collections.Generic.List[string]]::new()
        $this.Update = [System.Collections.Generic.List[string]]::new()
        $this.Exit = [System.Collections.Generic.List[string]]::new()
    }

    [int]$Total
    [System.Collections.Generic.List[string]]$Enter
    [System.Collections.Generic.List[string]]$Update
    [System.Collections.Generic.List[string]]$Exit
}

# $compareItems: function($item) { [bool] } predicate: return if items present in source and target differ
function DiffList([string[]]$sourceList, [string[]]$targetList, $ItemsDiffer) {
    $result = New-Object DiffData
    
    # step through both sorted lists in sync, sorting mismatches on the go
    $sIdx = 0;
    $tIdx = 0;
    $hasNext = ($sourceList.Length -gt 0) -and ($targetList.Length -gt 0)   
    while ($hasNext) {
        $sourceItem = $sourceList[$sIdx]
        $targetItem = $targetList[$tIdx]
        $compare = $sourceItem.CompareTo($targetItem)

        Write-Debug "'$sourceItem'.CompareTo('$targetItem'): $compare"
        if ($compare -eq 0) {
            $sIdx++;
            $tIdx++;
            if ([bool](&$ItemsDiffer $sourceItem)) {
                $result.Update.Add($sourceItem)
            }
        }
        elseif ($compare -gt 0) {
            # 1 == 'b'.CompareTo('a') => source is ahead of target, indicating a file in target that's missing in source
            $result.Exit.Add($targetItem)
            $tIdx++;
        }
        else <# ($compare -lt 0) #> {
            # -1 == 'a'.CompareTo('b') => source is behind on target, indicating an extra file in source
            $result.Enter.Add($sourceItem)
            $sIdx++;
        }
            
        $hasNext = ($sourceList.Length -gt $sIdx) -and ($targetList.Length -gt $tIdx)
    }

    # flush remainder
    $remainingSourceFiles = $sourceFiles[$sIdx..$sourceFiles.Length]
    foreach ($item in $remainingSourceFiles) {
        $result.Enter.Add($item)
    }
        
    $remainingTargetFiles = $targetFiles[$tIdx..$targetFiles.Length]
    foreach ($item in $remainingTargetFiles) {
        $result.Exit.Add($item)
    }

    $result.Total = $result.Enter.Count + $result.Update.Count + $result.Exit.Count
    $result
}


$ecnt = $Error.Count

$SourceDir = get-item $SourcePath
$targetDir = get-item $targetPath

if ($Error.Count -ne $ecnt) { exit } # can't find directories or somethin

# get sorted file lists of both directories
# remove common root path (including '\' that was not part of the dir.FullName) to get comparable relative names. 
$sourceFiles = @(ls -Recurse -File $SourceDir | % { $_.FullName.Substring($SourceDir.FullName.Length + 1) })
$targetFiles = @(ls -Recurse -File $targetDir | % { $_.FullName.Substring($targetDir.FullName.Length + 1) })

$fileDiff = DiffList $sourceFiles $targetFiles { 
    Param($filename)    
    # matching files: include in Update selection or not? 

    $sourceFile = Get-Item (Join-Path $SourcePath $filename)
    $targetFile = Get-Item (Join-Path $TargetPath $filename)

    if ($sourceFile.Length -ne $targetFile.Length) {
        Write-Debug "different Length"
        return $true;
    }

    if ($sourceFile.LastWriteTime -ne $targetFile.LastWriteTime) {
        Write-Debug "different LastWriteTime"
        return $true;
    }
                
    Write-Debug "not modified: $filename"
    return $false;
}
            
$fileDiff