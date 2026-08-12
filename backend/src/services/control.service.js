const bridge = require('./pythonBridge.service');

async function start(userId) {
  bridge.start();
  return bridge.request('start_control', { userId }, 15000);
}

async function stop() {
  bridge.start();
  return bridge.request('stop_control', {}, 15000);
}

module.exports = { start, stop };
