const bridge = require('./pythonBridge.service');

async function connect() {
  bridge.start();
  // The bridge itself bounds its BLE scan to 25s and reports a clean error
  // if nothing's found. But on a cold start (process just spawned) loading
  // the model can itself take 15-20s *before* scanning even begins, so this
  // needs enough headroom to cover startup + the full scan window, not just
  // the scan alone - otherwise Node gives up first with a bare timeout
  // instead of letting the bridge's own clear error come back.
  return bridge.request('myo_connect', {}, 50000);
}

async function disconnect() {
  return bridge.request('myo_disconnect');
}

async function battery() {
  return bridge.request('myo_battery');
}

async function powerOff() {
  return bridge.request('myo_poweroff');
}

module.exports = { connect, disconnect, battery, powerOff };
