Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-StableVersion([string]$Value) {
    if ($Value -notmatch '^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Invalid stable Electron version' }
    return $Value.TrimStart('v')
}

function Get-RuntimePath([string]$Root, [string]$Version) {
    $versionText = ConvertTo-StableVersion $Version
    return Join-Path ([IO.Path]::GetFullPath($Root)) "runtimes\$versionText"
}

function Read-RuntimeState([string]$Root) {
    $state = Get-Content -LiteralPath (Join-Path $Root 'runtime-state.json') -Raw | ConvertFrom-Json
    $null = ConvertTo-StableVersion $state.active
    if ($state.previous) { $null = ConvertTo-StableVersion $state.previous }
    return $state
}

function Write-RuntimeState([string]$Root, $State) {
    $target = Join-Path $Root 'runtime-state.json'
    $temporary = Join-Path $Root ('state-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 6))
    if (Test-Path -LiteralPath $target) { [IO.File]::Replace($temporary, $target, ($target + '.bak')) }
    else { [IO.File]::Move($temporary, $target) }
}

function Get-ReleaseVersion($Release) {
    if ($Release.draft -or $Release.prerelease) { throw 'Preview releases are not allowed' }
    return ConvertTo-StableVersion $Release.tag_name
}

function Assert-Checksum([string]$Archive, [string]$Manifest, [string]$AssetName) {
    $matching = @($Manifest -split '\r?\n' | Where-Object { $_ -match ('^[a-fA-F0-9]{64}\s+\*?' + [regex]::Escape($AssetName) + '$') })
    if ($matching.Count -ne 1) { throw 'Missing or ambiguous Electron checksum' }
    $expected = ($matching[0] -split '\s+')[0]
    if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $expected) { throw 'Electron checksum mismatch' }
}

function Expand-VerifiedArchive([string]$Archive, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $prefix = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $entryName = $entry.FullName.Replace('/', '\')
            if ($entryName.Contains(':') -or [IO.Path]::IsPathRooted($entryName)) { throw 'Unsafe ZIP entry' }
            $full = [IO.Path]::GetFullPath((Join-Path $Destination $entryName))
            if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'ZIP entry escapes runtime directory' }
            if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'ZIP links are not permitted' }
        }
    } finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination)
}

function Test-Runtime([string]$Directory) {
    $exe = Join-Path $Directory 'Flydigi Space Station.exe'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $exe
    $start.Arguments = '--runtime-health-check'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WorkingDirectory = $Directory
    $start.EnvironmentVariables.Remove('ELECTRON_RUN_AS_NODE')
    $process = [Diagnostics.Process]::Start($start)
    try {
        if (-not $process.WaitForExit(45000)) { $process.Kill(); throw 'Electron startup test timed out' }
        if ($process.ExitCode -ne 0) { throw "Electron startup test failed ($($process.ExitCode))" }
    } finally { $process.Dispose() }
}

function Install-Runtime([string]$Root, [string]$Version, [string]$Archive = '', [string]$Manifest = '') {
    $Version = ConvertTo-StableVersion $Version
    $destination = Get-RuntimePath $Root $Version
    if (Test-Path -LiteralPath $destination) { Test-Runtime $destination; return }
    $stagingRoot = Join-Path $Root 'staging'
    $work = Join-Path $stagingRoot ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $work -Force
    try {
        $asset = "electron-v$Version-win32-x64.zip"
        if (-not $Archive) {
            $base = "https://github.com/electron/electron/releases/download/v$Version/"
            $Archive = Join-Path $work $asset
            Invoke-WebRequest -UseBasicParsing -Uri ($base + $asset) -OutFile $Archive -TimeoutSec 600
            $Manifest = (Invoke-WebRequest -UseBasicParsing -Uri ($base + 'SHASUMS256.txt') -TimeoutSec 60).Content
        }
        Assert-Checksum $Archive $Manifest $asset
        $runtime = Join-Path $work 'runtime'
        Expand-VerifiedArchive $Archive $runtime
        foreach ($required in @('electron.exe', 'resources', 'icudtl.dat', 'LICENSE', 'LICENSES.chromium.html')) {
            if (-not (Test-Path -LiteralPath (Join-Path $runtime $required))) { throw "Missing runtime file: $required" }
        }
        Rename-Item -LiteralPath (Join-Path $runtime 'electron.exe') -NewName 'Flydigi Space Station.exe'
        $appSource = Join-Path $Root 'source'
        Copy-Item -LiteralPath $appSource -Destination (Join-Path $runtime 'resources\app') -Recurse
        Test-Runtime $runtime
        $null = New-Item -ItemType Directory -Path (Join-Path $Root 'runtimes') -Force
        Move-Item -LiteralPath $runtime -Destination $destination
    } finally {
        $resolvedWork = [IO.Path]::GetFullPath($work)
        $expectedPrefix = [IO.Path]::GetFullPath($stagingRoot).TrimEnd('\') + '\'
        if (-not $resolvedWork.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid staging cleanup path' }
        if (Test-Path -LiteralPath $resolvedWork) { Remove-Item -LiteralPath $resolvedWork -Recurse -Force }
    }
}

function Update-Runtime([string]$Root, [switch]$ForceCheck) {
    $state = Read-RuntimeState $Root
    if (-not $ForceCheck -and $state.lastCheckUtc -and ([DateTime]::UtcNow - [DateTime]::Parse($state.lastCheckUtc).ToUniversalTime()).TotalHours -lt 24) { return }
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/electron/electron/releases/latest' -Headers @{ 'User-Agent' = 'Flydigi-Space-Station-Desktop'; Accept = 'application/vnd.github+json' } -TimeoutSec 30
        $version = Get-ReleaseVersion $release
        if ([version]$version -gt [version]$state.active -and $version -notin @($state.blocked)) {
            Install-Runtime $Root $version
            $state.previous = $state.active
            $state.active = $version
        }
        $state.lastCheckUtc = [DateTime]::UtcNow.ToString('o')
        $state.lastError = $null
    } catch {
        $state.lastError = $_.Exception.Message
        # Failed checks retry on the next launch; no active version is changed.
    }
    Write-RuntimeState $Root $state
}

Export-ModuleMember -Function ConvertTo-StableVersion, Get-RuntimePath, Read-RuntimeState, Write-RuntimeState, Get-ReleaseVersion, Assert-Checksum, Expand-VerifiedArchive, Test-Runtime, Install-Runtime, Update-Runtime
