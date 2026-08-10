const logsService = require('../services/logs.service');

/**
 * Correlates `prediction` and `servo_event` bridge messages (matched by
 * predictionId) and persists one log row per pair once both sides arrive.
 * Expects payloads shaped like:
 *   prediction:  { predictionId, userId, gesture, confidence, timestamp }
 *   servo_event: { predictionId, userId, command, timestamp }
 */
function attachLatencyLogger(bridge) {
  const pending = new Map();

  bridge.on('prediction', (payload) => {
    pending.set(payload.predictionId, payload);
  });

  bridge.on('servo_event', async (payload) => {
    const prediction = pending.get(payload.predictionId);
    if (!prediction) return;
    pending.delete(payload.predictionId);

    const predictionTime = new Date(prediction.timestamp);
    const servoTime = new Date(payload.timestamp);

    try {
      await logsService.recordLog(payload.userId ?? prediction.userId, {
        prediction: prediction.gesture,
        confidence: prediction.confidence,
        servoCommand: payload.command,
        predictionTime,
        servoTime,
        latencyMs: servoTime - predictionTime,
      });
    } catch (err) {
      console.error('Failed to record log entry', err);
    }
  });
}

module.exports = attachLatencyLogger;
