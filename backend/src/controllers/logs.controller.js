const logsService = require('../services/logs.service');
const usersService = require('../services/users.service');
const pdfService = require('../services/pdf.service');

async function getLogs(req, res, next) {
  try {
    const logs = await logsService.getLogs(req.params.userId);
    res.json({ logs });
  } catch (err) {
    next(err);
  }
}

async function getLatestSession(req, res, next) {
  try {
    const logs = await logsService.getLatestSessionLogs(req.params.userId);
    res.json({ logs });
  } catch (err) {
    next(err);
  }
}

async function exportPdf(req, res, next) {
  try {
    const [user, logs] = await Promise.all([
      usersService.findById(req.params.userId),
      logsService.getLatestSessionLogs(req.params.userId),
    ]);
    if (!user) return res.status(404).json({ error: 'User not found' });

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="session-log-${user.id}.pdf"`);
    pdfService.streamLogsPdf(res, { user, logs });
  } catch (err) {
    next(err);
  }
}

module.exports = { getLogs, getLatestSession, exportPdf };
