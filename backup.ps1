<#
	.SYNOPSIS
		Incrementally back up files to a target directory

	.DESCRIPTION
		
	
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

function EnsureDirectory($filePath) {
    mkdir (Split-Path $filePath) -ErrorAction SilentlyContinue | Out-Null
}

# make value into human readable one-line string
function Print($value) {
    $value.ToString() # hack this for now...
}

# output variable by name for debugging
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

if (-not (Test-Path $TargetPath)) {
    mkdir $TargetPath | Out-Null
}
$TargetPath = Resolve-Path $TargetPath
DebugVar 'TargetPath'
if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot find or create target directory '$TargetPath'"; exit }

$latestDirPath = Join-Path $TargetPath '_latest'
DebugVar 'latestDirPath'
if (-not (Test-Path $latestDirPath)) {
    mkdir $latestDirPath | Out-Null
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot create _latest directory '$latestDirPath'"; exit }
}

$logDirName = "$(Get-Date -f 'yyyy-MM-dd')"
$revision = 0
do {
    $revision++
    $logDirPath = Join-Path $TargetPath "$logDirName.$revision"	
} while (Test-Path -LiteralPath $logDirPath);
DebugVar 'logDirPath'
mkdir $logDirPath | Out-Null
if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot create log directory '$logDirPath'"; exit }

$logFile = (Join-Path $logDirPath 'log.txt')
DebugVar 'logFile'
"Backing up '$SourcePath'" >> $logFile
if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot write log file"; exit }


function Main($SourcePath, $latestDirPath, $logDirPath, $scriptPath) {    
    $deletedDirPath = Join-Path $logDirPath deleted
    $updatedDirPath = Join-Path $logDirPath updated

    # Step 1: Determine changes ====================================================================================
    # ==============================================================================================================    
    $changes = &$scriptPath\Compare-Directories.ps1 $SourcePath $latestDirPath
    "$($changes.Enter) new files, $($changes.Update) files changed, $($changes.Exit) files deleted"
    if (-not $Confirm) {
        if ('y' -ne (Read-Host 'Sounds right? (y)').ToLower()) {
            $changes
            Exit;
        }   
    }

    # step 2: Move all deleted files
    $changes.Exit | % { 
        Write-Debug "deleted: $_"
        
        EnsureDirectory (Join-Path $deletedDirPath $_)
        mv (Join-Path $latestDirPath $_) (Join-Path $deletedDirPath $_) 
    }

    # step 3: Move all updated files, back up new version
    $changes.Update | % { 
        Write-Debug "updated: $_"
        
        EnsureDirectory (Join-Path $updatedDirPath $_)
        mv (Join-Path $latestDirPath $_) (Join-Path $updatedDirPath $_) 

        EnsureDirectory (Join-Path $latestDirPath $_)
        cp (Join-Path $SourcePath $_) (Join-Path $latestDirPath $_)
    }

    # step 4: back up new files
    $changes.Enter | % {
        Write-Debug "new file: $_"

        EnsureDirectory (Join-Path $latestDirPath $_)
        cp (Join-Path $SourcePath $_) (Join-Path $latestDirPath $_)
    }
}

Main $SourcePath $latestDirPath $logDirPath $scriptPath 2>&1 | % { $_ >> $logFile; $_ }