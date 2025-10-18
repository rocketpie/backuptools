[CmdletBinding(DefaultParameterSetName = 'default')]
Param(
    # Date's to test for expiration against $Policy.
    # all expired Dates will get returned / emitted.
    [Parameter(Mandatory, ParameterSetName = 'default')]
    [datetime[]]$DateList,

    # Policy to test all $Date's against.
    # eg.: '3/1d, 2/7d, 4/1y' will try to keep 9 dates:
    # the latest three dates that are at least 1d apart,
    # the latest two dates that are at least 7 days apart,
    # the latest four dates that are at least 1 year apart
    # (timing allows for 3% variation)
    # valid identifiers are: (s)econds (h)ours (d)ays (w)eeks (y)ears
    [Parameter(Mandatory, ParameterSetName = 'default')]
    [string]$Policy,

    [Parameter(ParameterSetName = 'selftest')]
    [switch]$Test
)

if ($PSCmdlet.ParameterSetName -eq 'selftest') {
    & (Join-Path $PSScriptRoot "Get-ExpiredRetentionDate.Test.ps1")
    return
}

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

# parse, sanity check policy
$policies = [System.Collections.ArrayList]::new()
$policyErrors = [System.Collections.ArrayList]::new()
$policyTokens = @($Policy.Split(',') | ForEach-Object { $_.Trim() })
foreach ($token in $policyTokens) {
    $token = $token.Trim()
    $tokenFormat = [regex]::Match($token, '^(\d+)/(\d+)([shdwy])$')
    if (-not $tokenFormat.Success) {
        $policyErrors.Add("unrecognized policy format '$($token)'") | Out-Null
        continue
    }

    $slotCount = $tokenFormat.Groups[1].Value
    $quantifier = $tokenFormat.Groups[2].Value
    $unit = $tokenFormat.Groups[3].Value
  
    switch ($unit) {
        's' { $cooldown = [timespan]::FromSeconds($quantifier) }
        'h' { $cooldown = [timespan]::FromHours($quantifier) }
        'd' { $cooldown = [timespan]::FromDays($quantifier) }
        'w' { $cooldown = [timespan]::FromDays(7 * $quantifier) }
        'y' { $cooldown = [timespan]::FromDays(365 * $quantifier) }
    }
    
    # reduce the cooldown by 3% to allow for some variation in backup timestamps
    $cooldown = $cooldown.Add([timespan]::FromMilliseconds(-($cooldown.TotalMilliseconds * 0.03)))

    $policies.Add(
        @{ 
            'name'     = $token; 
            'slots'    = $slotCount
            'cooldown' = $cooldown
            'queue'    = [System.Collections.Queue]::new()
        }
    ) | Out-Null
}

if ($policyErrors.Count -gt 0) {
    Write-Error ($policyErrors -join ', ')
    return
}

function AddNext($Policy, $Date) {
    $latestItem = $Policy.queue | Sort-Object | Select-Object -First 1
    
    if (($null -eq $latestItem) -or ($Date -gt ($latestItem.Add($Policy.cooldown)))) {
        $Policy.queue.Enqueue($Date)
        
        if ($Policy.queue.Count -gt $Policy.slots) {
            $expiredDate = $Policy.queue.Dequeue()
            
            Write-Debug "policy overflow: $($expiredDate.ToString('u'))"
            return $expiredDate
        }
        
        # date fits the policy
        return $null
    }
    
    Write-Debug "date isn't young enough to fit into this policy"
    return $Date
}

$policies = @($policies | Sort-Object -Property 'cooldown' )

$dateListSorted = [System.Collections.ArrayList]::new()
$dateListSorted.AddRange(@($DateList | Sort-Object)) | Out-Null

$expiredDates = [System.Collections.ArrayList]::new()
foreach ($nextDate in $dateListSorted) {
    
    $dateToFit = $nextDate
    foreach ($policyItem in $policies) {
        Write-Debug "fitting '$($nextDate.ToString('u'))' into '$($policyItem.name)'..."
        $result = AddNext -policy $policyItem -date $dateToFit
        if ($null -eq $result) { 
            Write-Debug "fits"
            break;
        }        
        if ($nextDate -eq $result) {
            Write-Debug "doesn't fit yet"
            break;
        }
        
        # now we need to try to fit the overflowed date into the next policy
        $dateToFit = $result
    }

    if ($null -ne $result) {
        Write-Debug "expiring '$($result.ToString('u'))'"
        $expiredDates.Add($result) | Out-Null
    }    
}

$expiredDates