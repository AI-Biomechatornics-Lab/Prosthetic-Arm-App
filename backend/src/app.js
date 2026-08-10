const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const env = require('./config/env');
const errorHandler = require('./middleware/errorHandler');

const authRoutes = require('./routes/auth.routes');
const myoRoutes = require('./routes/myo.routes');
const calibrationRoutes = require('./routes/calibration.routes');
const logsRoutes = require('./routes/logs.routes');

const app = express();

app.use(cors({ origin: env.corsOrigins }));
app.use(express.json());
app.use(morgan(env.nodeEnv === 'production' ? 'tiny' : 'dev'));

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.use('/auth', authRoutes);
app.use('/myo', myoRoutes);
app.use('/calibration', calibrationRoutes);
app.use('/logs', logsRoutes);

app.use(errorHandler);

module.exports = app;
