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
  -- (servo command issued). latency_ms spans gesture_start -> servo_time.
  gesture_start_time TIMESTAMPTZ NOT NULL,
  data_received_time TIMESTAMPTZ NOT NULL,
  prediction_time TIMESTAMPTZ NOT NULL,
  servo_time TIMESTAMPTZ NOT NULL,
  latency_ms REAL NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_calibrations_user_id ON calibrations(user_id);
CREATE INDEX IF NOT EXISTS idx_logs_user_id ON logs(user_id);
CREATE INDEX IF NOT EXISTS idx_logs_created_at ON logs(created_at);
