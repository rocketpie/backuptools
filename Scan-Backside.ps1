<#
	.SYNOPSIS
		Rename scans so that scanning the backsides will make them ordered correctly		
		Assumes that there are only those files present that have been scanned from the front

	.DESCRIPTION
		use in /scanned documents
	
    .EXAMPLE
        Scan-Backside
#>
[CmdletBinding()]
Param(	
)

if($PSBoundParameters["Debug"]){
	$DebugPreference = "Continue"
}

$pages = ls 'Bild*.jpg' | %{ 
	if($_.Name -match 'Bild \((\d+?)\)') { 
		New-Object psobject -Property @{ 'page'=$_; 'num'=[int]$Matches[1] } 
	} 
}

$pages = @($pages | sort -Property 'num' -Descending)
$maxpage  = $pages[0].num
Write-Debug "$maxpage ($($pages.count)) pages"

for($i = 0; $i -lt $pages.Length; $i++) { 
	$newPageIdx = ((($maxpage -$i) * 2) -1) # maxpage=4; i=0 => 7; i=1 => 5 i=2 => 3
	$newName = $pages[$i].page.FullName -replace "\($($pages[$i].num)\)\.(\w{3})$", "($newPageIdx).`$1"

	Write-Debug "mv $($pages[$i].page.FullName) $newName"
	mv $pages[$i].page.FullName $newName
}