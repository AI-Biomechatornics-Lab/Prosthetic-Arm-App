const bridge = require('./pythonBridge.service');

async function connect() {
  bridge.start();
  return bridge.request('myo_connect');
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
