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
    
# Functions ========================================================================================================
# ==================================================================================================================

# given a path to a *file*, 
# Create the file's parent directory if it does not exist.
function EnsureDirectory($filePath) {
    mkdir (Split-Path $filePath) -ErrorAction Ignore | Out-Null
}

# ~ToString(): convert value into human readable, log-printable (one-line) string
function Print($value) {
    $value.ToString() # hack this for now...
}

# debugging: print variable name with it's value
function DebugVar($varName) {
    $value = (get-item variable:$varName).Value
    Write-Debug "$($varName.PadRight(15)): $(Print $value)"
}

# output debugging inspection
function DebugOutput($name, $value) {    
    Write-Debug "$($name.PadRight(15)): $(Print $value)"    
}

# Preparation ======================================================================================================
# ==================================================================================================================

$priorErrorCount = $Error.Count
Write-Debug $MyInvocation.Line

$scriptPath = Split-path $MyInvocation.MyCommand.Definition
DebugVar 'scriptPath'

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


function Main($scriptPath, $SourcePath, $latestDirPath, $logDirPath) {    
    $deletedDirPath = Join-Path $logDirPath deleted
    $updatedDirPath = Join-Path $logDirPath updated

    # Step 1: Determine changes ====================================================================================
    # ==============================================================================================================    
    $changes = &(join-path $scriptPath Compare-Directories.ps1) $SourcePath $latestDirPath
    "$($changes.Enter.Count) new files, $($changes.Update.Count) files changed, $($changes.Exit.Count) files deleted"
    if (-not $Confirm) {
        if ('y' -ne (Read-Host 'Sounds right? (y)').ToLower()) {
            $changes
            Exit;
        }   
    }

    # step 2: Move all deleted files
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

Main $scriptPath $SourcePath $latestDirPath $logDirPath 2>&1 | % { $_ >> $logFile; $_ }