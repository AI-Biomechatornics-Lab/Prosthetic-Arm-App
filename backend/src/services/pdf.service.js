const PDFDocument = require('pdfkit');

const COLUMN_WIDTHS = [90, 110, 90, 110, 90];
const HEADERS = ['Timestamp', 'Prediction', 'Confidence', 'Servo Command', 'Latency (ms)'];

/** Streams a PDF log report directly to the given writable (e.g. an Express response). */
function streamLogsPdf(res, { user, logs }) {
  const doc = new PDFDocument({ margin: 40, size: 'A4' });
  doc.pipe(res);

  doc.fontSize(18).text('Prosthetic Arm - Session Log Report', { align: 'left' });
  doc.moveDown(0.3);
  doc.fontSize(11).fillColor('#555')
    .text(`User: ${user.name} ${user.surname} (ID: ${user.id})`)
    .text(`Generated: ${new Date().toISOString()}`)
    .text(`Total entries: ${logs.length}`);
  doc.moveDown(1);
  doc.fillColor('#000');

  const startX = doc.x;
  let y = doc.y;

  const drawRow = (cells, isHeader = false) => {
    doc.fontSize(9).font(isHeader ? 'Helvetica-Bold' : 'Helvetica');
    let x = startX;
    cells.forEach((cell, i) => {
      doc.text(String(cell), x, y, { width: COLUMN_WIDTHS[i], ellipsis: true });
      x += COLUMN_WIDTHS[i];
    });
    y += 18;
    if (y > doc.page.height - 60) {
      doc.addPage();
      y = doc.y;
    }
  };

  drawRow(HEADERS, true);
  doc.moveTo(startX, y).lineTo(startX + COLUMN_WIDTHS.reduce((a, b) => a + b, 0), y).strokeColor('#ccc').stroke();
  y += 4;

  for (const log of logs) {
    drawRow([
      new Date(log.prediction_time).toISOString().slice(11, 23),
      `${log.prediction}`,
      `${(log.confidence * 100).toFixed(1)}%`,
      log.servo_command,
      log.latency_ms.toFixed(1),
    ]);
  }

  doc.end();
}

module.exports = { streamLogsPdf };
