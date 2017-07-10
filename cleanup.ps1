[CmdletBinding()]
Param(
    [Parameter()]
    [string]
    $Source = 'C:\D\tmp\test\src',

    [Parameter()]
    [string]
    $Target = 'C:\D\tmp\test\target',

    [Parameter()]
    [int]
    $Stage
)

switch($Stage) {
    1 {
        rm -Recurse -Force $Source
        mkdir $Source | Out-Null

        rm -Recurse -Force $Target
        mkdir $Target | Out-Null

        [guid]::NewGuid().ToString() > (join-path $Source 'File A.txt')         
        mkdir (join-path $Source 'subfolder') | Out-Null
        [guid]::NewGuid().ToString() > (join-path $Source (join-path 'subfolder' 'File B.txt'))
    }

    2 {
        [guid]::NewGuid().ToString() > (join-path $Source 'File C.txt')         
        rm (join-path $Source 'File A.txt')   
    }

}

#$a = [guid]::NewGuid().ToString()
#$b = [guid]::NewGuid().ToString()
#$c = [guid]::NewGuid().ToString()
#$d = [guid]::NewGuid().ToString()

#$a > (join-path $Source 'File A.txt')
#$b > (join-path $Source (join-path 'subfolder' 'File B.txt'))
#$c > (join-path $Source 'File C.txt')
##$d > (join-path $Source 'File D.txt')

##$a > (join-path $Target 'File A.txt')
#$b > (join-path $Target 'File B.txt')
#$c > (join-path $Target (join-path 'other subfolder' 'File C.txt'))
#$d > (join-path $Target 'File D.txt')

