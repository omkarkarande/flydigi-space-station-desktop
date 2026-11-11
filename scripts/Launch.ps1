param([switch]$CheckOnly, [switch]$ForceCheck, [switch]$Rollback)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
$mutex = New-Object Threading.Mutex($false, 'Local\FlydigiSpaceStationRuntimeUpdate')
$owned = $false
try {
    try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    $state = Read-RuntimeState $root
    if ($Rollback) {
        if (-not $owned) { throw 'An update is in progress. Try rollback after it finishes.' }
        if (-not $state.previous) { throw 'No previous runtime is available' }
        $state.blocked = @($state.blocked) + $state.active
        $state.active = $state.previous
        $state.previous = $null
        Write-RuntimeState $root $state
    }
    if (-not $CheckOnly) {
        $exe = Join-Path (Get-RuntimePath $root $state.active) 'Flydigi Space Station.exe'
        $env:FLYDIGI_INSTALL_ROOT = $root
        Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
        # Show the app immediately; network and extraction happen afterward.
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -WindowStyle Normal
    }
    if ($owned -and -not $Rollback) { Update-Runtime $root -ForceCheck:$ForceCheck }
} catch {
    [IO.File]::WriteAllText((Join-Path $root 'launcher-error.log'), $_.Exception.ToString())
    if (-not $CheckOnly) {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Flydigi Space Station') | Out-Null
    }
} finally {
    if ($owned) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
