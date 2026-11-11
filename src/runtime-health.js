const { app, BrowserWindow } = require('electron');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function run() {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'flydigi-runtime-test-'));
  app.setPath('userData', temporary);
  const timer = setTimeout(() => app.exit(2), 30000);
  app.whenReady().then(async () => {
    const window = new BrowserWindow({ show: false, webPreferences: { sandbox: true, nodeIntegration: false, contextIsolation: true } });
    await window.loadFile(path.join(__dirname, 'health.html'));
    const healthy = await window.webContents.executeJavaScript("typeof navigator.hid === 'object' && typeof require === 'undefined' && window.isSecureContext");
    clearTimeout(timer);
    window.destroy();
    // Temporary Chromium files can still be locked until process exit.
    app.exit(healthy ? 0 : 3);
  }).catch(() => app.exit(4));
}
module.exports = { run };
