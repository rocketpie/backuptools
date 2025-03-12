$sut = (Join-Path $PSScriptRoot 'Get-ExpiredRetentionDate.ps1')

function AssertEqualItem($expected, $actual) {
    if ($null -eq $expected) {
        if ($null -eq $actual) {
            return
        }
        else {
            Write-Error "expected item null, but got $($actual.GetType().Name)"
            return
        }
    }
    
    $expectedTypeName = $expected.GetType().FullName
    if ($null -eq $actual) {
        Write-Error "expected item type '$($expectedTypeName)', but got (null)"
        return
    }

    $actualTypeName = $actual.GetType().FullName
    if ($expectedTypeName -ne $actualTypeName) {
        Write-Error "expected item type '$($expectedTypeName)' but got '$($actualTypeName)'"        
        return
    }

    $expectedTostring = $expected.ToString()
    $actualTostring = $actual.ToString()
    if ($expectedTostring -ne $actualTostring) {
        Write-Error "expected item .ToString() '$($expectedTostring)' but got '$($actualTostring)'"
        return
    }    

    if ($expectedTypeName -eq [datetime]::Now.GetType().FullName) {
        Write-Debug "'$($actualTostring)' is equal to '$($expectedTostring)'"
        return
    }
    
    Write-Warning "assert: is ($($actualTypeName))'$($actualTostring)' equal to ($($expectedTypeName)'$($expectedTostring)'?"
}

function AssertEqual($expected, $actual) {
    if ($null -eq $expected) {
        if ($null -eq $actual) {
            return
        }
        else {
            Write-Error "expected null, but got $($actual.GetType().Name)"
            return
        }
    }
    
    $expectedTypeName = $expected.GetType().FullName
    if ($null -eq $actual) {
        Write-Error "expected type '$($expectedTypeName)', but got (null)"
        return
    }

    $actualTypeName = $actual.GetType().FullName
    if ($expectedTypeName -ne $actualTypeName) {
        Write-Error "expected type '$($expectedTypeName)' but got '$($actualTypeName)'"        
        return
    }

    if ($expected.Count -ne $actual.Count) {
        Write-Error "expected .Count: $($expected.Count) but got $($actual.Count)"
        return
    }

    if ($expectedTypeName -eq 'System.Object[]') {
        for ($i = 0; $i -lt $expected.Count; $i++) {
            AssertEqualItem $expected[$i] $actual[$i]
        }
    }
    else {
        AssertEqualItem $expected $actual
    }
}

"TEST: Now fits 1/1s policy..."
$data = [datetime]::Now
$actual = @(& $sut -Date $data -Policy '1/1s')
$expected = @()
AssertEqual $expected $actual

"TEST: Now fits 1/1m policy..."
$data = [datetime]::Now
$actual = @(& $sut -Date $data -Policy '1/1h')
$expected = @()
AssertEqual $expected $actual

"TEST: Now fits 1/1d policy..."
$data = [datetime]::Now
$actual = @(& $sut -Date $data -Policy '1/1d')
$expected = @()
AssertEqual $expected $actual

"TEST: Now fits 1/1y policy..."
$data = [datetime]::Now
$actual = @(& $sut -Date $data -Policy '1/1y')
$expected = @()
AssertEqual $expected $actual

"TEST: Now and -2d in 1/1d expires -2d..."
$data = @([datetime]::Now, [datetime]::Now.AddDays(-2))
$actual = @(& $sut -Date $data -Policy '1/1d')
$expected = @($data[1])
AssertEqual $expected $actual

"TEST: Now and -2d in 1/1d,1/1w doesn't expire anything..."
$data = @([datetime]::Now, [datetime]::Now.AddDays(-2))
$actual = @(& $sut -Date $data -Policy '1/1d, 1/1w')
$expected = @()
AssertEqual $expected $actual

"TEST: -1d and -30min in 2/1d keeps both, despite being less than 1d apart (23:30)..."
$data = @([datetime]::Now.AddDays(-1), [datetime]::Now.AddMinutes(-30))
$actual = @(& $sut -Date $data -Policy '2/1d')
$expected = @()
AssertEqual $expected $actual

"TEST: -1d and -60min in 2/1d expires the latest, for being less than 1d apart (23:00)..."
$data = @([datetime]::Now.AddDays(-1), [datetime]::Now.AddMinutes(-60))
$actual = @(& $sut -Date $data -Policy '2/1d')
$expected = @($data[1])
AssertEqual $expected $actual



# "TEST: two item pipe call..."
# $actual = $data | & $sut -Policy '1days'
# AssertEqual $expected $actual

