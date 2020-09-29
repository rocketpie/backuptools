<#
	.SYNOPSIS
		Find the difference between two lists

	.DESCRIPTION
        returns a ListDiff {            
            [int]Total
            # items present in $Left but not $Right
            [string[]]Left
            # items present in both $Left and $Right
            [string[]]Both
            # items only present $Right
            [string[]]Right
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
        Get-ListDiff -Left @('1', '2', '3') -Right @('2', '3', '4')
        => { Left:['1'], Both:['2','3'], Right:['4'] }
#>
[CmdletBinding()]
Param(	
    [Parameter(Mandatory = $false)]
    [string[]]
    $Left,

    [Parameter(Mandatory = $false)]
    [string[]]
    $Right
)

class ListDiff {
    ListDiff() {
        $this.Left = [System.Collections.Generic.List[string]]::new()
        $this.Both = [System.Collections.Generic.List[string]]::new()
        $this.Right = [System.Collections.Generic.List[string]]::new()
    }

    [System.Collections.Generic.List[string]]$Left
    [System.Collections.Generic.List[string]]$Both
    [System.Collections.Generic.List[string]]$Right
}

$result = New-Object ListDiff
    
# step through both sorted lists in sync, sorting mismatches on the go
$leftIdx = 0;
$rightIdx = 0;
while (($left.Length -gt $leftIdx) -and ($Right.Length -gt $rightIdx)) {
    $leftItem = $Left[$leftIdx]
    $rightItem = $Right[$rightIdx]
    $compare = $leftItem.CompareTo($rightItem)

    if ($compare -eq 0) { 
        # most common case: same 
        $leftIdx++;
        $rightIdx++;
        $result.Both.Add($leftItem)
    }
    elseif ($compare -gt 0) {
        # 1 == 'b'.CompareTo('a') => left is ahead of right, indicating a file in right that's missing in left
        $result.Right.Add($rightItem)
        $rightIdx++;
    }
    else <# ($compare -lt 0) #> {
        # -1 == 'a'.CompareTo('b') => left is behind on right, indicating an extra file in left
        $result.Left.Add($leftItem)
        $leftIdx++;
    }
}

# flush remainder
$remainingSourceItems = @($Left[$leftIdx..$Left.Length])
$remainingSourceItems | %{
    $result.Left.Add($_)
}
    
$remainingTargetItems = @($Right[$rightIdx..$Right.Length])
$remainingTargetItems | %{
    $result.Right.Add($_)
}


return $result