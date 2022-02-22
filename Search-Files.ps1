# Searches all files in the current directory iteratively for all provided search terms.
$verbose = $false
if ($args | Where-Object { $_.tolower() -eq '-v' } ) {
    $terms = $args | Where-Object { $_.tolower() -ne '-v' }
    $verbose = $true
    $vPref = $VerbosePreference
    $VerbosePreference = 'Continue'
}
else {
    $terms = $args
}

$files = Get-ChildItem -File
function AddInfo($dict, $key, $value) {
    if (!$dict.ContainsKey($key)) {
        $dict.Add($key, [System.Collections.ArrayList]::new()) | Out-Null
    }    
    $dict[$key].Add($value) | Out-Null
}

$hitInfos = @{}
foreach ($term in $terms) {
    Write-Verbose "Searching $($files.count) files..."
    $hits = $files | ForEach-Object { Select-String -Path $_ -Pattern $term }
    
    foreach ($hit in $hits) {
        AddInfo $hitInfos $hit.Path "z. $($hit.LineNumber.ToString().PadLeft(3)): $($hit.Line)"
    }

    Write-Verbose "'$term' -> $($hits.count) hits"
    $files = $hits.Path | Select-Object -Unique
}

foreach ($file in $files) {
    $file
    foreach ($info in $hitInfos[$file]) {
        Write-Verbose $info
    }
}

if ($verbose) {
    $VerbosePreference = $vPref
}