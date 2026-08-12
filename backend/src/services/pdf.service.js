const PDFDocument = require('pdfkit');

const COLUMNS = [
  { key: 'gesture_start_time', label: 'Gesture Start', width: 72, time: true },
  { key: 'data_received_time', label: 'Data Received', width: 72, time: true },
  { key: 'prediction_time', label: 'Prediction', width: 72, time: true },
  { key: 'servo_time', label: 'Servo Moved', width: 72, time: true },
  { key: 'prediction', label: 'Gesture', width: 85 },
  { key: 'confidence', label: 'Confidence', width: 65 },
  { key: 'servo_command', label: 'Servo Command', width: 85 },
  { key: 'latency_ms', label: 'Total Latency (ms)', width: 85 },
];

function formatTime(value) {
  return new Date(value).toISOString().slice(11, 23);
}

/** Streams a PDF log report directly to the given writable (e.g. an Express response). */
function streamLogsPdf(res, { user, logs }) {
  const doc = new PDFDocument({ margin: 40, size: 'A4', layout: 'landscape' });
  doc.pipe(res);

  doc.fontSize(18).text('Prosthetic Arm - Session Log Report', { align: 'left' });
  doc.moveDown(0.3);
  doc.fontSize(11).fillColor('#555')
    .text(`User: ${user.name} ${user.surname} (ID: ${user.id})`)
    .text(`Generated: ${new Date().toISOString()}`)
    .text(`Total entries: ${logs.length}`);
  doc.moveDown(0.3);
  doc.fontSize(9).fillColor('#888')
    .text('Gesture Start = oldest EMG sample used for the prediction (proxy for when the gesture began). '
      + 'Total Latency = Servo Moved minus Gesture Start.');
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
      if (c.key === 'latency_ms') return log.latency_ms.toFixed(1);
      return log[c.key];
    }));
  }

  doc.end();
}

module.exports = { streamLogsPdf };
