const pool = require('../db/pool');

const SELECT_COLUMNS = `id, prediction, confidence, servo_command, gesture_start_time,
  data_received_time, prediction_time, servo_time, servo_moved_time,
  latency_ms, physical_latency_ms, session_started_at, created_at`;

async function getLogs(userId) {
  const { rows } = await pool.query(
    `SELECT ${SELECT_COLUMNS} FROM logs WHERE user_id = $1 ORDER BY created_at ASC`,
    [userId],
  );
  return rows;
}

/** Just the logs from the most recent control session (the last /control/start call). */
async function getLatestSessionLogs(userId) {
  const { rows } = await pool.query(
    `SELECT ${SELECT_COLUMNS} FROM logs
     WHERE user_id = $1 AND session_started_at = (
       SELECT MAX(session_started_at) FROM logs WHERE user_id = $1
     )
     ORDER BY created_at ASC`,
    [userId],
  );
  return rows;
}

async function recordLog(userId, entry) {
  const {
    prediction, confidence, servoCommand,
    gestureStartTime, dataReceivedTime, predictionTime, servoTime, servoMovedTime,
    latencyMs, physicalLatencyMs, sessionStartedAt,
  } = entry;
  const { rows } = await pool.query(
    `INSERT INTO logs (
       user_id, prediction, confidence, servo_command,
       gesture_start_time, data_received_time, prediction_time, servo_time, servo_moved_time,
       latency_ms, physical_latency_ms, session_started_at
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING *`,
    [
      userId, prediction, confidence, servoCommand,
      gestureStartTime, dataReceivedTime, predictionTime, servoTime, servoMovedTime,
      latencyMs, physicalLatencyMs, sessionStartedAt,
    ],
  );
  return rows[0];
}

module.exports = { getLogs, getLatestSessionLogs, recordLog };
