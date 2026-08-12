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
  bridge.start();
  const result = await bridge.request('fine_tune', { userId, samples: rawSamples }, 300000);
  const sessionData = Buffer.from(result.sessionData, 'base64');

  const { rows } = await pool.query(
    `INSERT INTO calibrations (user_id, session_data, accuracy)
     VALUES ($1, $2, $3) RETURNING id, accuracy, created_at`,
    [userId, sessionData, result.accuracy],
  );
  return rows[0];
}

async function getHistory(userId) {
  const { rows } = await pool.query(
    `SELECT id, accuracy, created_at FROM calibrations
     WHERE user_id = $1 ORDER BY created_at DESC`,
    [userId],
  );
  return rows;
}

/**
 * Deletes one calibration session and reconciles the Pi's active model
 * checkpoint to whatever the most recent *remaining* session is.
 *
 * Important nuance: fine-tuning is continual - each session trains on top of
 * whatever the checkpoint already was. Deleting the latest session genuinely
 * rolls the live model back to the previous one (undoes a bad session).
 * Deleting an older session only removes it from history - later sessions
 * were already trained on top of its effect, and that can't be un-baked
 * without the original raw samples, which aren't kept (only final weights
 * are stored, since raw calibration sessions are several MB each).
 */
async function deleteCalibration(userId, calibrationId) {
  await pool.query(`DELETE FROM calibrations WHERE id = $1 AND user_id = $2`, [calibrationId, userId]);

  const { rows } = await pool.query(
    `SELECT session_data FROM calibrations WHERE user_id = $1 ORDER BY created_at DESC LIMIT 1`,
    [userId],
  );

  bridge.start();
  await bridge.request(
    'revert_calibration',
    { userId, sessionData: rows[0] ? rows[0].session_data.toString('base64') : null },
    15000,
  );
}

module.exports = { GESTURES, getStatus, saveCalibration, getHistory, deleteCalibration };
