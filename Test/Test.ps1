$DebugPreference = 'Continue'

function Run($name, $testScript) {
    $result = &$testScript
    if($result.ToString() -eq 'True') {
        "PASSED: $name"
    }
    else {
        Write-Error "FAILED: $name"
    }
}


Run 'backup new file' {
    $filename = .\addfile.ps1
    backup .\source .\backups | Out-Null
    @(ls .\backups -Recurse | ?{$_.name -eq $filename}).Length -eq 1 
}

$leftover = .\deletefile.ps1
while ($leftover) {
    $leftover = .\deletefile.ps1
}