[CmdletBinding(DefaultParameterSetName = 'default')]
Param(
    [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'default')]
    [datetime]$Date,
    [Parameter(ParameterSetName = 'default')]
    [string]$Policy,

    [Parameter(ParameterSetName = 'selftest')]
    [switch]$Test
)
begin {
    if ($PSCmdlet.ParameterSetName -eq 'selftest') {
        & (Join-Path $PSScriptRoot "Get-ExpiredRetentionDate.Test.ps1")
        return
    }

    if ($PSBoundParameters['Debug']) {
        $DebugPreference = 'Continue'
    }

    Write-Debug "begin"
    Write-Debug "Date.Count: $($Date.Count)"
}
process {
    Write-Debug "process"    
    Write-Debug "Date.Count: $($Date.Count)"

    if ($Date.Count -eq 1) {
        Write-Debug "assigning item from `$Date[0]"
        $item = $Date[0]
    }
    else {
        Write-Debug "assigning item from `$_"
        $item = $_	
    }
    Write-Debug "returning item: $($item)"
    return $item
}
end {
    Write-Debug "end"
}



