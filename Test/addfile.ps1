$rand = new-object System.Random

$dirs = ls .\source -Recurse -Directory
$dirs += @(get-item .\source)

$filename = [guid]::NewGuid().ToString()
$fullname = join-path $dirs[$rand.Next($dirs.Length)].Fullname $filename

Write-Debug "+$fullname"
[guid]::NewGuid() > $fullname
$filename