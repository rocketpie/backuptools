$rand = new-object System.Random

$files = @(ls .\source -Recurse -File)

$target = $files[$rand.Next($files.Length)]
if($target) {
    Write-Debug "deleting $($target.FullName)"
    $target | rm
    $target.Name
}
