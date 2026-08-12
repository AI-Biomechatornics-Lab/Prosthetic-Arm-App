const controlService = require('../services/control.service');

async function start(req, res, next) {
  try {
    const { userId } = req.body;
    if (!userId) return res.status(400).json({ error: 'userId is required' });
    res.json(await controlService.start(userId));
  } catch (err) {
    next(err);
  }
}

async function stop(req, res, next) {
  try {
    res.json(await controlService.stop());
  } catch (err) {
    next(err);
  }
}

module.exports = { start, stop };
