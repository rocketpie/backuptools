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

# Preparation ============================================================================================
# ========================================================================================================
$Debug = $false
if($PSBoundParameters['Debug']){ 
	$DebugPreference = 'Continue'	
	$Debug = $true
}

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

$journal = Join-Path $JournalFolder $backupFolder.Remove(0, $Target.Length)
function Log ($Message) {
	$Message >> $journal
}
function Debug ($Message) {
	if($Debug) {
		Log $Message
	}
}
function Debug ([String]$Message) {
	Log $Message
	Write-Warning $Message
}


Log "$(Get-Date -Format 'yyyy-MM-dd:HH-mm-ss') backing up '$Source' to '$Target'"

# $shorten = [System.Text.RegularExpressions.Regex]::new('.{0,30}', [System.Text.RegularExpressions.RegexOptions]::Compiled)
# function DebugString ($Object) {
# 	if($Object -eq $null) { ""; return }
# 	switch($Object.GetType().Name) {        
# 		'DictionaryEntry' {	$shorten.Match($Object.Name).Value +': ' +$shorten.Match((DebugString $Object.Value)).Value	}
# 		'PathInfo'        { "$($Object.Path)" }
# 		'String'          { $Object }
# 		default           { "$Object" }
# 	}
# }

# function DebugVar ($Name, $Value) { if(-not $Debug) { return }
# 	if($Value -eq $null) { $Value = (ls variable:$Name).Value; if($Value -eq $null) { return; } }  #try to get variable by name 
# 	if(($Value.GetType().Name -eq 'String') -or ($Value.GetEnumerator -eq $null)) { $Value = @($Value) } # normalize to enumerable
# 	$enumerator = $Value.GetEnumerator(); $enumerator.MoveNext() | Out-Null
# 	do {
# 		Write-Debug "$(('$' + $Name).PadRight(18)): $(DebugString $enumerator.Current)"	
# 	} while($enumerator.MoveNext());
# }

function New-HashedFile {
	Param( [Parameter(Mandatory=$true, Position=0)][System.IO.FileInfo] $File, 
		   [Parameter(Mandatory=$true, Position=1)][System.Management.Automation.PathInfo]$Source, 
		   [Parameter()]                           [switch] $ReadInfoFromFile = $false
	)
	
	$result = New-Object PSObject
	$relativePath = $File.Directory.FullName.Remove(0, $Source.Path.Length)
	if($relativePath.Length -eq 0) { $relativePath = '.' }
	#DebugVar relativePath
	$result | Add-Member -MemberType NoteProperty -Name 'RelativePath' -Value (Join-Path $relativePath $File.Name)       

	if($ReadInfoFromFile) {
		$info = gc $file.FullName
		#DebugVar info $info
		#TODO: Sanity-check _latest file content
		$result | Add-Member -MemberType NoteProperty -Name 'Hash' -Value $info[0]
		$result | Add-Member -MemberType NoteProperty -Name 'File' -Value (ls $info[1])
	}
	else {
		$result | Add-Member -MemberType NoteProperty -Name 'Hash' -Value (Get-FileHash $File.FullName).Hash
		$result | Add-Member -MemberType NoteProperty -Name 'File' -Value $File 
	}

	$result
}

# Check _latest integrity ============================================================================================
# ========================================================================================================

$expectedLatestHash = gc (Join-Path $Target '_latest')
$actualLatestHash = .\Get-DirectoryHash.ps1 $latestFolder -HashBehaviour ContentAndPath

Log "_latest: $actualLatestHash, should be $expectedLatestHash"

if(($expectedLatestHash -ne $null) -and ($expectedLatestHash -ne $actualLatestHash)) {
	Log "TODO: recover? rescan? what?"
	Exit
}

# Read $Source ============================================================================================
# ========================================================================================================

# Read files in $Source
$sourceFiles = @{}
$files = ls -Recurse -File $Source
foreach($file in $files) {
	$hashedFile = New-HashedFile $file $Source
	if($sourceFiles.ContainsKey($hashedFile.Hash)) {
		Log "TODO: add a _latest with a RelativePath pointing to the backed up file?"
		Warn "Duplicate source file: Will not Backup $($hashedFile.File.FullName), because the same file $($sourceFiles[$hashedFile.Hash].File.FullName) is (already) being backed up."
	}
	else {
		$sourceFiles.Add($hashedFile.Hash, $hashedFile)              
	}
}
Debug $sourceFiles

$targetFiles = @{}
$files = ls -Recurse -File $latestFolder
foreach($file in $files) {
	$hashedFile = New-HashedFile $file $latestFolder -ReadInfoFromFile
	$targetFiles.Add($hashedFile.Hash, $hashedFile) 
}

DebugVar targetFiles
foreach($sourceFile in $sourceFiles.Values) {
	Write-Debug "handling $($sourceFile.RelativePath)"

	if($targetFiles.ContainsKey($sourceFile.RelativePath)){
		Write-Verbose "$($sourceFile.RelativePath) is already backed up"
		if($targetFiles[$sourceFile.RelativePath].Hash -eq $sourceFile.Hash) {
			Write-Information "$($sourceFile.RelativePath) is already backed up (latest version)"
			$targetFiles.Remove($sourceFile.RelativePath)
			continue;
		}        
		# newer version available
	}

	$latestFile = (Join-Path $latestFolder $sourceFile.RelativePath)
	$backupFile = (Join-Path $backupFolder $sourceFile.RelativePath)
	DebugVar latestFile
	DebugVar backupFile

	if(-not (Test-Path $latestFile)) { New-Item -ItemType File -Path $latestFile -Force | Out-Null }
	if(-not (Test-Path $backupFile)) { New-Item -ItemType File -Path $backupFile -Force | Out-Null }
	
	cp $sourceFile.File.FullName $backupFile
	$backupFile = Resolve-Path $backupFile
	$sourceFile.Hash > $latestFile
	"$backupFile" >> $latestFile

	if($targetFiles.ContainsKey($sourceFile.RelativePath)) { $targetFiles.Remove($sourceFile.RelativePath) }
}

foreach($targetFile in $targetFiles.Values) {
	if($sourceFiles.ContainsKey($targetFile.Hash)) {
		Write-Verbose "$($targetFile.RelativePath) has been moved to $($sourceFiles[$targetFile.Hash].RelativePath)"
	}
	else {
		Write-Verbose "$($targetFile.RelativePath) has been deleted"
	}
	
	$latestFile = (Join-Path $latestFolder $targetFile.RelativePath)
	$backupFile = (Join-Path $backupFolder $targetFile.RelativePath)
	DebugVar latestFile
	DebugVar backupFile

	if(-not (Test-Path $backupFile)) { New-Item -ItemType File -Path $backupFile -Force | Out-Null }
	"_destroyed" > $backupFile
	rm $latestFile
}