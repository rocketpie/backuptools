<#
    .NOTES
    Photosort collection:
    > Move-FilesByDate to rough-sort files for easy tagging etc.
    > Find-Duplicates to find all duplicates originating from different backups for de-duplication
    > Find-Lookalikes to find all sets of lookalike photos originating from taking multiple shots of the same thing

#> 
[CmdletBinding()]
param (
    [Parameter()]
    [ValidateSet('CreationTime', 'LastWriteTime')]
    $Property = 'LastWriteTime',

    [ValidateSet('Year', 'Month', 'Day')]
    $Selector = 'Month',

    [Parameter()]
    [switch]
    $WhatIf = $false
)
    
begin {
    $files = ls $origin -File
        
    $valueFormatter = "";
    switch ($Selector) {
        'Year' {
            $valueFormatter = "{0:d4}";
          }
        'Month' {
            $valueFormatter = "{0:d4}-{1:d2}";
         }
        'Day' {
            $valueFormatter = "{0:d4}-{1:d2}-{2:d2}";
         }
        Default { 
            Write-Error "invalid -Selector '$Selector'"
            exit
        }
    }
    $files | % { Add-Member -InputObject $_ -Type NoteProperty -Name "TargetDirectory" -Value ($valueFormatter -f $_.$Property.Year, $_.$Property.Month, $_.$Property.Day) }
        
    if ($WhatIf) {
        $files | % { "$($_.Name) => $($_.TargetDirectory)" }        
    }
    else {
        # ordner anlegen
        $files | select -Unique -Property 'TargetDirectory' | % { mkdir $_.TargetDirectory -ErrorAction 'ignore' }
            
        # dateien Verschieben
        $files | % { mv $_.FullName (Join-Path (Join-Path (Split-Path $_.FullName) $_.TargetDirectory) $_.Name) }        
    }
}
    
process {
        
}
    
end {
        
}

