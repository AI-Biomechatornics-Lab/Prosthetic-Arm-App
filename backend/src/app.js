const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const env = require('./config/env');
const errorHandler = require('./middleware/errorHandler');

const authRoutes = require('./routes/auth.routes');
const myoRoutes = require('./routes/myo.routes');
const calibrationRoutes = require('./routes/calibration.routes');
const logsRoutes = require('./routes/logs.routes');
const controlRoutes = require('./routes/control.routes');

const app = express();

app.use(cors({ origin: env.corsOrigins }));
// A full calibration session posts ~30k raw EMG samples (10 gestures x 3
// reps x 5s at ~200Hz) in one request - comfortably a few MB, well past
// Express's 100kb default.
app.use(express.json({ limit: '20mb' }));
app.use(morgan(env.nodeEnv === 'production' ? 'tiny' : 'dev'));

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.use('/auth', authRoutes);
app.use('/myo', myoRoutes);
app.use('/calibration', calibrationRoutes);
app.use('/logs', logsRoutes);
app.use('/control', controlRoutes);

app.use(errorHandler);

module.exports = app;
