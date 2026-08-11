const { URL } = require('url');
const bridge = require('../services/pythonBridge.service');
const createBroadcastChannel = require('./broadcastChannel');
const attachLatencyLogger = require('./latencyLogger');

const CHANNELS = {
  '/myo/stream': 'emg_data',
  // Throttled, pre-averaged ~20Hz feed for the dashboard chart, so it isn't
  // parsing the full ~200Hz raw stream just to average it back down anyway.
  // Calibration still reads raw /myo/stream, which needs full rate.
  '/myo/stream/preview': 'emg_data_preview',
  '/prediction/stream': 'prediction',
  '/servo/stream': 'servo_event',
};

function attachWebSockets(httpServer) {
  const wssByPath = Object.fromEntries(
    Object.entries(CHANNELS).map(([path, bridgeEvent]) => [
      path,
      createBroadcastChannel({ bridgeEvent, bridge }),
    ]),
  );

  attachLatencyLogger(bridge);

  httpServer.on('upgrade', (req, socket, head) => {
    const { pathname } = new URL(req.url, `http://${req.headers.host}`);
    const wss = wssByPath[pathname];
    if (!wss) {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit('connection', ws, req);
    });
  });
}

module.exports = attachWebSockets;
