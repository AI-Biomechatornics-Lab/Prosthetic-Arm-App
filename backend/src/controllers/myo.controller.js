const myoService = require('../services/myo.service');

async function connect(req, res, next) {
  try {
    res.json(await myoService.connect());
  } catch (err) {
    next(err);
  }
}

async function disconnect(req, res, next) {
  try {
    res.json(await myoService.disconnect());
  } catch (err) {
    next(err);
  }
}

async function battery(req, res, next) {
  try {
    res.json(await myoService.battery());
  } catch (err) {
    next(err);
  }
}

async function powerOff(req, res, next) {
  try {
    res.json(await myoService.powerOff());
  } catch (err) {
    next(err);
  }
}

module.exports = { connect, disconnect, battery, powerOff };
