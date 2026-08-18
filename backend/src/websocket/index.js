const { URL } = require('url');
const bridge = require('../services/pythonBridge.service');
const createBroadcastChannel = require('./broadcastChannel');
const attachLatencyLogger = require('./latencyLogger');

const CHANNELS = {
  '/myo/stream': ['emg_data'],
  // Throttled, pre-averaged ~20Hz feed for the dashboard chart, so it isn't
  // parsing the full ~200Hz raw stream just to average it back down anyway.
  // Calibration still reads raw /myo/stream, which needs full rate.
  '/myo/stream/preview': ['emg_data_preview'],
  // "warmup" fires once when control starts (ignore-predictions window);
  // "prediction" fires per confirmed gesture. Same channel, distinguished by
  // the message's own `type`.
  '/prediction/stream': ['prediction', 'warmup'],
  // Fires while a candidate gesture is still accumulating confident
  // predictions, before it's confirmed and sent to the servo - purely a UI
  // hint, never touches the logs (latencyLogger only listens for
  // 'prediction'/'servo_dispatched'/'servo_moved').
  '/prediction/stream/detecting': ['detecting'],
  // "servo_dispatched" fires the instant a confirmed gesture is handed to
  // the servo dispatcher (non-blocking); "servo_moved" fires once the
  // physical movement actually finishes. Splitting these is what lets
  // decision latency (dispatched - gesture start) be measured separately
  // from mechanical latency (moved - dispatched).
  '/servo/stream': ['servo_dispatched', 'servo_moved'],
};

function attachWebSockets(httpServer) {
  const wssByPath = Object.fromEntries(
    Object.entries(CHANNELS).map(([path, bridgeEvents]) => [
      path,
      createBroadcastChannel({ bridgeEvents, bridge }),
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
