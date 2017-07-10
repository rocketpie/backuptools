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

$DebugIndent = 15
$Debug = $false
if($PSBoundParameters['Debug']){
	$DebugPreference = 'Continue'
    $Debug = $true
}

$Source = Resolve-Path $SourcePath
$Target = Resolve-Path $TargetPath

function DebugString { Param($Object)
    if($Object -eq $null) { ""; return }

    switch($Object.GetType().Name) {        
        'DictionaryEntry' {
            $name = "$($Object.Name)"
            $value = "$($Object.Value)"
            if($name.Length -gt 30) { $name = $name.SubString(0,30) + '...' }
            if($value.Length -gt 30) { $value = $value.SubString(0,30) + '...' }
            "$($name): $value"            
        }
        'PathInfo' {
            "$($Object.Path)"
        }
        'String' {
            $Object
         }
         'SwitchParameter' {
            "$Object"             
         }

        default {
            Write-Verbose "DebugString: unknown Type $($Object.GetType().FullName)"            
            "$Object"
        }
    }
}

function DebugVar { 
    Param($Name, $Value)
    if(-not $Debug) { return }

    if($Value -eq $null) { $Value = (ls variable:$Name).Value }
    if(($Value -ne $null) -and ($Value.GetType().FullName -ne 'System.String') -and ($Value.GetEnumerator -is [System.Management.Automation.PSMethodInfo])) {
        $enumerator = $Value.GetEnumerator()
        $enumerator.MoveNext()
        Write-Debug "$(("$" + $Name).PadRight($DebugIndent)): $(DebugString $enumerator.Current)"	
        while($enumerator.MoveNext()) {
            Write-Debug "$(''.PadRight($DebugIndent)): $(DebugString $enumerator.Current)"	
        }
    }
    else {
        Write-Debug "$($Name.PadRight($DebugIndent)): $(DebugString $Value)"	
    }
}

function New-HashedFile {
    Param( 
        [Parameter(Mandatory=$true, Position=0)]
        [System.IO.FileInfo]
        $File, 
        
        [Parameter(Mandatory=$true, Position=1)]
        [System.Management.Automation.PathInfo]
        $Source, 

        [Parameter()]
        [switch]
        $ReadInfoFromFile=$false
    )
    DebugVar File $File.FullName
    DebugVar Source
    DebugVar ReadInfoFromFile

    $result = New-Object PSObject
    $relativePath = $File.Directory.FullName.Remove(0, $Source.Path.Length)
    if($relativePath.Length -eq 0) { $relativePath = '.' }
    DebugVar relativePath
    $result | Add-Member -MemberType NoteProperty -Name 'RelativePath' -Value (Join-Path $relativePath $File.Name)       

    if($ReadInfoFromFile) {
        $info = gc $file.FullName
        DebugVar info
        DebugVar info $info[0]
        DebugVar info $info[1]
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

DebugVar Source
DebugVar Target

$sourceFiles = @{}
$files = ls -Recurse -File $Source
foreach($file in $files) {
    $hashedFile = New-HashedFile $file $Source
    if($sourceFiles.ContainsKey($hashedFile.Hash)) {
        Write-Warning "Duplicate source file: Will not Backup $($hashedFile.File.FullName), because the same file $($sourceFiles[$hashedFile.Hash].File.FullName) is (already) being backed up."
    }
    else {
        $sourceFiles.Add($hashedFile.Hash, $hashedFile)              
    }
}
DebugVar sourceFiles

$latestFolder = Join-Path $Target '_latest'
DebugVar latestFolder
if(-not (Test-Path $latestFolder)) { New-Item -ItemType Directory -Path $latestFolder | Out-Null }
$latestFolder = Resolve-Path $latestFolder

$backupFolder = Join-Path $Target "$(Get-Date -Format 'yyyyMMdd')"
while (Test-Path $backupFolder) {
    if($backupFolder -match '\.(\d+)$'){
        $nextRevision = [int]$Matches[1] + 1;
        $backupFolder = $backupFolder -replace '\.\d+$', ".$nextRevision"
    }
    else {
        $backupFolder += '.1'
    }
}
DebugVar backupFolder
New-Item -ItemType Directory -Path $backupFolder | Out-Null 

$targetFiles = @{}
$files = ls -Recurse -File $latestFolder
foreach($file in $files) {
    $hashedFile = New-HashedFile $file $latestFolder -ReadInfoFromFile
    $targetFiles.Add($hashedFile.RelativePath, $hashedFile) 
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