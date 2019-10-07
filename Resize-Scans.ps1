<#
	.SYNOPSIS
		Make scanned documents smaller

	.DESCRIPTION
		use in /scanned documents

	.PARAMETER Filter
		default *.jpg

	.PARAMETER MinSize
		minimum filesize to resize, in KB
		default 900

    .EXAMPLE
        Resize-Scans
#>
[CmdletBinding()]
Param(
	[Parameter()]
	[string]
	$Filter = '*.jpg',

	[Parameter()]
	[int]
	$MinSize = 900
)

ls $Filter | ?{ ($_.Length / 1KB) -gt $MinSize } | %{ "resizing $($_.Name)"; magick $_.FullName -resize 75% -quality 60 $_.FullName } # "$($_.BaseName)_small$($_.Extension)"