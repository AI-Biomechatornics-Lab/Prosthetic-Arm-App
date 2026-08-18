const PDFDocument = require('pdfkit');

const COLUMNS = [
  { key: 'gesture_start_time', label: 'Gesture Start', width: 62, time: true },
  { key: 'data_received_time', label: 'Data Received', width: 62, time: true },
  { key: 'prediction_time', label: 'Prediction', width: 62, time: true },
  { key: 'servo_time', label: 'Servo Dispatched', width: 62, time: true },
  { key: 'servo_moved_time', label: 'Servo Moved', width: 62, time: true },
  { key: 'prediction', label: 'Gesture', width: 75 },
  { key: 'confidence', label: 'Confidence', width: 58 },
  { key: 'servo_command', label: 'Servo Command', width: 75 },
  { key: 'latency_ms', label: 'Decision Latency (ms)', width: 68 },
  { key: 'physical_latency_ms', label: 'Physical Latency (ms)', width: 68 },
];

// The DB/API deal in UTC (correct for storage/transport), but a report is
// for a human to read, so render in the Pi's local wall-clock time instead
// of raw UTC - Date's local getters use the system timezone (set to the
// same one the Pi/user are physically in), unlike toISOString() which is
// always UTC regardless of system settings.
function pad(n, len = 2) {
  return String(n).padStart(len, '0');
}

function formatTime(value) {
  const d = new Date(value);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}.${pad(d.getMilliseconds(), 3)}`;
}

function formatDateTime(value) {
  const d = new Date(value);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${formatTime(d)}`;
}

/** Streams a PDF log report directly to the given writable (e.g. an Express response). */
function streamLogsPdf(res, { user, logs }) {
  const doc = new PDFDocument({ margin: 40, size: 'A4', layout: 'landscape' });
  doc.pipe(res);

  doc.fontSize(18).text('Prosthetic Arm - Session Log Report', { align: 'left' });
  doc.moveDown(0.3);
  doc.fontSize(11).fillColor('#555')
    .text(`User: ${user.name} ${user.surname} (ID: ${user.id})`)
    .text(`Generated: ${formatDateTime(new Date())}`)
    .text(`Scope: latest session only${logs.length ? ` (started ${formatDateTime(logs[0].session_started_at)})` : ''}`)
    .text(`Total entries: ${logs.length}`);
  doc.moveDown(0.3);
  doc.fontSize(9).fillColor('#888')
    .text('Gesture Start = oldest EMG sample used for the prediction (proxy for when the gesture began). '
      + 'Decision Latency = Servo Dispatched minus Gesture Start (AI responsiveness, target <300ms). '
      + 'Physical Latency = Servo Moved minus Servo Dispatched (mechanical movement time, expected 800-1500ms).');
  doc.moveDown(0.7);
  doc.fillColor('#000');

  const startX = doc.x;
  let y = doc.y;
  const totalWidth = COLUMNS.reduce((sum, c) => sum + c.width, 0);

  const drawRow = (cells, isHeader = false) => {
    doc.fontSize(8).font(isHeader ? 'Helvetica-Bold' : 'Helvetica');
    let x = startX;
    cells.forEach((cell, i) => {
      doc.text(String(cell), x, y, { width: COLUMNS[i].width, ellipsis: true });
      x += COLUMNS[i].width;
    });
    y += 16;
    if (y > doc.page.height - 60) {
      doc.addPage();
      y = doc.y;
    }
  };

  drawRow(COLUMNS.map((c) => c.label), true);
  doc.moveTo(startX, y).lineTo(startX + totalWidth, y).strokeColor('#ccc').stroke();
  y += 4;

  for (const log of logs) {
    drawRow(COLUMNS.map((c) => {
      if (c.time) return formatTime(log[c.key]);
      if (c.key === 'confidence') return `${(log.confidence * 100).toFixed(1)}%`;
      if (c.key === 'latency_ms' || c.key === 'physical_latency_ms') return log[c.key].toFixed(1);
      return log[c.key];
    }));
  }

  doc.end();
}

module.exports = { streamLogsPdf };
