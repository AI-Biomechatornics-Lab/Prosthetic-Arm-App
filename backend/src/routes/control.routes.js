const express = require('express');
const controller = require('../controllers/control.controller');

const router = express.Router();

router.post('/start', controller.start);
router.post('/stop', controller.stop);

module.exports = router;
