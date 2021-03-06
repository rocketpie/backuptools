<#
	.SYNOPSIS
		Get an SHA256 Hash over a directory

	.DESCRIPTION
		Ignores empty directories completely

	.PARAMETER SourcePath
		Directory to calculate the Hash of

	.PARAMETER HashBehaviour
		Content: Get a Path-invariant Hash of all files content ( H( ||( ls -r | sort( H(file_n) ) ) )
		ContentAndPath: Get a Hash of content and filenames ( H( ||( ls -r | sort( pathof(file_n) ) ) ) )
		Path: Get a Hash of all filenames, ignoring content ( H( ||( pathof( ls -r | sort( pathof(file_n) ) ) ) ) )

	.EXAMPLE
		Get-DirectoryHash . 'Content'
		>1C640BF8EE3B78F66CAA35E6C6499ABF1207C85A70D754D5B81252D1A5815180
#>
[CmdletBinding()]
Param(
	#[Parameter(Mandatory=$true)]	
	[Parameter()]
	[string]
	$SourcePath= 'C:\D\tmp\test\src',

	#[Parameter(Mandatory=$true)]
	[Parameter()]
	[ValidateSet('Content','ContentAndPath','Path')]
	[string]
	$HashBehaviour = 'Content'
)

$hashContent = $HashBehaviour.Contains('Content')
$hashPath = $HashBehaviour.Contains('Path')


$files = ls -Recurse -File $SourcePath
$hashes = [System.Collections.Generic.List[System.String]]::new($files.Length)
foreach($file in $files) {
	if($hashPath) {
		$hashes.Add($file.FullName.Remove(0, $SourcePath.Length))
	}
	if($hashContent) {	
		$hashes.Add((Get-FileHash -LiteralPath $file.FullName).Hash)
	}
}

$hashes.Sort()
$hashFunction = [System.Security.Cryptography.SHA256Managed]::Create()
foreach($hash in $hashes){
	$bytes = [System.Text.Encoding]::UTF8.GetBytes($hash) 
	$hashFunction.TransformBlock($bytes, 0, $bytes.Length, $null, 0) | Out-Null
}
$hashFunction.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null

$output = [System.Text.StringBuilder]::new(32)
$hashFunction.Hash | %{ $output.Append(("{0:X2}" -f $_)) | Out-Null }

$output.ToString()