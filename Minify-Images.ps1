<#
	.SYNOPSIS
		Make images like scanned documents smaller

	.DESCRIPTION
		use in /scanned documents

	.PARAMETER Filter
		default *.jpg

	.PARAMETER MaxSizeKB
		resize all files larger than MaxSizeKB
		default 1000

    .EXAMPLE
        Minify-Images
#>
[CmdletBinding()]
Param(
	[Parameter()]
	[string]
	$Filter = '*.jpg',

	[Parameter()]
	[int]
	$MaxSizeKB = 1000
)

$imageFiles = Get-ChildItem -Filter $Filter

foreach ($file in $imageFiles) {
	if (($file.Length / 1KB) -le $MaxSizeKB) {
		Write-Debug "ignoring $([int]($file.Length / 1KB))KB '$($file.Name)'..."
		continue
	}
	
	"resizing '$($file.Name)'..."
	magick.exe $file.FullName -resize '6000000@' -quality 80 $file.FullName

}