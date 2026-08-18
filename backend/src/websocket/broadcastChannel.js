const { WebSocketServer } = require('ws');

/**
 * A WebSocketServer that fans out one or more bridge events to every
 * connected client, as JSON, tagged with the bridge event's own name as
 * `type` so a single channel can carry more than one kind of message (e.g.
 * /servo/stream carries both "servo_dispatched" and "servo_moved").
 */
function createBroadcastChannel({ bridgeEvents, bridge }) {
  const wss = new WebSocketServer({ noServer: true });
  const events = Array.isArray(bridgeEvents) ? bridgeEvents : [bridgeEvents];

  for (const bridgeEvent of events) {
    bridge.on(bridgeEvent, (payload) => {
      const message = JSON.stringify({ type: bridgeEvent, payload, ts: Date.now() });
      for (const client of wss.clients) {
        if (client.readyState === client.OPEN) client.send(message);
      }
    });
  }

  wss.on('connection', (ws) => {
    ws.send(JSON.stringify({ type: 'connected', channels: events }));
  });

  return wss;
}

module.exports = createBroadcastChannel;
