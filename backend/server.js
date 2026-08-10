const http = require('http');
const app = require('./src/app');
const env = require('./src/config/env');
const attachWebSockets = require('./src/websocket');

const server = http.createServer(app);
attachWebSockets(server);

server.listen(env.port, '0.0.0.0', () => {
  console.log(`Prosthetic Arm API listening on port ${env.port} (${env.nodeEnv})`);
});
