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

$prevWorkingPath = Get-Location

# make sure we're in the test directory
cd (Split-path $MyInvocation.MyCommand.Definition)

# re setup source
rm '.\source' -Recurse -Force
mkdir '.\source' | Out-Null
mkdir '.\source\1' | Out-Null
mkdir '.\source\1\1-1' | Out-Null
mkdir '.\source\2' | Out-Null

Run 'backup new file' {
    $filename = .\addfile.ps1
    backup .\source .\backups | Out-Null
    @(ls .\backups -Recurse | ?{$_.name -eq $filename}).Length -eq 1 
}

$leftover = .\deletefile.ps1
while ($leftover) {
    $leftover = .\deletefile.ps1
}

cd $prevWorkingPath