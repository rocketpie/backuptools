[CmdletBinding()]
Param(
    [ValidateSet('jpg')]
    [string]$TargetFormat = "jpg"
)

Write-Warning "ConvertFrom-Heic 0.1"
$heicFiles = Get-ChildItem -Path (Get-Location) -Filter *.heic

foreach ($file in $heicFiles) {       
    $newName = $file.FullName -replace '.heic$', '.jpg'

    Write-Debug "converting '$($file.Name)' to '$([System.IO.Path]::GetFileName($newName))'..."    
    magick $file.FullName -quality 100% $newName
}

"Done."