const express = require('express');
const controller = require('../controllers/myo.controller');

const router = express.Router();

router.get('/connect', controller.connect);
router.get('/disconnect', controller.disconnect);
router.get('/battery', controller.battery);
router.post('/poweroff', controller.powerOff);

module.exports = router;
