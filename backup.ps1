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
    $Confirm
)

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

function PatternMatch([string]$value, [string[]]$patterns, [int]$currentIndex) {        
    while ($patterns.Count -gt $currentIndex) {
        $pattern = $patterns[$currentIndex]
        
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
Write-Debug $MyInvocation.Line

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
        $patterns = @(gc $_)
        if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot read ignore file $($_.FullName)"; exit }

        # 'c:\source\subdir\.backupignore' => 'subdir\'
        $fileRelativePath = $_.Fullname.SubString($SourcePath.Length + 1, ($_.Fullname.length - 1 - $SourcePath.Length - ('.backupignore'.Length)))
        DebugVar parentPath
            
        $patterns | % {
            if ($_.StartsWith('!')) {
                # 'a\b\' '!file.txt' => 'a\b\file.txt'
                $notIgnorePatterns.Add("$($fileRelativePath)$($_.Substring(1))") | Out-Null
            }
            else {
                # 'a\b\' '\file.txt' => 'a\b\file.txt'
                $ignorePatterns.Add("$($fileRelativePath)$($_)") | Out-Null
            }
        }
    }
    
    $ignorePatterns = @( $ignorePatterns | sort -Unique )
    $notIgnorePatterns = @( $notIgnorePatterns | sort -Unique )
    "$($ignoreFiles.Count) ignore files"
    $ignorePatterns | % {
        "ignoring: '$_'"
    }
    $notIgnorePatterns | % {
        "not-ignoring: '$_'"
    }


    # Step 2: Determine source state, honouring ignorePatterns =====================================================
    # ==============================================================================================================
    $rawSourceRelativeFilenames = @(ls $SourcePath -Recurse -File -Force | % { $_.FullName.Substring($SourceDir.FullName.Length + 1) } | sort)
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
    "ignored $($rawSourceRelativeFilenames.Count - $sourceRelativeFilenames.Count) files"
    
    # free some space
    $rawSourceRelativeFilenames = $null


    # Step 3: Determine target state ===============================================================================
    # ==============================================================================================================
    $latestBackupRelativeFilenames = @(ls $latestDirPath -Recurse -File -Force | % { $_.FullName.Substring($targetDir.FullName.Length + 1) } | sort)
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot list target files"; exit }
    "found $($latestBackupRelativeFilenames.Count) files already backed up"

    # Step 4: Determine changes ===================================================================================
    # ==============================================================================================================
    $changes = &(join-path $PSScriptRoot Get-ListDiff.ps1) $sourceRelativeFilenames $latestBackupRelativeFilenames
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot Get-ListDiff"; exit }
    
    # filter Update selection by actual file difference since last backup
    $rawUpdateCount = $changes.Update.Count
    $update = [System.Collections.Generic.List[string]]::new()
    $changes.Update | % { 
        $sourceFile = Get-Item (Join-Path $SourcePath $_) -Force
        $targetFile = Get-Item (Join-Path $TargetPath $_) -Force
        
        if (($sourceFile.LastWriteTime -ne $targetFile.LastWriteTime) -or ($sourceFile.Length -ne $targetFile.Length)) {
            $update.Add($_)
        }
    }    
    $changes.Update = $update
    if ($Error.Count -gt $priorErrorCount) { Write-Error "error filtering update selection"; exit }    
    "skipped $($rawUpdateCount - $changes.Update.Count) unmodified files"    

    # Step 5: (Report), Confirm ====================================================================================
    # ==============================================================================================================

    "$($changes.Enter.Count) new files, $($changes.Update.Count) files changed, $($changes.Exit.Count) files deleted"
    if (-not $Confirm) {
        if ('y' -ne (Read-Host 'Sounds right? (y)').ToLower()) {
            $changes
            Exit;
        }   
    }  

     
    # Step 6: Ready, Set, GO! ======================================================================================
    # ==============================================================================================================
    $changes.Exit | % { 
        "deleted: $_"
        
        EnsureDirectory (Join-Path $deletedDirPath $_)
        mv (Join-Path $latestDirPath $_) (Join-Path $deletedDirPath $_) 
    }

    # step 3: Move all updated files, back up new version
    $changes.Update | % { 
        "updated: $_"
        
        EnsureDirectory (Join-Path $updatedDirPath $_)
        mv (Join-Path $latestDirPath $_) (Join-Path $updatedDirPath $_) 

        EnsureDirectory (Join-Path $latestDirPath $_)
        cp (Join-Path $SourcePath $_) (Join-Path $latestDirPath $_)
    }

    # step 4: back up new files
    $changes.Enter | % {
        "new file: $_"

        EnsureDirectory (Join-Path $latestDirPath $_)
        cp (Join-Path $SourcePath $_) (Join-Path $latestDirPath $_)
    }
}

Main $SourcePath $latestDirPath $logDirPath 2>&1 | % { $_ >> $logFile; $_ }