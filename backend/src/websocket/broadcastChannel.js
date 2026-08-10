const { WebSocketServer } = require('ws');

/**
 * A WebSocketServer that just fans out one bridge event to every connected client,
 * as JSON. Used identically by the EMG, prediction and servo streams.
 */
function createBroadcastChannel({ bridgeEvent, bridge }) {
  const wss = new WebSocketServer({ noServer: true });

  const onEvent = (payload) => {
    const message = JSON.stringify({ type: bridgeEvent, payload, ts: Date.now() });
    for (const client of wss.clients) {
      if (client.readyState === client.OPEN) client.send(message);
    }
  };

  bridge.on(bridgeEvent, onEvent);

  wss.on('connection', (ws) => {
    ws.send(JSON.stringify({ type: 'connected', channel: bridgeEvent }));
  });

  return wss;
}

module.exports = createBroadcastChannel;
