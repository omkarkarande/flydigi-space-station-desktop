# Flydigi Space Station Desktop

Unofficial standalone **Windows x64** app for [Flydigi Space Station](https://space_station.flydigi.com/), with a WebHID controller picker and automatic Electron runtime updates. Runs independently of Edge. Requires internet access.

## Install

Download or clone this repository. In Windows PowerShell, run from the repository folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install.ps1
```

The installer downloads the latest stable official Electron runtime, verifies its SHA-256 checksum, tests the sandboxed renderer and WebHID availability, and creates Desktop and Start menu shortcuts. No Node.js, npm, administrator account, GitHub token, paid hosting, or release server is needed to run the app.

Use the **Flydigi Space Station** shortcut. Connect your controller, click the website's connect button, and select it in the app's picker. Press **Alt** for the app menu; **Ctrl+R** reloads. App > Forget saved controllers resets device permissions.

## Automatic updates

- Launching the shortcut opens the current app immediately and starts a background check, at most once every 24 hours. Failed checks retry next launch.
- Only stable releases from the official `electron/electron` GitHub repository are eligible. Beta, nightly, draft, and older versions are rejected.
- A release downloads into a separate staging directory. The archive must match Electron's official SHA-256 manifest; unsafe ZIP paths are rejected.
- Before activation, the candidate must start a sandboxed renderer with WebHID available and Node.js unavailable to the page. This is a startup compatibility check, not a complete controller/firmware regression test.
- The active runtime pointer changes only after verification succeeds. **Close all app windows and launch again** to use the new version. Current controller sessions and firmware operations are never restarted by the updater.
- The previous runtime is retained for recovery. Network errors, GitHub rate limits, and failed verification leave the existing runtime active.
- Press Alt > Help > **Electron update status** to see the running/prepared versions or a failed check. **Check for Electron updates now** bypasses the daily throttle.

The updater includes future stable major versions so the app does not remain on an unsupported branch. Runtime updates are not a replacement for future maintenance of the wrapper itself. The Flydigi website updates independently; this updater does **not** fetch application source from this repository.

Electron's [security guidance](https://www.electronjs.org/docs/latest/tutorial/security) recommends current runtimes because Electron includes Chromium and Node.js security fixes. Waiting until something visibly breaks can leave vulnerabilities unpatched.

## Recovery

If a new runtime starts but behaves incorrectly, close the app and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\Flydigi Space Station\scripts\Launch.ps1" -Rollback
```

This opens the previous runtime and prevents reinstalling the rejected version. A newer release remains eligible. Downloaded runtimes are retained under `runtimes`; unused older versions can be removed after closing the app (keep the active and previous versions listed in `runtime-state.json`).

## Files and security

- Installation: `%LOCALAPPDATA%\Programs\Flydigi Space Station`.
- Controller grants, window preferences, and browser profile: `%APPDATA%\FlydigiSpaceStationDesktop`.
- Updater state: `runtime-state.json` inside the installation directory. No GitHub credentials are used by the updater.
- Remote website: sandboxed, context-isolated, with Node.js disabled and device permissions restricted to the exact Flydigi origin and explicitly selected devices.
- Devices without serial numbers may need selection again if Windows assigns a new device ID.
- Official runtime downloads and checksum manifests use HTTPS. Checksums detect corruption; this project is not signed or published by Flydigi. Upstream Electron licenses are bundled with every runtime.
- Launch through the shortcuts (or `scripts\Launch.vbs`) for automatic checks. Directly opening a runtime executable bypasses the launcher.

To uninstall, close the app and remove its installation directory and the two shortcuts. Optionally remove the profile directory to erase saved preferences. The first locally installed version may also have legacy runtime files at the installation root; these are unused by the new shortcuts.

## Development and validation

`src` contains the Electron wrapper; `scripts` contains the installer, launcher, and runtime updater. They use built-in Electron/Node/Windows APIs without npm dependencies. `Install.ps1 -Version X.Y.Z` pins the initial install only; later automatic checks use the latest stable release.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\runtime.tests.ps1
node --check .\src\main.js
node --check .\src\runtime-health.js
```

Tests cover stable-release filtering, invalid paths, archive integrity, ZIP traversal, atomic state writes, failed downloads, upgrade/fallback selection, daily throttling, downgrade prevention, and blocked releases. Installation also runs a real Electron renderer/WebHID smoke test. Hardware testing was performed with an APEX 6 Pro; other supported controllers depend on Flydigi's site.

Flydigi names, controller images, and the site favicon belong to their respective owners. This repository does not include the website or controller firmware.
