<#
	.SYNOPSIS
		Incrementally back up files to a target directory

	.DESCRIPTION
        TODO: Optimize Workflow: 
            1. diff origin <> backup
            2. move changed files backup > updated
            2. move extra files backup > deleted
            3. robocopy /mir origin > backup
	
    .EXAMPLE
        backup \sourcedir \targetdir
#>
[CmdletBinding()]
Param(	
    [Parameter(Mandatory = $true, Position = 0)]
    [string]
    $SourcePath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]
    $TargetPath,

    [Parameter(Mandatory = $false)]
    [switch]
    $Confirm,

    [Parameter(Mandatory = $false)]
    [string]
    [ValidateSet('default', 'progress', 'data')]
    $OutputBehaviour = 'default'
)

$global:OUTPUT_BEHAVIOUR_DEFAULT = 'default'
$global:OUTPUT_BEHAVIOUR_PROGRESS = 'progress'
$global:OUTPUT_BEHAVIOUR_DATA = 'data'

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}
    
# Functions ========================================================================================================
# ==================================================================================================================

# given a path to a *file*, 
# Create the file's parent directory if it does not exist.
function EnsureDirectory($filePath) {
    mkdir (Split-Path $filePath) -ErrorAction Ignore | Out-Null
}

# ~ToString(): convert value into human readable, log-printable (one-line) string
function Print($value) {
    $value | Out-string  # hack this for now...
}

# debugging: print variable name with it's value
function DebugVar($varName) {
    $value = (get-item variable:$varName).Value
    Write-Debug "$($varName.PadRight(18)): $(Print $value)"
}

# output debugging inspection
function DebugOutput($name, $value) {    
    Write-Debug "$($name.PadRight(18)): $(Print $value)"    
}

class MatchResult {
    MatchResult($isMatchValue, $newIndexValue) {
        $this.IsMatch = $isMatchValue
        $this.NewIndex = $newIndexValue
    }

    [bool]$IsMatch
    [int]$NewIndex
}

# checks if an item matches an (ignore)pattern
function PatternMatch([string]$value, [string[]]$patterns, [int]$currentIndex) {        
    $value = $value.ToLower()
    while ($patterns.Count -gt $currentIndex) {
        $pattern = $patterns[$currentIndex].ToLower()
        
        if ($value.StartsWith($pattern)) {
            return [MatchResult]::new($true, $currentIndex)
        }
        
        if ($value.CompareTo($pattern) -lt 0) {
            # need to advance $value, not $pattern
            return [MatchResult]::new($false, $currentIndex)
        }
        else {
            # test next $pattern
            $currentIndex++                
        }
    }

    # no more patterns to match against
    return [MatchResult]::new($false, $currentIndex)
}

# Preparation ======================================================================================================
# ==================================================================================================================

$priorErrorCount = $Error.Count

# Normalize SourcePath
$SourcePath = $SourcePath.Replace('/', '\')
$SourcePath = $SourcePath.TrimEnd('\') 
$SourcePath = Resolve-Path $SourcePath
DebugVar 'SourcePath'
if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot find source directory '$SourcePath'"; exit }

# resolve target path even if it does not yet exist
$TargetPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetPath)
DebugVar 'TargetPath'

# ensure target path exists
if (-not (Test-Path $TargetPath)) {
    mkdir $TargetPath | Out-Null
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot create target directory '$TargetPath'"; exit }
}

# ensure _latest path exists
$latestDirPath = Join-Path $TargetPath '_latest'
DebugVar 'latestDirPath'
if (-not (Test-Path $latestDirPath)) {
    mkdir $latestDirPath | Out-Null
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot create _latest directory '$latestDirPath'"; exit }
}

# determine and create log directory
$logDirName = "$(Get-Date -f 'yyyy-MM-dd')"
$revision = 0
do {
    $revision++
    $logDirPath = Join-Path $TargetPath "$logDirName.$revision"	
} while (Test-Path -LiteralPath $logDirPath);
DebugVar 'logDirPath'
mkdir $logDirPath | Out-Null
if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot create log directory '$logDirPath'"; exit }

# create log file
$logFile = (Join-Path $logDirPath 'log.txt')
DebugVar 'logFile'
"Backing up '$SourcePath'" >> $logFile
if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot write log file"; exit }


function Main($SourcePath, $latestDirPath, $logDirPath) {    
    $deletedDirPath = Join-Path $logDirPath deleted
    $updatedDirPath = Join-Path $logDirPath updated


    # Step 1: Determine ignore pattern =============================================================================
    # ==============================================================================================================
    $ignorePatterns = [System.Collections.Generic.List[string]]::new()
    $notIgnorePatterns = [System.Collections.Generic.List[string]]::new()
    $ignoreFiles = @(ls $SourcePath -Filter '.backupignore' -Recurse -File -Force) 
    $ignoreFiles | % {
        if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot read ignore file $($_.FullName)"; exit }
        else { Write-Debug "reading ignore file $($_.FullName)..." }
        
        # 'c:\source\subdir\.backupignore' => 'subdir\'
        # there's a bug here, when theres a .backupignore file in the root directory and the root directory ends with '\' (eg. backup c:\d\ <target> when there's a .backupignore file in c:\d\. backup c:\d <target> will work)
        $ignoreFileRelativePath = (Split-Path $_.Fullname).SubString($SourcePath.Length)
        DebugVar ignoreFileRelativePath
        
        $patterns = @(gc $_.FullName)
        $patterns = @($patterns | % { $_.Trim() } | ? { $_.Length -gt 0 })

        $patterns | % {
            if ($_.StartsWith('!')) {
                # 'a\b\' '!file.txt' => 'a\b\file.txt'
                $notIgnorePatterns.Add("$($ignoreFileRelativePath)$($_.Substring(1))") | Out-Null
            }
            else {
                # 'a\b\' '\file.txt' => 'a\b\file.txt'
                $ignorePatterns.Add("$($ignoreFileRelativePath)$($_)") | Out-Null
            }
        }
    }
    
    $ignorePatterns = @( $ignorePatterns | sort -Unique )
    $notIgnorePatterns = @( $notIgnorePatterns | sort -Unique )
    if ($OutputBehaviour -eq $global:OUTPUT_BEHAVIOUR_DEFAULT) { 
        "$($ignoreFiles.Count) ignore files"
        $ignorePatterns | % {
            "ignoring: '$_'"
        }
        $notIgnorePatterns | % {
            "not-ignoring: '$_'"
        }
    }


    # Step 2: Determine source state, honouring ignorePatterns =====================================================
    # ==============================================================================================================
    $rawSourceRelativeFilenames = @(ls $SourcePath -Recurse -File -Force | % { $_.FullName.Substring($SourcePath.Length + 1) } | sort)
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot list source files"; exit }
    
    $sourceRelativeFilenames = [System.Collections.Generic.List[string]]::new(($rawSourceRelativeFilenames.Count / 4))
    $sourceIdx = 0;
    $ignoreIdx = 0;
    $notIgnoreIdx = 0;
    while (($rawSourceRelativeFilenames.Count -gt $sourceIdx) -and ($ignorePatterns.Count -gt $ignoreIdx)) {
        $item = $rawSourceRelativeFilenames[$sourceIdx]

        $ignoreResult = PatternMatch $item $ignorePatterns $ignoreIdx
        $ignoreIdx = $ignoreResult.NewIndex 
        
        if (!$ignoreResult.IsMatch) {
            $sourceRelativeFilenames.Add($item) # result.Add
        }
        else {            
            # ignore. Except when a not-ignore pattern also matches
            $notIgnoreResult = PatternMatch $item $notIgnorePatterns $notIgnoreIdx
            $notIgnoreIdx = $notIgnoreResult.NewIndex
            
            if ($notIgnoreResult.IsMatch) {
                $sourceRelativeFilenames.Add($item) # result.Add
            }
        }

        $sourceIdx++
    }
    
    # flush remainder
    $remainingSourceItems = @($rawSourceRelativeFilenames[$sourceIdx..$rawSourceRelativeFilenames.Length])
    $remainingSourceItems | % {
        $sourceRelativeFilenames.Add($_)
    }

    if ($OutputBehaviour -eq $global:OUTPUT_BEHAVIOUR_DEFAULT) {
        "ignored $($rawSourceRelativeFilenames.Count - $sourceRelativeFilenames.Count) files"
    }
    
    # free some space
    $rawSourceRelativeFilenames = $null


    # Step 3: Determine target state ===============================================================================
    # ==============================================================================================================
    $latestBackupRelativeFilenames = @(ls $latestDirPath -Recurse -File -Force | % { $_.FullName.Substring($latestDirPath.Length + 1) } | sort)
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot list target files"; exit }
    if ($OutputBehaviour -eq $global:OUTPUT_BEHAVIOUR_DEFAULT) {
        "found $($latestBackupRelativeFilenames.Count) files already backed up"
    }

    # Step 4: Determine changes ===================================================================================
    # ==============================================================================================================
    $changes = &(join-path $PSScriptRoot Get-ListDiff.ps1) -Left $sourceRelativeFilenames -Right $latestBackupRelativeFilenames
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot Get-ListDiff"; exit }
    
    if ($OutputBehaviour -eq $global:OUTPUT_BEHAVIOUR_DATA) {
        $changes
        return
    }

    # filter Update selection by actual file difference since last backup
    $rawUpdateCount = $changes.Both.Count
    $update = [System.Collections.Generic.List[string]]::new()
    $changes.Both | % { 
        $sourceFile = Get-Item (Join-Path $SourcePath $_) -Force
        $targetFile = Get-Item (Join-Path $latestDirPath $_) -Force
        
        $wtChanged = $sourceFile.LastWriteTime -ne $targetFile.LastWriteTime
        $ltChanged = $sourceFile.Length -ne $targetFile.Length
        if ($wtChanged -or $ltChanged) {
            Write-Debug "update found: writeTime:$($sourceFile.LastWriteTime):vs:$($targetFile.LastWriteTime) ($($wtChanged)) length:$($sourceFile.Length):vs:$($targetFile.Length) ($($ltChanged))"
            $update.Add($_)
        }
    }    
    $changes.Both = $update
    if ($Error.Count -gt $priorErrorCount) { Write-Error "error filtering update selection"; exit }    
    if ($OutputBehaviour -eq $global:OUTPUT_BEHAVIOUR_DEFAULT) {
        "skipped $($rawUpdateCount - $changes.Both.Count) unmodified files"    
    }

    # Step 5: (Report), Confirm ====================================================================================
    # ==============================================================================================================

    "$($changes.Left.Count) new files, $($changes.Both.Count) files changed, $($changes.Right.Count) files deleted"
    if (-not $Confirm) {
        if ('y' -ne (Read-Host 'Sounds right? (y)').ToLower()) {
            $changes
            Exit;
        }   
    }  

    #$total = $changes.Left.Count + $changes.Both.Count + $changes.Right.Count
    #$progress = 0;    
     
    # Step 6: Ready, Set, GO! ======================================================================================
    # ==============================================================================================================
    $changes.Right | % { 
        if ($OutputBehaviour -eq $global:OUTPUT_BEHAVIOUR_DEFAULT) {
            "deleted: $_"
        }
        
        EnsureDirectory (Join-Path $deletedDirPath $_)
        mv -LiteralPath (Join-Path $latestDirPath $_) -Destination (Join-Path $deletedDirPath $_) 
    }

    # step 3: Move all updated files, back up new version
    $changes.Both | % { 
        if ($OutputBehaviour -eq $global:OUTPUT_BEHAVIOUR_DEFAULT) {
            "updated: $_"
        }
        
        EnsureDirectory (Join-Path $updatedDirPath $_)
        mv -LiteralPath (Join-Path $latestDirPath $_) -Destination (Join-Path $updatedDirPath $_) 

        EnsureDirectory (Join-Path $latestDirPath $_)
        cp -LiteralPath (Join-Path $SourcePath $_) -Destination (Join-Path $latestDirPath $_)
    }

    # step 4: back up new files
    $changes.Left | % {
        if ($OutputBehaviour -eq $global:OUTPUT_BEHAVIOUR_DEFAULT) {
            "new file: $_"
        }

        EnsureDirectory (Join-Path $latestDirPath $_)
        cp -LiteralPath (Join-Path $SourcePath $_) -Destination (Join-Path $latestDirPath $_) 
    }
}

if ($OutputBehaviour -eq $global:OUTPUT_BEHAVIOUR_DATA) {
    Main $SourcePath $latestDirPath $logDirPath
}
else {
    Main $SourcePath $latestDirPath $logDirPath 2>&1 | % { $_ >> $logFile; $_ }
}
