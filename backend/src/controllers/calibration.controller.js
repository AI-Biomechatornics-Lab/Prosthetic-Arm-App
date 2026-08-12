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

async function getHistory(req, res, next) {
  try {
    const history = await calibrationService.getHistory(req.params.userId);
    res.json({ history });
  } catch (err) {
    next(err);
  }
}

async function deleteCalibration(req, res, next) {
  try {
    await calibrationService.deleteCalibration(req.params.userId, req.params.calibrationId);
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
}

module.exports = { getStatus, save, getHistory, deleteCalibration };
