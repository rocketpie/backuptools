<#
	.SYNOPSIS
		Incrementally back up files

	.DESCRIPTION
		Only backs up changes 

		You should not use the -Verbose flag in production. This will kill your log.

	.PARAMETER Source

	.PARAMETER Target

	.PARAMETER VerifyHash
		When set, checking wether a file has changed will re-calculate the backed up files hash instead of trusting the hash remembered from when the file was last backed up.

	.EXAMPLE
#>
[CmdletBinding()]
Param(
	[Parameter(Mandatory=$true)]
	[string]
	$SourcePath,

	[Parameter(Mandatory=$true)]
	[string]
	$TargetPath,

	[Parameter()]
	[switch]
	$VerifyHash = $false
)

# Functions ========================================================================================================
# ====================================================================================================================
$priorErrorCount = $Error.Count

function ReadDirectory ($directory) {
	$result = @{}
	$files = ls -Recurse -File $directory
	foreach($file in $files) {
		$result.Add($file.FullName.Remove(0, $directory.Path.Length), $file)
	}

	Write-Host "found $($result.Count) files in $directory"
	Write-Verbose ($result.Keys | Out-String)

	$result
}

function EnsureDirectoryExists ($VarName, $path = $null) {
	if($path -eq $null) {
		$path = (ls variable:$VarName).Value
	}
	if(($path -ne $null) -and $path.GetType().Name -ne 'String') { Write-Error "FATAL: invalid variable name '$VarName'"; Exit }  
	if(-not (Test-Path -LiteralPath $path)) { 
		Write-Debug "creating $VarName '$path'"	
		New-Item -ItemType Directory -Path $path | Out-Null
	}	
}

function CompareFiles ($fileA, $fileB, $fileBHash) {
	if($fileA.Length -ne $fileB.Length) {
		Write-Verbose "different Length $($fileA.Length)/$($fileB.Length)"; $false; return }

	if($fileA.LastWriteTime -ne $fileB.LastWriteTime) { 
		Write-Verbose "different LastWriteTime $($fileA.LastWriteTime)/$($fileB.LastWriteTime)"; $false; return }
	
	$fileAHash = (Get-FileHash -LiteralPath $fileA.FullName).Hash 
	if($fileBHash -eq $null) { $fileBHash = (Get-FileHash -LiteralPath $fileB.FullName).Hash }
	if($fileAHash -ne $fileBHash) { 
		Write-Verbose "different Hash $($fileAHash)/$($fileBHash)"; $false; return }
	
	$true 
}

function WriteBackupFile ($sourceFile, $backupFile, $latestFile) {		
	EnsureDirectoryExists 'directory' (Split-Path $backupFile)	
	EnsureDirectoryExists 'directory' (Split-Path $latestFile)	
		
	[System.IO.File]::Copy($sourceFile.FullName, $backupFile)
		
	if([System.IO.File]::Exists($latestFile)) {
		[System.IO.File]::Delete($latestFile)
	}
	New-Item -ItemType File -Path $latestFile -Value "$backupFile`n$((Get-FileHash -LiteralPath $sourceFile.FullName).Hash)" | Out-Null
}

# Preparation ========================================================================================================
# ====================================================================================================================

$Verbose = $false; if($PSBoundParameters['Verbose']) { $Verbose = $true }
$Debug = $false; if($PSBoundParameters['Debug']) { $Debug = $true }
if($Debug){ $DebugPreference = 'Continue' }

$Source = Resolve-Path "$SourcePath\"
$Target = Resolve-Path "$TargetPath\"
$ignoreFile = Join-Path $Target '_ignore'
$latestDirectory = Join-Path $Target '_latest\' 
$latestStateFile = Join-Path $Target '_latestState' 
$journalDirectory = Join-Path $Target '_journal\'

$backupDirectory = ''
$revision = 0
do {
	$revision++
	$backupDirectory = Join-Path $Target "$(Get-Date -Format 'yyyyMMdd').$revision\"	
} while (Test-Path -LiteralPath $backupDirectory);

EnsureDirectoryExists 'latestDirectory'
EnsureDirectoryExists 'journalDirectory'
EnsureDirectoryExists 'backupDirectory' 
$latestDirectory = Resolve-Path "$latestDirectory\"
$journalDirectory = Resolve-Path "$journalDirectory\"
$backupDirectory = Resolve-Path "$backupDirectory\"

$journalFile = Join-Path $journalDirectory "$(Get-Date -Format 'yyyyMMdd').$revision"
"$(Get-Date -Format 'yyyy-MM-dd:HH-mm-ss') backing up '$Source' to '$Target'" > $journalFile

if($Error.Count -ne $priorErrorCount) {
	Write-Error "there were errors."
	Exit	
}

function Main () {
 	"Checking _latest\ integrity..." # ============================================================================================
# ====================================================================================================================
	if([System.IO.File]::Exists($latestStateFile)) {
		$expectedLatestHash = gc $latestStateFile
	}
	$actualLatestHash = Get-DirectoryHash $latestDirectory -HashBehaviour ContentAndPath

	if(($expectedLatestHash -ne $null) -and ($expectedLatestHash -ne $actualLatestHash)) {
		Write-Error "_latest\ state: '$actualLatestHash', should be '$expectedLatestHash'"
		"TODO: recover? rescan? what?"
		Exit
	}
	else {
		"_latest\ state: '$actualLatestHash', should be '$expectedLatestHash' (OK)"
	}

	# TODO: Verify hashes

	"Reading Source files and Target state..." # =======================================================================================
# ====================================================================================================================

	# Read files in $Source
	[hashtable]$sourceFiles = ReadDirectory $Source
	[hashtable]$latestFiles = ReadDirectory $latestDirectory
 
	"Checking _ignore file..." # =======================================================================================

	$ignorecnt = 0;
	if([System.IO.File]::Exists($ignoreFile)) {
		"_ignore file found"
		foreach	($entry in (gc $ignoreFile)) { 
			if(($entry[0] -eq '/') -or ($entry[0] -eq '\')) {
				$entry = $entry.Remove(0, 1)
			}
			$ignoreFiles = @((ls -Recurse -File ($Source.Path + '\' + $entry)))
			"_ignore '$entry': $($ignoreFiles.Length) files"

			foreach ($file in $ignoreFiles) {
				$key = $file.FullName.Remove(0, $Source.Path.Length)
				if(-not $sourceFiles.ContainsKey($key)) { Write-Error "cannot _ignore '$key': not found" }
				else {
					Write-Debug "_ignore '$file'"
					$sourceFiles.Remove($key)
					$ignorecnt++;
				}
			}
		}

		"ignoring $ignorecnt files"
	}
	else {
		"no _ignore file found"
	}

	$allfiles = $sourceFiles.Keys + @($latestFiles.Keys)
	$allfiles = $allfiles | sort | Get-Unique

	# TODO: move _latest to $version_latest to be able to restore prior?

	"Applying changes to backup Target..." # ==========================================================================================
# ====================================================================================================================

	$rmcnt=0;$newcnt=0;$updcnt=0;
	foreach($file in $allfiles) { 
		$latestFile = (Join-Path $latestDirectory $file)
		$oldBackupFile = $null; $oldBackupFileHash = $null
		if($latestFiles.ContainsKey($file) -and [System.IO.File]::Exists($latestFiles[$file].FullName)) {
			$oldBackupFile, $oldBackupFileHash, $__ = [System.IO.File]::ReadAllLines($latestFiles[$file].FullName)
			if($VerifyHash) { $oldBackupFileHash = $null }
		}
		Write-Debug "inspecting '$file' (current: '$(Join-Path $Source $file)', latest backup: '$oldBackupFile')"
		
		Write-Debug "source contains '$file': $($sourceFiles.ContainsKey($file))"
		if(-not $sourceFiles.ContainsKey($file)) {
			Write-Verbose "found '$file' in the latest backup, but '$(Join-Path $Source $file)' is not present (anymore)"
			"deleting '$latestFile'"
			[System.IO.File]::Delete($latestFile)

			$rmcnt++; continue;
		}

		# TODO: look for moved files
		Write-Debug "target contains '$file': $($latestFiles.ContainsKey($file))"
		if(-not $latestFiles.ContainsKey($file)) {
			Write-Verbose "found '$(Join-Path $Source $file)', but no matching '$file' in the latest backup"
			"backing up $file"

			WriteBackupFile $sourceFiles[$file] (Join-Path $backupDirectory $file) (Join-Path $latestDirectory $file)

			$newcnt++; continue;
		}
			
		if(-not [System.IO.File]::Exists($oldBackupFile)) { Write-Error "backup file missing: '$oldBackupFile'"; }
		
		if(-not (CompareFiles $sourceFiles[$file] (ls -LiteralPath $oldBackupFile) $oldBackupFileHash)) {
			Write-Verbose "'$(Join-Path $Source $file)' has been modified since the latest backup"
			"updating $file"

			WriteBackupFile $sourceFiles[$file] (Join-Path $backupDirectory $file) (Join-Path $latestDirectory $file)
			$updcnt++;
		}
		else {
			Write-Verbose "'$(Join-Path $Source $file)' is already backed up (not modified)"
		}
	}

	"Finishing up..." # ==========================================================================================================

	$actualLatestHash = Get-DirectoryHash $latestDirectory -HashBehaviour ContentAndPath
	$actualLatestHash > $latestStateFile

	# TODO: also backup _ignore file ?

	"removed $rmcnt files, added $newcnt files, updated $updcnt files since last backup"
	"$($Error.Count) error(s)"
	"updated _latestState: '$actualLatestHash'"
	"Done"
}
Main *>&1 | %{ $_; $_ >> $journalFile }