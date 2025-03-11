[CmdletBinding(DefaultParameterSetName = 'default')]
Param(
    # Date's to test for expiration against $Policy.
    # all expired Dates will get returned / emitted.
    [Parameter(Mandatory, ParameterSetName = 'default')]
    [datetime[]]$DateList,

    # Policy to test all $Date's against.
    # eg.: '8days, 5weeks, 2months, 1years' will keep:
    # the latest date each for all of the last 8 days,
    # the latest date each for all of the last five weeks,
    # the latest date each for all of the last 2 months,
    # the latest date of the last year,
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

$VALID_RULE_NAMES = @('years', 'months', 'weeks', 'days')
"instead, go with something like 2/365days as: store 2 backups with 365 days cooldown in between"

# parse, sanity check policy
$policies = [System.Collections.ArrayList]::new()
$policyErrors = [System.Collections.ArrayList]::new()
$policyTokens = @($Policy.Split(',') | ForEach-Object { $_.Trim() })
foreach ($token in $policyTokens) {
    $tokenFormat = [regex]::Match($token, '(\d*)(\D*)')
    if (-not $tokenFormat.Success) {
        $policyErrors.Add("unrecognized policy format '$($token)'") | Out-Null
        continue
    }

    $quantifier = $tokenFormat.Groups[1].Value
    $rule = $tokenFormat.Groups[2].Value
    
    if ($VALID_RULE_NAMES -notcontains $rule) {
        $policyErrors.Add("unrecognized policy '$($token)'") | Out-Null
        continue
    }

    # todo: re'name' to cooldown
    $policies.Add(@{ 'name' = $rule; 'slots' = [Nullable[datetime][]]::new([int]$quantifier) }) | Out-Null
}

if ($policyErrors.Count -gt 0) {
    Write-Error ($policyErrors -join ', ')
    return
}

$dateListSorted = [System.Collections.ArrayList]::new()
$dateListSorted.AddRange(@($DateList | Sort-Object)) | Out-Null

$policies = @($policies | Sort-Object { $VALID_RULE_NAMES.IndexOf($_) } )
foreach ($date in $dateListSorted) {
    foreach ($policyItem in $policies) {
        $latestPolicySlot = @($policyItem.slots | Where-Object { $null -ne $_ }| Sort-Object -Descending | Select-Object -First 1)
        if($latestPolicySlot.Count -eq 0){
        $policyItem.slots[0] = $date
        }

        if($date - $latestPolicySlot){}
    }
}




$now = [datetime]::Now
foreach ($policyItem in $policies) {
    switch ($policyItem.name) {
        'years' {
            $now.AddYears(-$policyItem.quantity)
        }
    }
}