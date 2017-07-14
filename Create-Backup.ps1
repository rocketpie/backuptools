<#
	.SYNOPSIS
		Incrementally back up files

	.DESCRIPTION
		Only back up changes 

	.PARAMETER Source

	.PARAMETER Target

	.EXAMPLE
#>
[CmdletBinding()]
Param(
	#[Parameter(Mandatory=$true)]
	[Parameter()]
	[string]
	$SourcePath = 'C:\D\tmp\test\src',

	#[Parameter(Mandatory=$true)]
	[Parameter()]
	[string]
	$TargetPath = 'C:\D\tmp\test\target'
)

# Preparation ========================================================================================================
# ====================================================================================================================

$Verbose = $false; if($PSBoundParameters['Verbose']) { $Verbose = $true }
$Debug = $false; if($PSBoundParameters['Debug']) { $Debug = $true }
if($Debug){ $DebugPreference = 'Continue' }

$Source = Resolve-Path $SourcePath
$Target = Resolve-Path $TargetPath
$latestFolder = Join-Path $Target '_latest'
$JournalFolder = Join-Path $Target '_journal'
$backupFolder = Join-Path $Target "$(Get-Date -Format 'yyyyMMdd').1"
while (Test-Path $backupFolder) {
	if($backupFolder -match '\.(\d+)$' ) { 
		$backupFolder = $backupFolder -replace '\.\d+$', ".$([int]$Matches[1] + 1)"
	}
}
if(-not (Test-Path $latestFolder)) { New-Item -ItemType Directory -Path $latestFolder | Out-Null }
if(-not (Test-Path $JournalFolder)) { New-Item -ItemType Directory -Path $JournalFolder | Out-Null }
New-Item -ItemType Directory -Path $backupFolder | Out-Null 
$latestFolder = Resolve-Path $latestFolder 
$JournalFolder = Resolve-Path $JournalFolder
$backupFolder = Resolve-Path $backupFolder

$journal = Join-Path $JournalFolder $backupFolder.Path.Remove(0, $Target.Path.Length)

# Functions ========================================================================================================
# ====================================================================================================================

function Log ($Message) {
	$Message >> $journal
}
function Verbose ($Message) {
	if($Verbose) {
		Log	"VERBOSE: $($Message | Out-String -Stream)"
		Write-Verbose ($Message | Out-String)
	}
}
function Debug ($Message) {
	if($Debug) {
		Log	"DEBUG: $($Message | Out-String -Stream)"
		Write-Debug ($Message | Out-String)
	}
}
function Warn ($Message) {
	Log "`nWARNING: $($Message | Out-String -Stream)"
	Write-Warning ($Message | Out-String)
}

Log "$(Get-Date -Format 'yyyy-MM-dd:HH-mm-ss') backing up '$Source' to '$Target'"

function Compare ($fileA, $fileB) {
	if($fileA.Length -ne $fileB.Length) {
		Verbose "different Length $($fileA.Length)/$($fileB.Length)"; $false; return }

	if($fileA.LastWriteTime -ne $fileB.LastWriteTime) { 
		Verbose "different LastWriteTime $($fileA.LastWriteTime)/$($fileB.LastWriteTime)"; $false; return }
	
	$fileAHash = (Get-FileHash $fileA.FullName).Hash
	$fileBHash = (Get-FileHash $fileB.FullName).Hash
	if($fileAHash -ne $fileBHash) { 
		Verbose "different Hash $($fileAHash)/$($fileBHash)"; $false; return }
	
	$true 
}

function WriteBackupFile ($sourceFile, $relativeFileName) {
		$backupFile = Join-Path $backupFolder $relativeFileName

		if(-not (Test-Path (Split-Path $backupFile))) { New-Item -ItemType Directory -Path (Split-Path $backupFile) | Out-Null }
		cp $sourceFile.FullName $backupFile
		
		$latestFile = Join-Path $latestFolder $relativeFileName
		if(-not (Test-Path (Split-Path $latestFile))) { New-Item -ItemType Directory -Path (Split-Path $latestFile) | Out-Null }
		
		$backupFile > $latestFile
		(Get-FileHash $sourceFiles[$file].FullName).Hash >> $latestFile
}

# Check _latest integrity ============================================================================================
# ====================================================================================================================

if([System.IO.File]::Exists((Join-Path $Target '_latestState'))) {
	$expectedLatestHash = gc (Join-Path $Target '_latestState')
}
$actualLatestHash = .\Get-DirectoryHash.ps1 $latestFolder -HashBehaviour ContentAndPath


if(($expectedLatestHash -ne $null) -and ($expectedLatestHash -ne $actualLatestHash)) {
	Log "TODO: recover? rescan? what?"
	Exit
}
else {
	Log "_latest state: '$actualLatestHash', should be '$expectedLatestHash' (OK)"
}

# Collect Source, Target state =======================================================================================
# ====================================================================================================================

# Read files in $Source
$sourceFiles = @{}
$files = ls -Recurse -File $Source 
foreach($file in $files) {
	$sourceFiles.Add($file.FullName.Remove(0, $Source.Path.Length), $file)
}

$targetFiles = @{}
$files = ls -Recurse -File $latestFolder
foreach($file in $files) {
	$targetFiles.Add($file.FullName.Remove(0, $latestFolder.Path.Length), $file)
}

$allfiles = $sourceFiles.Keys + @($targetFiles.Keys)
$allfiles = $allfiles | sort | Get-Unique
Verbose $allfiles

# update Target and _latest ==========================================================================================
# ====================================================================================================================

$rmcnt=0;$newcnt=0;$updcnt=0;
foreach($file in $allfiles) {
	$latestFile = (Join-Path $latestFolder $file)
	if($targetFiles.ContainsKey($file) -and [System.IO.File]::Exists($targetFiles[$file].Fullname)) {
		$oldBackupFile, $__ = gc $targetFiles[$file].Fullname
	}
	Debug "inspecting '$file' (current: '$(Join-Path $Source $file)', latest backup: '$oldBackupFile')"
	
	if(-not $sourceFiles.ContainsKey($file)) {
		Verbose "found '$file' in the latest backup, but '$(Join-Path $Source $file)' is not present (anymore)"
		Log "deleting '$latestFile'"
		rm $latestFile

		$rmcnt++; continue;
	}

	# TODO: look for moved files
	if(-not $targetFiles.ContainsKey($file)) {
		Verbose "found '$(Join-Path $Source $file)', but no matching '$file' in the latest backup"
		Log "backing up $file"

		WriteBackupFile $sourceFiles[$file] $file

		$newcnt++; continue;
	}
		
	if(-not [System.IO.File]::Exists($oldBackupFile)) { Write-Error "backup file missing: '$oldBackupFile'"; Exit; }
	if(-not (Compare $sourceFiles[$file] (ls $oldBackupFile))) {
		Verbose "'$(Join-Path $Source $file)' has been modified since the latest backup"
		Log "updating $file"

		WriteBackupFile $sourceFiles[$file] $file
		$updcnt++;
	}
	else {
		Verbose "'$(Join-Path $Source $file)' is already backed up (not modified)"
	}
}


# Finish up ==========================================================================================================
# ====================================================================================================================

$actualLatestHash = .\Get-DirectoryHash.ps1 $latestFolder -HashBehaviour ContentAndPath
$actualLatestHash > (Join-Path $Target '_latestState')

Log "removed $rmcnt files, added $newcnt files, updated $updcnt files since last backup"
Log "updated _latestState: '$actualLatestHash'"
Log "Done"