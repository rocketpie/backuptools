<#
	.SYNOPSIS
		Incrementally back up files to a target directory

	.DESCRIPTION
		
	
    .EXAMPLE
        backup \sourcedir \targetdir
#>
[CmdletBinding()]
Param(	
    [Parameter(Mandatory = $true, Position = 0)]
	[string]
	$SourcePath,

	[Parameter(Mandatory = $true, Position = 1)]
	[string]
    $TargetPath, 
    
    [Parameter(Mandatory = $false)]
    [switch]$Test = $false
)
    
# Functions ========================================================================================================
# ===================================================================================================================

# make value into human readable one-line string
function Print($value) {
    $value.ToString() # hack this for now...
}

# output variable by name for debugging
function DebugVar($varName) {
    $value = (get-item variable:$varName).Value
    Write-Debug "$($varName.PadRight(15)): $(Print $value)"
}

# output debugging inspection
function DebugOutput($name, $value) {    
    Write-Debug "$($name.PadRight(15)): $(Print $value)"    
}

# returns an object with a method 'GetRelativePath($target)' that returns a relative path from $rootPath to $target
function NewRelativePathGenerator($rootPath) {
    $rootPath = (Resolve-Path $rootPath).Path # make sure root path is absolute
    $rootPath = $rootPath.TrimEnd('/').TrimEnd('\') + '/' # make sure root path is uniform, ending with '/'
    # TODO: Test what happens if so passes a filename as root uri?
    $rootUri = [uri]::new($rootPath)

    $generator = New-Object psobject
    $generator | Add-Member -MemberType NoteProperty -Name 'RootUri' -Value $rootUri
    $generator | Add-Member -MemberType ScriptMethod -Name 'GetRelativePath' -Value { 
        Param($target) 
        $this.RootUri.MakeRelative([uri]::new($target)) 
    }

    $generator
}

# Preparation ========================================================================================================
# ====================================================================================================================

$priorErrorCount = $Error.Count
Write-Debug $MyInvocation.Line

$SourcePath = Resolve-Path $SourcePath
DebugVar 'SourcePath'
if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot find source directory '$SourcePath'"; exit }

if(-not (Test-Path $TargetPath)) {
    mkdir $TargetPath | Out-Null
}
$TargetPath = Resolve-Path $TargetPath
DebugVar 'TargetPath'
if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot find or create target directory '$TargetPath'"; exit }

$latestDirPath = Join-Path $TargetPath '_latest'
DebugVar 'latestDirPath'
if(-not (Test-Path $latestDirPath)) {
    mkdir $latestDirPath | Out-Null
    if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot create _latest directory '$latestDirPath'"; exit }
}

$runDirName = "$(Get-Date -f 'yyyy-MM-dd')"
$revision = 0
do {
	$revision++
	$runDirPath = Join-Path $TargetPath "$runDirName.$revision"	
} while (Test-Path -LiteralPath $runDirPath);
DebugVar 'runDirPath'
mkdir $runDirPath | Out-Null
if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot create run directory '$runDirPath'"; exit }

$journalFile = (Join-Path $runDirPath '_journal.txt')
DebugVar 'journalFile'
"Backing up '$SourcePath'" >> $journalFile
if ($Error.Count -gt $priorErrorCount) { Write-Error "cannot write to journal file"; exit }



function Main($SourcePath, $TargetPath, $latestDirPath, $runDirName) {    

    # Step 1: Determine changes ==========================================================================================
    # ====================================================================================================================
    
    $sourceFiles = @(ls $SourcePath -Recurse)
    DebugOutput 'sourcefiles' $sourceFiles.Length
    
    $relativeSourcePath = NewRelativePathGenerator $SourcePath
    $sourcefiles | %{ 
        $relativePath = $relativeSourcePath.GetRelativePath($_.FullName);
        $targetPath = Join-Path $latestDirPath $relativePath
        "backup $relativePath"
        cp $_.FullName $targetPath
    }
}



# Self-Tests =========================================================================================================
# ====================================================================================================================

function TestGetRelativePath() {
    $testDirName = [guid]::NewGuid().ToString()
    mkdir $testDirName | Out-Null
    mkdir (Join-Path $testDirName 'subdir') | Out-Null

    $testDirObj = NewRelativePathGenerator $testDirName
    
    $testFileA = (Join-Path $testDirName 'testfile.txt')
    $testFileB = (Join-Path $testDirName 'subdir/testfile.txt')
    'test' > $testFileA
    'test' > $testFileB

    $result = $testDirObj.GetRelativePath((Resolve-Path $testFileA))
    if($result -ne 'testfile.txt') {
        Write-Error "A: $result"
    }

    $result = $testDirObj.GetRelativePath((Resolve-Path $testFileB))
    if($result -ne 'subdir/testfile.txt') {
        Write-Error "B: $result"
    }

    $result = (Join-Path $testDirName $result)
    if($result -ne "$testdirname\subdir\testfile.txt") {
        Write-Error "C: $result"
    }

    rm $testDirName -Recurse -Force
}

if($Test) {
    TestGetRelativePath
    exit
}
else {
    Main $SourcePath $TargetPath $latestDirPath $runDirName 2>&1 | %{ $_ >> $journalFile; $_ }
}