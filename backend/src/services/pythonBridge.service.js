/**
 * Wraps emg_bridge_server.py (lives in EMG_PROJECT_DIR on the Pi) as a
 * long-lived child process. That script imports the existing, untouched
 * quick_calibration.py / hand_controller.py and exposes them over a
 * line-delimited JSON stdio protocol - see that file for the command/event
 * shapes. All spawn args + stdin/stdout framing live here so the rest of the
 * app only deals with plain JS events, not process plumbing.
 */
const { spawn } = require('child_process');
const readline = require('readline');
const { EventEmitter } = require('events');
const env = require('../config/env');

class PythonBridge extends EventEmitter {
  constructor() {
    super();
    this.proc = null;
    this.ready = false;
  }

  start() {
    if (this.proc) return;

    this.proc = spawn(env.emg.pythonBin, ['emg_bridge_server.py'], {
      cwd: env.emg.projectDir,
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    readline.createInterface({ input: this.proc.stdout }).on('line', (line) => {
      this._handleLine(line);
    });

    this.proc.stderr.on('data', (chunk) => {
      console.error('[python]', chunk.toString().trim());
    });

    this.proc.on('exit', (code) => {
      console.warn(`Python process exited with code ${code}`);
      this.ready = false;
      this.proc = null;
      this.emit('exit', code);
    });

    this.ready = true;
  }

  _handleLine(line) {
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      return; // ignore non-JSON stdout noise from the script
    }
    if (!msg || typeof msg !== 'object' || !msg.type) return;
    this.emit(msg.type, msg.payload ?? {});
  }

  send(command, payload = {}) {
    if (!this.proc) throw new Error('Python bridge is not running');
    this.proc.stdin.write(JSON.stringify({ command, payload }) + '\n');
  }

  /** Sends a command and resolves with the first matching `${command}_result` event. */
  request(command, payload = {}, timeoutMs = 10000) {
    return new Promise((resolve, reject) => {
      const resultEvent = `${command}_result`;
      const timer = setTimeout(() => {
        this.off(resultEvent, onResult);
        reject(new Error(`Timed out waiting for "${resultEvent}"`));
      }, timeoutMs);

      const onResult = (result) => {
        clearTimeout(timer);
        resolve(result);
      };

      this.once(resultEvent, onResult);
      try {
        this.send(command, payload);
      } catch (err) {
        clearTimeout(timer);
        this.off(resultEvent, onResult);
        reject(err);
      }
    });
  }

  stop() {
    if (this.proc) {
      this.proc.kill();
      this.proc = null;
      this.ready = false;
    }
  }
}

module.exports = new PythonBridge();
