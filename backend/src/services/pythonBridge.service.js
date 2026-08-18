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
    // command name -> in-flight Promise. Without this, clicking (e.g.)
    // Connect twice before the first scan finishes fires a second command
    // with the same result-event name; the `once()` listener below can then
    // resolve whichever call's promise the NEXT matching event happens to
    // satisfy, not necessarily its own - one request can silently get
    // another request's answer. Coalescing duplicate concurrent requests
    // for the same command into a single shared promise removes that race
    // entirely, and also stops us firing overlapping BLE scans that BlueZ
    // itself rejects outright.
    this._inFlight = new Map();
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
    const existing = this._inFlight.get(command);
    if (existing) return existing;

    const promise = new Promise((resolve, reject) => {
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

    const tracked = promise.finally(() => this._inFlight.delete(command));
    this._inFlight.set(command, tracked);
    return tracked;
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
