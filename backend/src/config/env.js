require('dotenv').config();

function list(value, fallback) {
  return (value ?? fallback).split(',').map((s) => s.trim()).filter(Boolean);
}

module.exports = {
  port: Number(process.env.PORT) || 3000,
  nodeEnv: process.env.NODE_ENV || 'development',

  db: {
    host: process.env.PGHOST || 'localhost',
    port: Number(process.env.PGPORT) || 5432,
    database: process.env.PGDATABASE || 'prosthetic_arm',
    user: process.env.PGUSER || 'postgres',
    password: process.env.PGPASSWORD || '',
  },

  emg: {
    projectDir: process.env.EMG_PROJECT_DIR || '/home/biomekatronik/Desktop/EMG_Hand_Control',
    pythonBin: process.env.EMG_PYTHON_BIN || '/home/biomekatronik/Desktop/EMG_Hand_Control/myo_env/bin/python',
  },

  corsOrigins: list(process.env.CORS_ORIGINS, 'http://localhost:5000'),
};
