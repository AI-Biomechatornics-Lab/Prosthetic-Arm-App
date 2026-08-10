const pool = require('../db/pool');
const bridge = require('./pythonBridge.service');

const GESTURES = [
  'rest', 'fist', 'grasp', 'index', 'middle',
  'ring', 'pinky', 'thumb', 'wrist_rotate_out', 'wrist_rotate_in',
];

async function getStatus(userId) {
  const { rows } = await pool.query(
    `SELECT id, accuracy, created_at FROM calibrations
     WHERE user_id = $1 ORDER BY created_at DESC LIMIT 1`,
    [userId],
  );
  const latest = rows[0] || null;
  return {
    calibrated: Boolean(latest),
    accuracy: latest?.accuracy ?? null,
    lastCalibratedAt: latest?.created_at ?? null,
    gestures: GESTURES,
  };
}

/**
 * Runs a fine-tune pass on top of any prior calibration (the Python side owns
 * the merge logic - it never discards previous session data) and persists the
 * resulting session blob + accuracy.
 */
async function saveCalibration(userId, rawSamples) {
  const result = await bridge.request('fine_tune', { userId, samples: rawSamples }, 120000);
  const sessionData = Buffer.from(result.sessionData, 'base64');

  const { rows } = await pool.query(
    `INSERT INTO calibrations (user_id, session_data, accuracy)
     VALUES ($1, $2, $3) RETURNING id, accuracy, created_at`,
    [userId, sessionData, result.accuracy],
  );
  return rows[0];
}

module.exports = { GESTURES, getStatus, saveCalibration };
