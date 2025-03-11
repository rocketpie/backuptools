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
    if ($expected.Count -eq 1) {
        AssertEqualItem $expected $actual
    }
    else {
        for ($i = 0; $i -lt $expected.Count; $i++) {
            AssertEqualItem $expected[$i] $actual[$i]
        }
    }
}

"TEST: Now fits 1/1s policy..."
$data = [datetime]::Now
$actual = & $sut -Date $data -Policy '1/1s'
$expected = $null
AssertEqual $expected $actual

"TEST: Now fits 1/1m policy..."
$data = [datetime]::Now
$actual = & $sut -Date $data -Policy '1/1h'
$expected = $null
AssertEqual $expected $actual

"TEST: Now fits 1/1d policy..."
$data = [datetime]::Now
$actual = & $sut -Date $data -Policy '1/1d'
$expected = $null
AssertEqual $expected $actual

"TEST: Now fits 1/1y policy..."
$data = [datetime]::Now
$actual = & $sut -Date $data -Policy '1/1y'
$expected = $null
AssertEqual $expected $actual

"TEST: Now and -2d in 1/1d expires -2d..."
$data = @([datetime]::Now, [datetime]::Now.AddDays(-2))
$actual = & $sut -Date $data -Policy '1/1d'
$expected = $data[1]
AssertEqual $expected $actual

# "TEST: two item pipe call..."
# $actual = $data | & $sut -Policy '1days'
# AssertEqual $expected $actual

