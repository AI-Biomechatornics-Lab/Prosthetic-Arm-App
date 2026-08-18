const logsService = require('../services/logs.service');
const sessionTracker = require('../services/sessionTracker');

/**
 * Correlates `prediction`, `servo_dispatched` and `servo_moved` bridge
 * messages (matched by predictionId) and persists one log row once all
 * three have arrived for a given prediction. Expects payloads shaped like:
 *   prediction:       { predictionId, userId, gesture, confidence, gestureStartTime, dataReceivedTime, timestamp }
 *   servo_dispatched: { predictionId, userId, command, timestamp }
 *   servo_moved:      { predictionId, userId, command, timestamp }
 *
 * latencyMs ("decision latency") spans gestureStartTime -> servo_dispatched
 * timestamp: the pipeline from the oldest EMG sample the model used for this
 * prediction through inference to the servo command being dispatched -
 * this is the number that matters for responsiveness, since dispatch is
 * now non-blocking (see ServoDispatcher in the bridge).
 *
 * physicalLatencyMs spans servo_dispatched -> servo_moved: the mechanical
 * time for the servo to actually finish moving, which is expected to be
 * slow (800-1500ms) and tracked separately so it doesn't get conflated with
 * how responsive the AI pipeline itself is.
 */
function attachLatencyLogger(bridge) {
  const pending = new Map(); // predictionId -> { prediction, dispatched }

  bridge.on('prediction', (payload) => {
    const entry = pending.get(payload.predictionId) ?? {};
    entry.prediction = payload;
    pending.set(payload.predictionId, entry);
  });

  bridge.on('servo_dispatched', (payload) => {
    const entry = pending.get(payload.predictionId);
    if (!entry) return;
    entry.dispatched = payload;
  });

  bridge.on('servo_moved', async (payload) => {
    const entry = pending.get(payload.predictionId);
    if (!entry || !entry.prediction || !entry.dispatched) return;
    pending.delete(payload.predictionId);

    const { prediction, dispatched } = entry;
    const gestureStartTime = new Date(prediction.gestureStartTime);
    const dataReceivedTime = new Date(prediction.dataReceivedTime);
    const predictionTime = new Date(prediction.timestamp);
    const servoTime = new Date(dispatched.timestamp);
    const servoMovedTime = new Date(payload.timestamp);
    const userId = payload.userId ?? dispatched.userId ?? prediction.userId;
    const sessionStartedAt = sessionTracker.getCurrentSessionStart(userId) ?? gestureStartTime;

    try {
      await logsService.recordLog(userId, {
        prediction: prediction.gesture,
        confidence: prediction.confidence,
        servoCommand: payload.command,
        gestureStartTime,
        dataReceivedTime,
        predictionTime,
        servoTime,
        servoMovedTime,
        latencyMs: servoTime - gestureStartTime,
        physicalLatencyMs: servoMovedTime - servoTime,
        sessionStartedAt,
      });
    } catch (err) {
      console.error('Failed to record log entry', err);
    }
  });
}

module.exports = attachLatencyLogger;
