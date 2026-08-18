-- Prosthetic Arm App schema
-- Run with: psql -d prosthetic_arm -f src/db/schema.sql

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  surname VARCHAR(100) NOT NULL,
  gender CHAR(1) NOT NULL CHECK (gender IN ('M', 'F')),
  birthdate DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS calibrations (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_data BYTEA NOT NULL,
  accuracy REAL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS logs (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  prediction VARCHAR(50) NOT NULL,
  confidence REAL NOT NULL,
  servo_command VARCHAR(50) NOT NULL,
  -- Full pipeline breakdown: gesture_start (oldest sample in the window used
  -- for this prediction - the closest proxy we have to "when the user moved
  -- their hand"), data_received (newest sample in that window, i.e. just
  -- before inference ran), prediction_time (inference done), servo_time
  -- (servo command dispatched - non-blocking, doesn't wait on physical
  -- movement), servo_moved_time (physical movement actually finished).
  -- latency_ms ("decision latency") spans gesture_start -> servo_time and is
  -- the number that matters for responsiveness; physical_latency_ms
  -- (servo_time -> servo_moved_time) is mechanical and expected to be slow.
  gesture_start_time TIMESTAMPTZ NOT NULL,
  data_received_time TIMESTAMPTZ NOT NULL,
  prediction_time TIMESTAMPTZ NOT NULL,
  servo_time TIMESTAMPTZ NOT NULL,
  servo_moved_time TIMESTAMPTZ NOT NULL,
  latency_ms REAL NOT NULL,
  physical_latency_ms REAL NOT NULL,
  -- When the control session (the /control/start call) that produced this
  -- log entry began. Lets "latest session" queries scope to just what
  -- happened since the last Start press, not the user's entire history.
  session_started_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_calibrations_user_id ON calibrations(user_id);
CREATE INDEX IF NOT EXISTS idx_logs_user_id ON logs(user_id);
CREATE INDEX IF NOT EXISTS idx_logs_created_at ON logs(created_at);
CREATE INDEX IF NOT EXISTS idx_logs_session ON logs(user_id, session_started_at);
