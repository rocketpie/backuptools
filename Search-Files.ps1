# Searches all files in the current directory iteratively for all provided search terms.

$files = ls -File

foreach($term in $args){
    "Searching $($files.count) files..."
    $hits = $files | %{ Select-String -Path $_ -Pattern $term }
    
    "'$term' -> $($hits.count) hits"
    $files = $hits.Path
}

$files