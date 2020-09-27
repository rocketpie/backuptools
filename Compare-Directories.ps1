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

# ~ToString(): convert value into human readable, log-printable (one-line) string
function Print($value) {
    $value | Out-string
}

# debugging: print variable name with it's value
function DebugVar($varName) {
    $value = (get-item variable:$varName).Value
    Write-Debug "$($varName.PadRight(18)): $(Print $value)"
}

# given two *sorted* lists,
# remove all elements from the first list
# that .StartsWith any element from the second list
function ApplyExcludeList {
    param (
        [array]$Source,
        [array]$ExcludeList,
        [string]$DebugMessage
    )
    
    if (($Source.Count -lt 1) -or ($excludeList.Count -lt 1)) {
        return $Source                
    }
    
    $sourceList = [System.Collections.ArrayList]::new($Source)
    
    # sorted-walk both lists simultaneously to avoid most overhead
    $sIdx = 0 # soruce index
    $eIdx = 0 # exclude index
    do {
        $excludePattern = $excludeList[$eIdx]
        
        if ($sourceList[$sIdx].StartsWith($excludePattern)) {
            Write-Debug "$DebugMessage '$($sourceList[$sIdx])'"
            $sourceList.RemoveAt($sIdx)
        }
        else {
            $compare = $sourceList[$sIdx].CompareTo($excludePattern)
            if ($compare -lt 0) { 
                # assumption: most files are not ignored. Most common case: source file is before the next ignore pattern
                $sIdx++
            }
            elseif ($compare -gt 0) {
                $eIdx++
            }
            else <# ($compare -eq 0) #> {
                $sIdx++
                $eIdx++
            }
        }
    } while (($sourceList.Count -gt $sIdx) -and ($ExcludeList.Length -gt $eIdx))
    
    return $sourceList
}

# given two *sorted* relative file path listings, and
# $ItemsDiffer: [bool] function($filePath) a predicate that returns wether an item that's present in source and target differ
# this function returns DiffData, an object representing which items exist only in source, only in target, or both 
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

        if ($compare -eq 0) { 
            # most common case: file is up-to-date
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


$errorCountBeforeStart = $Error.Count

$SourceDir = get-item $SourcePath
$targetDir = get-item $targetPath

if ($Error.Count -ne $errorCountBeforeStart) { exit } # can't find directories or somethin

# get comparable lists of both directories
# -File to exclude empty directories (TODO: Why, exactly, is this a problem?)
# -Force to include hidden files 
# sort because Get-ChildItem produces sorted output within, but not across directories (-Recurse)
# remove common root path (including '\' that was not part of the dir.FullName) to get comparable relative names. 
$sourceFiles = @(ls -Recurse -File $SourceDir -Force | % { $_.FullName.Substring($SourceDir.FullName.Length + 1) } | sort)
$targetFiles = @(ls -Recurse -File $targetDir -Force | % { $_.FullName.Substring($targetDir.FullName.Length + 1) } | sort)

$ignoreFiles = @($sourceFiles | ? { $_.EndsWith('.backupignore') })
Debugvar ignoreFiles

$excludeList = New-Object System.Collections.ArrayList
if ($ignoreFiles.Count -gt 0) {
    
    $ignoreFiles | % {
        $fullname = Join-Path $SourceDir $_
        $patterns = @(gc $fullname)
        if ($Error.Count -ne $errorCountBeforeStart) { 
            Write-Error "cant read file: '$fullname'"
            exit 
        } 
        
        # 'a\b\.backupignore' => 'a\b\'
        $parentPath = $_.SubString(0, $_.length - '.backupignore'.Length)
        
        $patterns | ? { -not $_.StartsWith('!') } | % { 
            # 'a\b\' '\file.txt' => 'a\b\file.txt'
            $fullPattern = "$($parentPath)$($_)"

            $sourceFiles | % { # ignoreFiles -> ignorePatterns -> sourceFiles is some heavy nesting - can we optimize? maybe partially exclude during ls before merging and sorting? 
                # or maybe collect all patterns, then dedup, then sorted-walk both collections simultaneously? (don't need to test patterns 'g...' when you're at 'a...' and vice vers)

                if ($_.StartsWith($fullPattern)) {
                    $excludeList.Add($_) | Out-Null
                }
            }
        }

        $notExcludeList = New-Object System.Collections.ArrayList # find 'do-not-exclude' files by applying them like an exclude-list to the excluded files - because we already know how to do that.
        $patterns | ? { $_.StartsWith('!') } | % {
            # 'a\b\' '!file.txt' => 'a\b\file.txt'
            $fullPattern = "$($parentPath)$($_.Substring(1))"
            
            $excludeList | % {
                if ($_.StartsWith($fullPattern)) {
                    $notExcludeList.Add($_) | Out-Null
                }
            }
        }
    }

    $excludeList = @($excludeList | sort)
    $notExcludeList = @($notExcludeList | sort)
    
    Debugvar excludeList
    Debugvar notExcludeList

    $excludeList = @(ApplyExcludeList $excludeList $notExcludeList 'not-ignoring')
    $sourceFiles = @(ApplyExcludeList $sourceFiles $excludeList 'ignoring')
}

$fileDiff = DiffList $sourceFiles $targetFiles { 
    Param($filename)    
    # matching files: include in Update selection or not? 

    # -Force get-item to work with hidden files
    $sourceFile = Get-Item (Join-Path $SourcePath $filename) -Force
    $targetFile = Get-Item (Join-Path $TargetPath $filename) -Force

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