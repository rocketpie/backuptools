<#
	.SYNOPSIS
		Get an SHA256 Hash over a directory

	.DESCRIPTION
		

	.PARAMETER SourcePath

	.PARAMETER HashBehaviour
		Content: Get a Path-invariant Hash of all files content ( H( ||( ls -r | sort( H(file_n) ) ) )
		ContentAndPath: Get a Hash of content and filenames ( H( ||( ls -r | sort( pathof(file_n) ) ) ) )
		Path: Get a Hash of all filenames, ignoring content ( H( ||( pathof( ls -r | sort( pathof(file_n) ) ) ) ) )
	.EXAMPLE
#>
[CmdletBinding()]
Param(
	[Parameter(Mandatory=$true)]
	[string]
	$SourcePath,

	[Parameter(Mandatory=$true)]
	[ValidateSet('Content','ContentAndPath')]
	[string]
	$HashBehaviour
)

$hashFunc = [System.Security.Cryptography.SHA256]::Create()

'Test'