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
	$BackupPath,

	[Parameter(Mandatory=$true)]
	[string]
	$RestorePath,

    [Parameter()]
    [string]
    $Version = '_latest',

	[Parameter()]
	[switch]
	$Verify = $false
)

# something like ls -Recurse -File $BackupPath\_latest\ | % { cp (gc $_)[0] $_.FullName.Replace($BackupPath, $RestorePath) }
# or something.
