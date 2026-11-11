const container = document.getElementById('devices');
window.controllerPicker.watch(devices => {
  container.replaceChildren();
  if (!devices.length) { const p = document.createElement('p'); p.textContent = 'No compatible controllers found. Connect your controller by USB or its receiver. New devices appear here automatically.'; container.append(p); }
  for (const device of devices) {
    const button = document.createElement('button'); button.className = 'device'; button.textContent = device.name;
    const detail = document.createElement('small'); detail.textContent = `USB ${device.vendorId.toString(16).padStart(4, '0')}:${device.productId.toString(16).padStart(4, '0')}`;
    button.append(detail); button.onclick = () => window.controllerPicker.select(device.deviceId); container.append(button);
  }
});
document.getElementById('cancel').onclick = () => window.controllerPicker.select(null);
document.addEventListener('keydown', event => { if (event.key === 'Escape') window.controllerPicker.select(null); });
