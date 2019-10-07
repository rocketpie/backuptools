$rand = new-object System.Random

$files = @(ls .\source -Recurse -File)

$target = $files[$rand.Next($files.Length)]
if($target) {
    Write-Debug "editing $($target.FullName)"
    [guid]::NewGuid().ToString() > $target.FullName
}