const calibrationService = require('../services/calibration.service');

async function getStatus(req, res, next) {
  try {
    const status = await calibrationService.getStatus(req.params.userId);
    res.json(status);
  } catch (err) {
    next(err);
  }
}

async function save(req, res, next) {
  try {
    const { samples } = req.body;
    if (!Array.isArray(samples) || samples.length === 0) {
      return res.status(400).json({ error: 'samples array is required' });
    }
    const calibration = await calibrationService.saveCalibration(req.params.userId, samples);
    res.status(201).json({ calibration });
  } catch (err) {
    next(err);
  }
}

module.exports = { getStatus, save };
