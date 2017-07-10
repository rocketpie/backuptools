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
        "DictionaryEntry" {
            $name = "$($Object.Name)"
            $value = "$($Object.Value)"
            if($name.Length -gt 30) { $name = $name.SubString(0,30) + '...' }
            if($value.Length -gt 30) { $value = $value.SubString(0,30) + '...' }
            "$($name): $value"            
        }
        "PathInfo" {
            "$($Object.Path)"
        }
        "String" {
            $Object
         }

        default {
            Write-Debug "DebugString: unknown Type $($Object.GetType().FullName)"            
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
        [Parameter(ValueFromPipeline=$true)]
        [System.IO.FileInfo]
        $File, 
        
        [Parameter(Mandatory=$true, Position=1)]
        [System.Management.Automation.PathInfo]
        $Source, 

        [Parameter()]
        [switch]
        $ReadHashFromFile=$false
    )
    Begin { }
    Process {
        #DebugVar File $File.FullName
        #DebugVar Source
        #DebugVar ReadHashFromFile

        $result = New-Object PSObject
        $result | Add-Member -MemberType NoteProperty -Name 'File' -Value $File    

        $pathFromSource = $File.Directory.FullName.Remove(0, $Source.Path.Length)
        if($pathFromSource.Length -eq 0) { $pathFromSource = '.' }
        #DebugVar pathFromSource
        $result | Add-Member -MemberType NoteProperty -Name 'RelativePath' -Value $pathFromSource        

        if($ReadHashFromFile) {
            $result | Add-Member -MemberType NoteProperty -Name 'Hash' -Value (gc $File.FullName)[0]
        }
        else { 
            $result | Add-Member -MemberType NoteProperty -Name 'Hash' -Value (Get-FileHash $File.FullName).Hash
        }

        $result
    }
    End { }
}

DebugVar Source
DebugVar Target

$sourceFiles = @{}
$files = ls -Recurse -File $Source
if($files) {
    $files | New-HashedFile $Source | %{ if(-not $sourceFiles.ContainsKey($_.Hash)) { $sourceFiles.Add($_.Hash, $_) } }
}
DebugVar sourceFiles

$latestFolder = Join-Path $Target '_latest'
DebugVar latestFolder
if(-not (Test-Path $latestFolder)) { New-Item -ItemType Directory -Path $latestFolder | Out-Null }

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
if($files) {
    $files | New-HashedFile $latestFolder -ReadHashFromFile | %{ $targetFiles.Add($_.RelativePath, $_) }
}

DebugVar targetFiles