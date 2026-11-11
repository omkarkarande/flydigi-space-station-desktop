const { app, BrowserWindow, Menu, dialog, ipcMain, session, shell } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const SITE = 'https://space_station.flydigi.com';
const NAME = 'Flydigi Space Station';
app.setName(NAME);
app.setAppUserModelId('local.flydigi.space-station');
app.setPath('userData', path.join(app.getPath('appData'), 'FlydigiSpaceStationDesktop'));
let main, picker, pending, grants = [], settings = {};
const dataFile = path.join(app.getPath('userData'), 'settings.json');
const pickerURL = pathToFileURL(path.join(__dirname, 'picker.html')).href;
const trusted = url => { try { return new URL(url).origin === SITE; } catch { return false; } };
const sameDevice = (a, b) => a.vendorId === b.vendorId && a.productId === b.productId &&
  (a.serialNumber ? a.serialNumber === b.serialNumber : a.deviceId === b.deviceId);
function save() {
  try { fs.mkdirSync(path.dirname(dataFile), { recursive: true }); fs.writeFileSync(dataFile, JSON.stringify({ ...settings, grants }, null, 2)); }
  catch (error) { console.error('Could not save preferences:', error.message); }
}
function finish(id) {
  if (!pending) return;
  const request = pending;
  pending = null;
  const device = request.devices.find(d => d.deviceId === id);
  if (device) { grants = grants.filter(d => !sameDevice(d, device)); grants.push(device); save(); }
  request.callback(device?.deviceId);
  if (picker && !picker.isDestroyed()) picker.close();
  picker = null;
}
function publishDevices() {
  if (picker && !picker.isDestroyed()) picker.webContents.send('devices', pending?.devices.map(d => ({
    deviceId: d.deviceId, name: d.name || 'HID controller', vendorId: d.vendorId, productId: d.productId
  })) || []);
}
function showPicker(details, callback) {
  finish();
  pending = { devices: details.deviceList.slice(), callback, frame: details.frame };
  picker = new BrowserWindow({ width: 520, height: 440, parent: main, modal: true,
    title: 'Connect a controller', backgroundColor: '#151923', autoHideMenuBar: true,
    icon: path.join(__dirname, 'icon.ico'),
    webPreferences: { preload: path.join(__dirname, 'picker-preload.js'), contextIsolation: true, sandbox: true, nodeIntegration: false }
  });
  picker.setMenu(null);
  picker.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  picker.webContents.on('will-navigate', event => event.preventDefault());
  picker.on('closed', () => finish());
  picker.loadFile(path.join(__dirname, 'picker.html'));
}
ipcMain.on('picker-ready', event => { if (event.sender === picker?.webContents && event.senderFrame.url === pickerURL) publishDevices(); });
ipcMain.on('picker-select', (event, id) => {
  if (event.sender === picker?.webContents && event.senderFrame.url === pickerURL && (id === null || typeof id === 'string')) finish(id);
});
async function loadSite() {
  try { await main.loadURL(SITE + '/'); }
  catch (error) {
    if (!main || main.isDestroyed() || error.code === 'ERR_ABORTED') return;
    const result = await dialog.showMessageBox(main, { type: 'error', title: NAME,
      message: 'Could not load Flydigi Space Station', detail: 'Check your internet connection and try again.\n\n' + error.message,
      buttons: ['Retry', 'Close'], defaultId: 0, cancelId: 1 });
    if (result.response === 0) loadSite(); else main.close();
  }
}
if (process.argv.includes('--runtime-health-check')) require('./runtime-health').run();
else if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => { if (main) { if (main.isMinimized()) main.restore(); main.show(); main.focus(); } });
  app.whenReady().then(() => {
    try { settings = JSON.parse(fs.readFileSync(dataFile, 'utf8')); grants = Array.isArray(settings.grants) ? settings.grants : []; } catch {}
    const ses = session.fromPartition('persist:flydigi');
    ses.setPermissionCheckHandler((wc, permission, origin) => wc === main?.webContents && permission === 'hid' && trusted(origin));
    ses.setPermissionRequestHandler((wc, permission, callback, details) => callback(wc === main?.webContents && permission === 'hid' && trusted(details.requestingUrl)));
    ses.setDevicePermissionHandler(details => details.deviceType === 'hid' && trusted(details.origin) && grants.some(d => sameDevice(d, details.device)));
    ses.on('select-hid-device', (event, details, callback) => {
      event.preventDefault();
      if (!details.frame || details.frame !== main?.webContents.mainFrame || !trusted(details.frame.url)) return callback();
      showPicker(details, callback);
    });
    ses.on('hid-device-added', (_event, details) => {
      if (pending && details.frame === pending.frame) { pending.devices = pending.devices.filter(d => d.deviceId !== details.device.deviceId); pending.devices.push(details.device); publishDevices(); }
    });
    ses.on('hid-device-removed', (_event, details) => {
      if (pending && details.frame === pending.frame) { pending.devices = pending.devices.filter(d => d.deviceId !== details.device.deviceId); publishDevices(); }
    });
    ses.on('hid-device-revoked', (_event, details) => { if (trusted(details.origin)) { grants = grants.filter(d => !sameDevice(d, details.device)); save(); } });
    main = new BrowserWindow({ width: settings.width || 1380, height: settings.height || 900,
      minWidth: 980, minHeight: 680, title: NAME, backgroundColor: '#101116',
      icon: path.join(__dirname, 'icon.ico'), autoHideMenuBar: true,
      webPreferences: { session: ses, nodeIntegration: false, contextIsolation: true, sandbox: true, webSecurity: true, spellcheck: false }
    });
    main.webContents.on('page-title-updated', event => { event.preventDefault(); main.setTitle(NAME); });
    main.webContents.on('will-navigate', (event, url) => { if (!trusted(url)) event.preventDefault(); });
    main.webContents.on('will-redirect', (event, url) => { if (!trusted(url)) event.preventDefault(); });
    main.webContents.on('did-start-navigation', (_event, _url, _inPlace, isMainFrame) => { if (isMainFrame) finish(); });
    main.webContents.setWindowOpenHandler(({ url }) => {
      if (trusted(url)) main.loadURL(url).catch(() => {});
      else if (/^https:\/\//i.test(url)) dialog.showMessageBox(main, { type: 'question', message: 'Open this link in your default browser?', detail: url, buttons: ['Cancel', 'Open'], cancelId: 0, defaultId: 0 }).then(r => { if (r.response === 1) shell.openExternal(url); });
      return { action: 'deny' };
    });
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      { label: 'App', submenu: [ { label: 'Home', click: loadSite },
        { label: 'Forget saved controllers', click: async () => { const r = await dialog.showMessageBox(main, { message: 'Forget controller permissions?', detail: 'You will be asked to choose your controller again.', buttons: ['Cancel', 'Forget'], defaultId: 0, cancelId: 0 }); if (r.response === 1) { finish(); grants = []; save(); main.webContents.reload(); } } },
        { type: 'separator' }, { role: 'quit' } ] },
      { label: 'View', submenu: [{ role: 'reload' }, { role: 'forceReload' }, { type: 'separator' }, { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { role: 'togglefullscreen' }] },
      { label: 'Help', submenu: [
        { label: 'Electron update status', click: () => {
          let detail = 'Running Electron ' + process.versions.electron;
          try {
            const state = JSON.parse(fs.readFileSync(path.join(process.env.FLYDIGI_INSTALL_ROOT, 'runtime-state.json'), 'utf8'));
            detail += '\nReady for next launch: ' + state.active + '\nLast successful check: ' + (state.lastCheckUtc || 'Not yet checked');
            if (state.lastError) detail += '\nLast update attempt: ' + state.lastError;
          } catch { detail += '\nUse the installed Desktop or Start menu shortcut to enable automatic updates.'; }
          dialog.showMessageBox(main, { title: 'Electron updates', message: 'Updates download in the background and apply on the next launch.', detail });
        } },
        { label: 'Check for Electron updates now', enabled: !!process.env.FLYDIGI_INSTALL_ROOT, click: () => {
          const { spawn } = require('node:child_process');
          const worker = spawn(path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
            ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', path.join(process.env.FLYDIGI_INSTALL_ROOT, 'scripts', 'Launch.ps1'), '-CheckOnly', '-ForceCheck'],
            { detached: true, windowsHide: true, stdio: 'ignore' });
          worker.on('error', error => { if (main && !main.isDestroyed()) dialog.showErrorBox('Update check failed', error.message); });
          worker.unref();
          dialog.showMessageBox(main, { message: 'Checking for updates in the background.', detail: 'You can keep using your controller. See Help > Electron update status for the result.' });
        } },
        { label: 'About', click: () => dialog.showMessageBox(main, { title: NAME, message: NAME + ' Desktop ' + app.getVersion(), detail: 'Unofficial local wrapper for the live Flydigi website.\nElectron ' + process.versions.electron + '\nInternet access required. Press Alt to show the menu.' }) }
      ] }
    ]));
    main.on('close', () => { finish(); const b = main.getNormalBounds(); settings.width = b.width; settings.height = b.height; settings.maximized = main.isMaximized(); save(); });
    main.on('closed', () => { main = null; });
    if (settings.maximized) main.maximize();
    loadSite();
  });
  app.on('window-all-closed', () => app.quit());
}
