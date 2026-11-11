$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\scripts\Runtime.psm1') -Force
$script:count = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message }; $script:count++ }
function Assert-Throws([scriptblock]$Action, [string]$Message) { $threw = $false; try { & $Action } catch { $threw = $true }; Assert $threw $Message }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('flydigi-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
try {
    Assert ((ConvertTo-StableVersion 'v45.3.0') -eq '45.3.0') 'Stable version parsing failed'
    foreach ($invalid in @('45.3.0-beta.1', '..\outside', 'v45.0', '45.3.0;cmd', 'https://host', '01.2.3')) {
        Assert-Throws { ConvertTo-StableVersion $invalid } "Accepted unsafe version: $invalid"
    }
    Assert-Throws { Get-ReleaseVersion ([pscustomobject]@{ draft = $false; prerelease = $true; tag_name = 'v46.0.0-beta.1' }) } 'Accepted prerelease'
    $file = Join-Path $temporary 'archive.zip'
    [IO.File]::WriteAllText($file, 'fixture')
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    Assert-Checksum $file "$hash *electron-v45.3.0-win32-x64.zip" 'electron-v45.3.0-win32-x64.zip'
    $script:count++
    Assert-Throws { Assert-Checksum $file (('0' * 64) + ' *electron-v45.3.0-win32-x64.zip') 'electron-v45.3.0-win32-x64.zip' } 'Accepted corrupt download'
    Assert-Throws { Assert-Checksum $file "$hash *other.zip" 'electron-v45.3.0-win32-x64.zip' } 'Accepted wrong checksum filename'
    Assert-Throws { Assert-Checksum $file "$hash *test.zip`n$hash *test.zip" 'test.zip' } 'Accepted ambiguous checksum'
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $badZip = Join-Path $temporary 'bad.zip'
    $zip = [IO.Compression.ZipFile]::Open($badZip, [IO.Compression.ZipArchiveMode]::Create)
    $null = $zip.CreateEntry('../escaped.txt')
    $zip.Dispose()
    Assert-Throws { Expand-VerifiedArchive $badZip (Join-Path $temporary 'expanded') } 'ZIP traversal accepted'
    Assert (-not (Test-Path -LiteralPath (Join-Path $temporary 'escaped.txt'))) 'ZIP wrote outside destination'
    $state = [pscustomobject]@{ active = '45.3.0'; previous = $null; blocked = @(); lastCheckUtc = $null; lastError = $null }
    Write-RuntimeState $temporary $state
    Assert ((Read-RuntimeState $temporary).active -eq '45.3.0') 'State round-trip failed'
    $module = Get-Module Runtime
    & $module {
        $script:release = [pscustomobject]@{ draft = $false; prerelease = $false; tag_name = 'v45.4.0' }
        $script:downloadFails = $true
        $script:calls = 0
        function script:Invoke-RestMethod { $script:calls++; return $script:release }
        function script:Install-Runtime { if ($script:downloadFails) { throw 'Download failed' } }
    }
    Update-Runtime $temporary -ForceCheck
    $state = Read-RuntimeState $temporary
    Assert ($state.active -eq '45.3.0' -and $state.lastError -eq 'Download failed') 'Failure replaced working runtime'
    & $module { $script:downloadFails = $false }
    Update-Runtime $temporary -ForceCheck
    $state = Read-RuntimeState $temporary
    Assert ($state.active -eq '45.4.0' -and $state.previous -eq '45.3.0') 'Update did not preserve fallback'
    $callsBefore = & $module { $script:calls }
    Update-Runtime $temporary
    Assert ((& $module { $script:calls }) -eq $callsBefore) 'Daily throttle failed'
    & $module { $script:release.tag_name = 'v44.9.0' }
    Update-Runtime $temporary -ForceCheck
    Assert ((Read-RuntimeState $temporary).active -eq '45.4.0') 'Updater downgraded runtime'
    $state = Read-RuntimeState $temporary
    $state.blocked = @('46.0.0')
    Write-RuntimeState $temporary $state
    & $module { $script:release.tag_name = 'v46.0.0' }
    Update-Runtime $temporary -ForceCheck
    Assert ((Read-RuntimeState $temporary).active -eq '45.4.0') 'Reinstalled rejected runtime'
    Write-Output "PASS: $script:count updater assertions"
} finally {
    $full = [IO.Path]::GetFullPath($temporary)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\flydigi-tests-'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
