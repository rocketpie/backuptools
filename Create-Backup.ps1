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
		if(-not (Test-Path -LiteralPath (Split-Path $backupFile))) { New-Item -ItemType Directory -Path (Split-Path $backupFile) | Out-Null }
		if(-not (Test-Path -LiteralPath (Split-Path $latestFile))) { New-Item -ItemType Directory -Path (Split-Path $latestFile) | Out-Null }
		
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

$Source = Resolve-Path $SourcePath
$Target = Resolve-Path $TargetPath
$ignoreFile = Join-Path $Target '_ignore'
$latestFolder = Join-Path $Target '_latest\' 
$JournalFolder = Join-Path $Target '_journal\'
$backupFolder = Join-Path $Target "$(Get-Date -Format 'yyyyMMdd').1"
while (Test-Path -LiteralPath $backupFolder) {
	if($backupFolder -match '\.(\d+)$' ) { 
		$backupFolder = $backupFolder -replace '\.\d+$', ".$([int]$Matches[1] + 1)"
	}
}
if(-not (Test-Path -LiteralPath $latestFolder)) { New-Item -ItemType Directory -Path $latestFolder | Out-Null }
if(-not (Test-Path -LiteralPath $JournalFolder)) { New-Item -ItemType Directory -Path $JournalFolder | Out-Null }
New-Item -ItemType Directory -Path $backupFolder | Out-Null 
$latestFolder = Resolve-Path $latestFolder 
$JournalFolder = Resolve-Path $JournalFolder
$backupFolder = Resolve-Path $backupFolder

$journal = Join-Path $JournalFolder $backupFolder.Path.Remove(0, $Target.Path.Length)

function Main () {
	"$(Get-Date -Format 'yyyy-MM-dd:HH-mm-ss') backing up '$Source' to '$Target'"

 	"Checking _latest\ integrity..." # ============================================================================================
# ====================================================================================================================
	if([System.IO.File]::Exists((Join-Path $Target '_latestState'))) {
		$expectedLatestHash = gc (Join-Path $Target '_latestState')
	}
	$actualLatestHash = Get-DirectoryHash $latestFolder -HashBehaviour ContentAndPath

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
	$sourceFiles = @{}
	$files = ls -Recurse -File $Source 
	foreach($file in $files) {
		$sourceFiles.Add($file.FullName.Remove(0, $Source.Path.Length), $file)
	}
	"found $($sourceFiles.Count) files in $Source"
	Write-Verbose ($sourceFiles.Keys | Out-String)

	$latestFiles = @{}
	$files = ls -Recurse -File $latestFolder
	foreach($file in $files) {
		$latestFiles.Add($file.FullName.Remove(0, $latestFolder.Path.Length), $file)
	}
	"found $($latestFiles.Count) files in $latestFolder"
	Write-Verbose ($latestFiles.Keys | Out-String)

	"Checking _ignore file..." # =======================================================================================

	$ignorecnt = 0;
	if([System.IO.File]::Exists($ignoreFile)) {
		"_ignore file found"
		foreach	($entry in (gc $ignoreFile)) { 
			if(($entry[0] -eq '/') -or ($entry[0] -eq '\')) {
				$entry = $entry.Remove(0, 1)
			}
			$ignoreFiles = @((ls -Recurse -File ($Source.Path + '\' + $entry)))
			Write-Debug "DEBUG: _ignore '$entry': $($ignoreFiles.Length) files"

			foreach ($file in $ignoreFiles) {
				$key = $file.FullName.Remove(0, $Source.Path.Length)
				if(-not $sourceFiles.ContainsKey($key)) { Write-Error "cannot _ignore '$key': not found" }
				else {
					Write-Verbose "VERBOSE: _ignore '$file'"
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

	$allfiles = $sourceFiles.Keys + @($targetFiles.Keys)
	$allfiles = $allfiles | sort | Get-Unique

	"Applying changes to backup Target..." # ==========================================================================================
# ====================================================================================================================

	$rmcnt=0;$newcnt=0;$updcnt=0;
	foreach($file in $allfiles) { 
		$latestFile = (Join-Path $latestFolder $file)
		$oldBackupFile = $null; $oldBackupFileHash = $null
		if($targetFiles.ContainsKey($file) -and [System.IO.File]::Exists($targetFiles[$file].FullName)) {
			$oldBackupFile, $oldBackupFileHash, $__ = [System.IO.File]::ReadAllLines($targetFiles[$file].FullName)
			if($VerifyHash) { $oldBackupFileHash = $null }
		}
		Write-Debug "DEBUG: inspecting '$file' (current: '$(Join-Path $Source $file)', latest backup: '$oldBackupFile')"
		
		Write-Debug "source contains '$file': $($sourceFiles.ContainsKey($file))"
		if(-not $sourceFiles.ContainsKey($file)) {
			Write-Verbose "VERBOSE: found '$file' in the latest backup, but '$(Join-Path $Source $file)' is not present (anymore)"
			"deleting '$latestFile'"
			[System.IO.File]::Delete($latestFile)

			$rmcnt++; continue;
		}

		# TODO: look for moved files
		Write-Debug "target contains '$file': $($targetFiles.ContainsKey($file))"
		if(-not $targetFiles.ContainsKey($file)) {
			Write-Verbose "VERBOSE: found '$(Join-Path $Source $file)', but no matching '$file' in the latest backup"
			"backing up $file"

			WriteBackupFile $sourceFiles[$file] (Join-Path $backupFolder $file) (Join-Path $latestFolder $file)

			$newcnt++; continue;
		}
			
		if(-not [System.IO.File]::Exists($oldBackupFile)) { Write-Error "backup file missing: '$oldBackupFile'"; Exit; }
		
		if(-not (CompareFiles $sourceFiles[$file] (ls -LiteralPath $oldBackupFile) $oldBackupFileHash)) {
			Write-Verbose "VERBOSE: '$(Join-Path $Source $file)' has been modified since the latest backup"
			"updating $file"

			WriteBackupFile $sourceFiles[$file] (Join-Path $backupFolder $file) (Join-Path $latestFolder $file)
			$updcnt++;
		}
		else {
			Write-Verbose "VERBOSE: '$(Join-Path $Source $file)' is already backed up (not modified)"
		}
	}

	"Finishing up..." # ==========================================================================================================

	$actualLatestHash = Get-DirectoryHash $latestFolder -HashBehaviour ContentAndPath
	$actualLatestHash > (Join-Path $Target '_latestState')

	"removed $rmcnt files, added $newcnt files, updated $updcnt files since last backup"
	"$($Error.Count) error(s)"
	"updated _latestState: '$actualLatestHash'"
	"Done"
}
Main *>&1 | %{ $_; $_ >> $journal }