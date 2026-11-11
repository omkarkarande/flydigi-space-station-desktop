const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('controllerPicker', {
  watch: callback => { ipcRenderer.on('devices', (_event, devices) => callback(devices)); ipcRenderer.send('picker-ready'); },
  select: id => ipcRenderer.send('picker-select', id)
});
