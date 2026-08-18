const express = require('express');
const controller = require('../controllers/logs.controller');

const router = express.Router();

router.get('/:userId/latest-session', controller.getLatestSession);
router.get('/:userId', controller.getLogs);
router.post('/:userId/export', controller.exportPdf);

module.exports = router;
