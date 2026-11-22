# Supervisor-only lifecycle support. No client launch, DLL loading, network or DB writes.
function New-LocalClientLifecycle {
    return @{ SeenClient=$false; AbsentSinceSeconds=$null; StopAttempted=$false }
}
function Update-LocalClientLifecycle {
    param(
        [Parameter(Mandatory=$true)][hashtable]$State,
        [bool]$ClientPresent,
        [bool]$ProbeSucceeded,
        [double]$NowSeconds,
        [ValidateRange(1,3600)][int]$GraceSeconds=30
    )
    if ($State.StopAttempted) { return $false }
    if (-not $ProbeSucceeded) {
        # An unreadable process is not evidence that the game exited.
        $State.AbsentSinceSeconds=$null
        return $false
    }
    if ($ClientPresent) {
        $State.SeenClient=$true
        $State.AbsentSinceSeconds=$null
        return $false
    }
    # A server started alone, or a failed launcher, must not trigger shutdown.
    if (-not $State.SeenClient) { return $false }
    if ($null -eq $State.AbsentSinceSeconds -or $NowSeconds -lt $State.AbsentSinceSeconds) {
        $State.AbsentSinceSeconds=$NowSeconds
        return $false
    }
    return ($NowSeconds-$State.AbsentSinceSeconds -ge $GraceSeconds)
}
function Test-IsolatedClientPath {
    param([string]$ActualPath,[string]$ExpectedPath)
    return (-not [string]::IsNullOrWhiteSpace($ActualPath) -and
        [string]::Equals($ActualPath,$ExpectedPath,[StringComparison]::OrdinalIgnoreCase))
}
function Get-IsolatedClientPresence {
    param([Parameter(Mandatory=$true)][string]$ExpectedPath)
    $processes=@()
    $present=$false
    $success=$true
    try {
        $processes=@([Diagnostics.Process]::GetProcessesByName('YuanShen'))
        foreach ($process in $processes) {
            try {
                if ($process.HasExited) { continue }
                if (Test-IsolatedClientPath $process.MainModule.FileName $ExpectedPath) { $present=$true }
            } catch {
                # Exit races and access failures are conservative: restart the grace timer.
                $success=$false
            }
        }
    } catch { $success=$false }
    finally { foreach ($process in $processes) { $process.Dispose() } }
    return [pscustomobject]@{Present=$present;Succeeded=$success}
}
