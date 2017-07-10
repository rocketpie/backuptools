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
    [Parameter]
    [string]
    $Source,

    [Parameter]
    [string]
    $Target
)

$Source = Resolve-Path $Source
$Target = Resolve-Path $Target

function New-HashedFile {
    Param( [Parameter(ValueFromPipeline=$true)]$File, $Source, $ReadHashFromFile=$false)
    $result = New-Object System.Management.Automation.PSCustomObject
    $result | Add-Member -TypeName NoteProperty -Name 'File' -Value $File    

    $pathFromSource = $File.Directory.FullName.Remove(0, $Source.length)
    if($pathFromSource.length -eq 0){ $pathFromSource = '.' }
    $result | Add-Member -TypeName NoteProperty -Name 'RelativePath' -Value $pathFromSource

    if($ReadHashFromFile) {
        $result | Add-Member -TypeName NoteProperty -Name 'Hash' -Value (Get-FileHash $File).Hash
    }
}

$sourceFiles = @{}
ls -r $Source | New-HashedFile $Source | %{ if(-not $sourceFiles.ContainsKey($_.Hash)) { $sourceFiles.Add($_.Hash, $_) } }

$latestFolder = Join-Path $Target "_latest"
$backupFolder = Join-Path $Target "$(Get-Date -Format 'yyyyMMdd')"
while (Test-Path $backupRootFolder) {
    if($backupRootFolder -match '\.(\d+)$'){
        $nextRevision = $Matches[1] + 1;
        $backupRootFolder -replace '\.\d+$', ".$nextRevision"
    }
    else {
        $backupRootFolder = "$backupRootFolder.1"
    }
}

$targetFiles = @{}
ls -r $latestFolder | New-HashedFile $latestFolder -ReadHashFromFile | %{ $targetFiles.Add($_.RelativePath, $_) }






