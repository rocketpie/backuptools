<#
	.SYNOPSIS
		Find the difference between two lists

	.DESCRIPTION
        returns a ListDiff {            
            [int]Total
            # items present in $Source but not $Target
            [string[]]Enter
            # items present in both $Source and $Target
            [string[]]Update
            # items only present $Target
            [string[]]Exit
        }
    
    .NOTES
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
        Get-ListDiff @('1', '2', '3') @('2', '3', '4')
        => { Total:4, Enter:['4'], Update:['2','3'], Exit:['1'] }
#>
[CmdletBinding()]
Param(	
    [Parameter(Mandatory = $true)]
    [string[]]
    $Source,

    [Parameter(Mandatory = $true)]
    [string[]]
    $Target
)

class ListDiff {
    ListDiff() {
        $this.Enter = [System.Collections.Generic.List[string]]::new()
        $this.Update = [System.Collections.Generic.List[string]]::new()
        $this.Exit = [System.Collections.Generic.List[string]]::new()
    }

    [int]$Total
    [System.Collections.Generic.List[string]]$Enter
    [System.Collections.Generic.List[string]]$Update
    [System.Collections.Generic.List[string]]$Exit
}

$result = New-Object ListDiff
    
# step through both sorted lists in sync, sorting mismatches on the go
$sourceIdx = 0;
$targetIdx = 0;
$hasNext = ($Source.Length -gt 0) -and ($Target.Length -gt 0)   
while ($hasNext) {
    $sourceItem = $Source[$sourceIdx]
    $targetItem = $Target[$targetIdx]
    $compare = $sourceItem.CompareTo($targetItem)

    if ($compare -eq 0) { 
        # most common case: same 
        $sourceIdx++;
        $targetIdx++;
        $result.Update.Add($sourceItem)
    }
    elseif ($compare -gt 0) {
        # 1 == 'b'.CompareTo('a') => source is ahead of target, indicating a file in target that's missing in source
        $result.Exit.Add($targetItem)
        $targetIdx++;
    }
    else <# ($compare -lt 0) #> {
        # -1 == 'a'.CompareTo('b') => source is behind on target, indicating an extra file in source
        $result.Enter.Add($sourceItem)
        $sourceIdx++;
    }
        
    $hasNext = ($Source.Length -gt $sourceIdx) -and ($Target.Length -gt $targetIdx)
}

# flush remainder
$remainingSourceFiles = @($Source[$sourceIdx..$Source.Length])
$result.Enter.AddRange($remainingSourceFiles)
    
$remainingTargetFiles = @($Target[$targetIdx..$Target.Length])
$result.Exit.AddRange($remainingTargetFiles)


$result.Total = $result.Enter.Count + $result.Update.Count + $result.Exit.Count
return $result