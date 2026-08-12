const pool = require('../db/pool');

async function getLogs(userId) {
  const { rows } = await pool.query(
    `SELECT id, prediction, confidence, servo_command, gesture_start_time,
            data_received_time, prediction_time, servo_time, latency_ms, created_at
     FROM logs WHERE user_id = $1 ORDER BY created_at ASC`,
    [userId],
  );
  return rows;
}

async function recordLog(userId, entry) {
  const {
    prediction, confidence, servoCommand,
    gestureStartTime, dataReceivedTime, predictionTime, servoTime, latencyMs,
  } = entry;
  const { rows } = await pool.query(
    `INSERT INTO logs (
       user_id, prediction, confidence, servo_command,
       gesture_start_time, data_received_time, prediction_time, servo_time, latency_ms
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
    [userId, prediction, confidence, servoCommand, gestureStartTime, dataReceivedTime, predictionTime, servoTime, latencyMs],
  );
  return rows[0];
}

module.exports = { getLogs, recordLog };
