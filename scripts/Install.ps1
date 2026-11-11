param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\Flydigi Space Station'),
    [string]$Version = '',
    [string]$Archive = '',
    [string]$ManifestFile = ''
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
if (Test-Path -LiteralPath (Join-Path $InstallRoot 'runtime-state.json')) { throw 'Already installed. Launch the existing app to update Electron.' }
if (-not $Version) {
    $release = Invoke-RestMethod 'https://api.github.com/repos/electron/electron/releases/latest' -Headers @{ 'User-Agent' = 'Flydigi-Space-Station-Desktop' }
    $Version = Get-ReleaseVersion $release
}
$Version = ConvertTo-StableVersion $Version
$null = New-Item -ItemType Directory -Path $InstallRoot -Force
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') -Destination (Join-Path $InstallRoot 'source') -Recurse
Copy-Item -LiteralPath $PSScriptRoot -Destination (Join-Path $InstallRoot 'scripts') -Recurse
$manifest = if ($ManifestFile) { Get-Content -LiteralPath $ManifestFile -Raw } else { '' }
Install-Runtime $InstallRoot $Version $Archive $manifest
$state = [pscustomobject]@{ active = $Version; previous = $null; blocked = @(); lastCheckUtc = $null; lastError = $null }
Write-RuntimeState $InstallRoot $state
$wsh = New-Object -ComObject WScript.Shell
foreach ($folder in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
    $shortcut = $wsh.CreateShortcut((Join-Path $folder 'Flydigi Space Station.lnk'))
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $shortcut.Arguments = '"' + (Join-Path $InstallRoot 'scripts\Launch.vbs') + '"'
    $shortcut.WorkingDirectory = $InstallRoot
    $shortcut.IconLocation = Join-Path $InstallRoot 'source\icon.ico'
    $shortcut.Description = 'Flydigi controller configuration with automatic Electron updates'
    $shortcut.Save()
}
Write-Output "Installed Flydigi Space Station with Electron $Version at $InstallRoot"
