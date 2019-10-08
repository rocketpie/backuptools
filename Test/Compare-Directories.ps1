<#
	.SYNOPSIS
		Compare two directories

	.DESCRIPTION
        list items present in sourcePath only, as well as items in targetPath only
        
        Problem: ls lists dirs and files, so .\source\5 (dir) can be confused with .\backups\5 (file)
        Option A: ls -Directory first, then a second pass with ls -File
        Option B: git style ignore directories, compare files only
        Option C: ignore, run into derived problems later.

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

$ecnt = $Error.Count

$SourceDir = get-item $SourcePath
$targetDir = get-item $targetPath

if ($Error.Count -ne $ecnt) { exit } # can't find directories or somethin

$result = New-Object psobject -Property @{
    'Total' = 0; # total number of differences
    'Enter' = @(); # files added in $source, not present in $target
    'Exit'  = @() # files not in #source, but present in $target
};

# get sorted lists of both directories
# remove common root path (including '\' that was not part of the dir.FullName) to get comparable relative names. 
# They come sorted from ls, but for good measure, ensure alphabetic sorting.
$sourceFiles = @(ls -Recurse $SourceDir | %{ $_.FullName.Substring($SourceDir.FullName.Length + 1) } | sort)
$targetFiles = @(ls -Recurse $targetDir | %{ $_.FullName.Substring($targetDir.FullName.Length + 1) } | sort)
    
# step through both sorted lists in sync, sorting mismatches on the go
$sIdx = 0;
$tIdx = 0;
$hasNext = ($sourceFiles.Length -gt 0) -and ($targetFiles.Length -gt 0)   
while ($hasNext) {
    $compare = $sourceFiles[$sIdx].CompareTo($targetFiles[$tIdx])

    Write-Debug "'$($sourceFiles[$sIdx])'.CompareTo('$($targetFiles[$tIdx])'): $compare"
    if ($compare -eq 0) {
        $sIdx++;
        $tIdx++;
    }
    elseif ($compare -gt 0) {
        # 1 == 'b'.CompareTo('a') => source is ahead of target, indicating a file in target that's missing in source
        $result.Exit += @($targetFiles[$tIdx])
        $tIdx++;
    }
    else <# ($compare -lt 0) #> {
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

$result.Total = $result.Enter.Length + $result.Exit.Length

$result