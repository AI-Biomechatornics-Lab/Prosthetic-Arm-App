/**
 * Tracks when each user's most recent control session (a /control/start
 * call) began, purely in memory. Read by the latency logger so every log
 * row it writes can be tagged with which session it belongs to, letting
 * "latest session" queries scope to just what happened since the last
 * Start press instead of the user's entire history.
 */
const sessionStartedAtByUser = new Map();

function startSession(userId) {
  const startedAt = new Date();
  sessionStartedAtByUser.set(String(userId), startedAt);
  return startedAt;
}

function getCurrentSessionStart(userId) {
  return sessionStartedAtByUser.get(String(userId)) ?? null;
}

module.exports = { startSession, getCurrentSessionStart };
