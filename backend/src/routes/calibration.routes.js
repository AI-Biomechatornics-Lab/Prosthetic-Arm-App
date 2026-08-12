const express = require('express');
const controller = require('../controllers/calibration.controller');

const router = express.Router();

router.get('/:userId/history', controller.getHistory);
router.delete('/:userId/:calibrationId', controller.deleteCalibration);
router.get('/:userId', controller.getStatus);
router.post('/:userId', controller.save);

module.exports = router;
