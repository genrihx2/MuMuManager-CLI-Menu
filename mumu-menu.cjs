#!/usr/bin/env node
/**
 * MuMuManager CLI Menu - JavaScript entry point.
 *
 * Two engines, one repo:
 *   node mumu-menu.cjs        native JS menu (this file)
 *   .\mumu-menu.ps1           the full PowerShell menu (unchanged)
 *
 * The JS side implements the core, most-used operations natively (status,
 * instance control, network/updater watcher) and delegates anything else to
 * mumu-menu.ps1, which stays fully supported and is still the reference
 * implementation. No npm install is needed: this file has zero dependencies,
 * resolves its own folder, and works from any working directory - including a
 * deployed install where package.json does not exist.
 *
 * Usage:
 *   node mumu-menu.cjs                 interactive JS menu (TTY)
 *   node mumu-menu.cjs --status        instance table (read-only)
 *   node mumu-menu.cjs --status --json machine-readable status
 *   node mumu-menu.cjs --start 0       start instance 0
 *   node mumu-menu.cjs --stop 0        stop instance 0
 *   node mumu-menu.cjs --restart 0     restart instance 0
 *   node mumu-menu.cjs --watch         network + updater watcher (read-only)
 *   node mumu-menu.cjs --ps            full PowerShell menu
 *   node mumu-menu.cjs --help          this text
 *
 * Nothing here writes MuMu configuration: every action goes through
 * MuMuManager.exe, exactly like the PowerShell menu.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');
const { spawn, spawnSync } = require('child_process');

const SCRIPT_DIR = __dirname;
const MENU_PS1 = path.join(SCRIPT_DIR, 'mumu-menu.ps1');
const VERSION_FILE = path.join(SCRIPT_DIR, '.version');
const PIN_FILE = path.join(SCRIPT_DIR, '.mumu-install');
const VERSION = readVersion();

// --- small helpers ---------------------------------------------------------

function readVersion() {
  try {
    const v = fs.readFileSync(VERSION_FILE, 'utf8').replace(/^\uFEFF/, '').trim();
    return v.replace(/^v/i, '') || 'unknown';
  } catch {
    return 'unknown';
  }
}

function out(line) {
  process.stdout.write((line === undefined ? '' : line) + '\n');
}

function die(msg, code) {
  process.stderr.write('mumu-menu: ' + msg + '\n');
  process.exit(code === undefined ? 1 : code);
}

function isTTY() {
  return Boolean(process.stdin.isTTY && process.stdout.isTTY);
}

// --- MuMuManager.exe discovery --------------------------------------------

function fromPin() {
  try {
    const raw = fs.readFileSync(PIN_FILE, 'utf8').replace(/^\uFEFF/, '').trim();
    const first = raw.split(/\r?\n/).map((s) => s.trim()).filter(Boolean)[0];
    if (!first) return null;
    if (fs.existsSync(first) && path.basename(first).toLowerCase() === 'mumumanager.exe') return first;
    const direct = path.join(first, 'MuMuManager.exe');
    if (fs.existsSync(direct)) return direct;
    const nx = path.join(first, 'nx_main', 'MuMuManager.exe');
    if (fs.existsSync(nx)) return nx;
  } catch {
    /* no pin: normal */
  }
  return null;
}

function candidateManagers() {
  const found = [];
  const add = (p) => {
    if (p && !found.includes(p) && fs.existsSync(p)) found.push(p);
  };
  add(fromPin());

  const bases = [
    process.env.ProgramFiles,
    process.env['ProgramFiles(x86)'],
    process.env.LOCALAPPDATA,
  ].filter(Boolean);
  const suffixes = [
    'MuMuManager.exe',
    path.join('nx_main', 'MuMuManager.exe'),
    path.join('shell', 'MuMuManager.exe'),
  ];

  for (const base of bases) {
    let vendors = [];
    try {
      vendors = fs.readdirSync(base).filter((n) => /^netease/i.test(n));
    } catch {
      continue;
    }
    for (const vendor of vendors) {
      const root = path.join(base, vendor);
      for (const suffix of suffixes) add(path.join(root, suffix));
      let products = [];
      try {
        products = fs.readdirSync(root).filter((n) => /^mumu/i.test(n));
      } catch {
        continue;
      }
      for (const product of products) {
        for (const suffix of suffixes) add(path.join(root, product, suffix));
      }
    }
  }
  return found;
}

function findManager() {
  const all = candidateManagers();
  return all.length ? all[0] : null;
}

function runManager(manager, args, { json = false } = {}) {
  const res = spawnSync(manager, args, {
    encoding: 'utf8',
    windowsHide: true,
    maxBuffer: 32 * 1024 * 1024,
  });
  if (res.error) throw res.error;
  const text = (res.stdout || '') + (res.stderr || '');
  if (!json) return text;
  const start = text.indexOf('{');
  if (start < 0) throw new Error('MuMuManager returned no JSON for: ' + args.join(' '));
  return JSON.parse(text.slice(start));
}

function requireManager() {
  const manager = findManager();
  if (!manager) {
    die(
      'MuMuManager.exe not found. Install MuMu Emulator, or pin the active install ' +
        'through the PowerShell menu ([IN]) so ' + PIN_FILE + ' exists.'
    );
  }
  return manager;
}

function listInstances(manager) {
  const info = runManager(manager, ['info', '-v', 'all'], { json: true });
  return Object.keys(info)
    .filter((k) => info[k] && typeof info[k] === 'object')
    .map((k) => info[k])
    .sort((a, b) => Number(a.index) - Number(b.index));
}

function instanceState(inst) {
  if (inst.is_android_started) return 'running (android)';
  if (inst.is_process_started) return 'starting / process only';
  return 'stopped';
}

function gb(bytes) {
  const n = Number(bytes);
  if (!Number.isFinite(n) || n <= 0) return '-';
  return (n / 1024 / 1024 / 1024).toFixed(1) + ' GB';
}

// --- commands -------------------------------------------------------------

function showStatus({ json = false } = {}) {
  const manager = requireManager();
  const instances = listInstances(manager);

  if (json) {
    out(
      JSON.stringify(
        {
          engine: 'javascript',
          menuVersion: VERSION,
          manager,
          instances: instances.map((i) => ({
            index: Number(i.index),
            name: i.name,
            state: instanceState(i),
            androidVersion: i.android_version,
            isAndroidStarted: Boolean(i.is_android_started),
            isProcessStarted: Boolean(i.is_process_started),
            diskBytes: Number(i.disk_size_bytes) || 0,
          })),
        },
        null,
        2
      )
    );
    return;
  }

  out('');
  out('MuMuManager CLI Menu ' + VERSION + ' (JavaScript)');
  out('  Manager : ' + manager);
  out('  Engine  : node ' + process.version);
  out('');

  if (!instances.length) {
    out('  No instances found.');
    out('');
    return;
  }

  const rows = instances.map((i) => [
    String(i.index),
    String(i.name || ''),
    instanceState(i),
    String(i.android_version || '-'),
    gb(i.disk_size_bytes),
  ]);
  const head = ['#', 'Name', 'State', 'Android', 'Disk'];
  const widths = head.map((h, c) => Math.max(h.length, ...rows.map((r) => r[c].length)));
  const fmt = (cells) => '  ' + cells.map((cell, c) => cell.padEnd(widths[c])).join('  ');
  out(fmt(head));
  out('  ' + widths.map((w) => '-'.repeat(w)).join('  '));
  rows.forEach((r) => out(fmt(r)));
  out('');
}

function controlInstance(action, index) {
  const manager = requireManager();
  const i = String(index).trim();
  if (!/^\d+$/.test(i)) die('instance index must be a number, got: ' + index);
  out('MuMuManager control -v ' + i + ' ' + action + ' ...');
  const text = runManager(manager, ['control', '-v', i, action]);
  const trimmed = text.trim();
  if (trimmed) out(trimmed);
  out('Done: ' + action + ' instance ' + i);
}

function resolveWatchLog(explicit) {
  if (explicit) return path.resolve(explicit);
  if (process.env.MUMU_WATCH_LOG) return path.resolve(process.env.MUMU_WATCH_LOG);
  const legacy = 'C:\\test\\mumu-network-update.txt';
  if (process.platform === 'win32' && fs.existsSync('C:\\test')) return legacy;
  return path.join(os.tmpdir(), 'mumu-network-update.txt');
}

// netstat parsing (same contract as the PowerShell watcher: PID column last,
// numeric only, so it does not depend on the OS display language).
function splitHostPort(endpoint) {
  const m = /^\[(.*)\]:(\d+)$/.exec(endpoint);
  if (m) return { host: m[1], port: Number(m[2]) };
  const idx = endpoint.lastIndexOf(':');
  if (idx < 1) return { host: endpoint, port: 0 };
  return { host: endpoint.slice(0, idx), port: Number(endpoint.slice(idx + 1)) || 0 };
}

function mumuProcesses() {
  const res = spawnSync('tasklist', ['/FO', 'CSV', '/NH'], {
    encoding: 'utf8',
    windowsHide: true,
    maxBuffer: 16 * 1024 * 1024,
  });
  const map = new Map();
  for (const line of String(res.stdout || '').split(/\r?\n/)) {
    const m = /^"([^"]+)","(\d+)"/.exec(line);
    if (!m) continue;
    const name = m[1];
    if (!/^mumu/i.test(name)) continue;
    map.set(Number(m[2]), name);
  }
  return map;
}

function tcpRows(pids) {
  if (process.platform !== 'win32' || !pids.size) return [];
  const res = spawnSync('netstat', ['-ano', '-p', 'tcp'], {
    encoding: 'utf8',
    windowsHide: true,
    maxBuffer: 64 * 1024 * 1024,
  });
  const rows = [];
  for (const line of String(res.stdout || '').split(/\r?\n/)) {
    const m = /^\s*TCP\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+)\s*$/.exec(line);
    if (!m) continue;
    const pid = Number(m[4]);
    if (!pids.has(pid)) continue;
    const state = m[3];
    if (state === 'LISTENING' || state === 'TIME_WAIT' || state === 'BOUND' || state === 'CLOSED') continue;
    const local = splitHostPort(m[1]);
    const remote = splitHostPort(m[2]);
    // DevSkim: ignore DS162092 - loopback literals are the EXCLUSION filter (localhost rows are skipped, none are contacted)
    if (['127.0.0.1', '::1', '0.0.0.0', '::'].includes(remote.host)) continue;
    rows.push({
      pid,
      name: pids.get(pid),
      state,
      localAddress: local.host,
      localPort: local.port,
      remoteAddress: remote.host,
      remotePort: remote.port,
    });
  }
  return rows;
}

function stamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return (
    d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' +
    p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds())
  );
}

function pushLine(lines, text) {
  lines.push(text);
}

function watcherTick(state, seed) {
  const started = Date.now();
  const procs = mumuProcesses();
  const rows = tcpRows(procs);
  const tag = seed ? 'SEEN' : 'NEW';

  for (const row of rows) {
    const key = 'tcp|' + row.pid + '|' + row.localPort + '|' + row.remoteAddress + '|' + row.remotePort;
    if (state.seen.has(key)) continue;
    state.seen.add(key);
    pushLine(state.lines, stamp() + ' | ' + tag + ' | ' + row.name + ' | PID=' + row.pid +
      ' | ' + (row.remotePort === 443 ? 'TCP/443' : 'TCP') + ' | ' + row.remoteAddress + ':' + row.remotePort);
    pushLine(state.lines, stamp() + ' |      | state=' + row.state +
      ' local=' + row.localAddress + ':' + row.localPort);
  }

  const updaters = [...procs.entries()].filter(([, name]) => name.toLowerCase() === 'mumunxupdater');
  for (const [pid, name] of updaters) {
    const launchKey = 'updater-launch|' + pid;
    if (!state.seen.has(launchKey)) {
      state.seen.add(launchKey);
      pushLine(state.lines, stamp() + ' | UPDATER LAUNCH | ' + name + ' | PID=' + pid);
    }
    const ips = rows.filter((r) => r.pid === pid);
    for (const row of ips) {
      const key = 'updater-ip|' + pid + '|' + row.localPort + '|' + row.remoteAddress + '|' + row.remotePort;
      if (state.seen.has(key)) continue;
      state.seen.add(key);
      pushLine(state.lines, stamp() + ' | UPDATER IP | PID=' + pid + ' | ' + row.state +
        ' | ' + row.remoteAddress + ':' + row.remotePort);
    }
  }

  return { processes: procs.size, updaters: updaters.length, rows: rows.length, ms: Date.now() - started };
}

function startWatcher({ logPath, intervalMs = 5000 } = {}) {
  const target = resolveWatchLog(logPath);
  try {
    fs.mkdirSync(path.dirname(target), { recursive: true });
  } catch (err) {
    die('cannot create log directory for ' + target + ': ' + err.message);
  }

  const header = '===== MuMu Network + Updater Watcher (menu [WN], JavaScript) =====';
  const fresh = !fs.existsSync(target);
  const head = fresh
    ? header + os.EOL + 'Started: ' + stamp() + os.EOL
    : header + os.EOL + 'Session started: ' + stamp() + os.EOL;
  fs.appendFileSync(target, head, 'utf8');
  fs.appendFileSync(
    target,
    'Menu v' + VERSION + ' (node ' + process.version + ') | ' + os.hostname() +
      ' | cadence ' + Math.round(intervalMs / 1000) + ' s | TCP source: netstat -ano -p tcp' + os.EOL,
    'utf8'
  );

  out('');
  out('MuMu network + updater watcher (READ-ONLY, JavaScript)');
  out('  Processes watched : MuMu* (tasklist)');
  out('  TCP scope         : external connections, LISTENING/TIME_WAIT skipped, dedup 5-tuple');
  out('  Log file          : ' + target);
  out('  Cadence           : ' + Math.round(intervalMs / 1000) + ' s + heartbeat every 60 s. Ctrl+C stops.');
  out('');

  const state = { seen: new Set(), lines: [] };
  let ticks = 0;
  let timer = null;
  let stopping = false;

  const stop = (reason) => {
    if (stopping) return;
    stopping = true;
    if (timer) clearInterval(timer);
    const line = 'Stopped: ' + stamp() + ' (ticks=' + ticks + ', tracked 5-tuples=' + state.seen.size + ')' +
      (reason ? ' reason=' + reason : '');
    fs.appendFileSync(target, line + os.EOL, 'utf8');
    out('');
    out('Watcher stopped. Log: ' + target);
    process.exit(0);
  };

  const tick = () => {
    const seed = ticks === 0;
    let stats = null;
    try {
      stats = watcherTick(state, seed);
    } catch (err) {
      pushLine(state.lines, stamp() + ' | ERROR | ' + err.message);
    }
    if (stats && (seed || ticks % 12 === 0)) {
      pushLine(state.lines, stamp() + ' | HEARTBEAT | MuMu processes=' + stats.processes +
        ' | updaters=' + stats.updaters + ' | external rows=' + stats.rows + ' | tick=' + stats.ms + ' ms');
    }
    if (seed) {
      pushLine(state.lines, '  (SEEN = connection already open when the session started; NEW = opened while watching)');
    }
    if (state.lines.length) {
      fs.appendFileSync(target, state.lines.join(os.EOL) + os.EOL, 'utf8');
      state.lines.forEach((l) => out(l));
      state.lines.length = 0;
    }
    ticks += 1;
  };

  tick();
  timer = setInterval(tick, intervalMs);
  process.on('SIGINT', () => stop('ctrl+c'));
  process.on('SIGTERM', () => stop('sigterm'));
  if (!isTTY()) out('(non-interactive terminal: run in the foreground, Ctrl+C stops)');
}

// --- PowerShell delegation ------------------------------------------------

function powershellExe() {
  const root = process.env.SystemRoot || 'C:\\Windows';
  const candidates = [
    path.join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
    'pwsh.exe',
  ];
  for (const candidate of candidates) {
    if (candidate.includes(path.sep) && fs.existsSync(candidate)) return candidate;
  }
  return 'powershell.exe';
}

function runPowerShellMenu() {
  if (!fs.existsSync(MENU_PS1)) {
    die(
      'mumu-menu.ps1 not found next to this JS entry (' + MENU_PS1 + ').\n' +
        'Download the release ZIP, or run: curl.exe -L -o mumu-menu.ps1 ' +
        'https://raw.githubusercontent.com/genrihx2/MuMuManager-CLI-Menu/main/mumu-menu.ps1'
    );
  }
  if (!isTTY()) {
    out('The full PowerShell menu is interactive and needs a TTY.');
    out('Run: powershell -NoProfile -ExecutionPolicy Bypass -File "' + MENU_PS1 + '"');
    return;
  }
  const exe = powershellExe();
  out('Starting the full PowerShell menu: ' + exe + ' -File "' + MENU_PS1 + '"');
  const child = spawn(exe, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', MENU_PS1], {
    stdio: 'inherit',
  });
  child.on('error', (err) => die('cannot start PowerShell: ' + err.message));
  child.on('close', (code) => process.exit(code || 0));
}

// --- interactive JS menu --------------------------------------------------

function ask(rl, prompt) {
  return new Promise((resolve) => rl.question(prompt, (answer) => resolve(String(answer).trim())));
}

async function interactive() {
  const manager = findManager();
  if (!manager) {
    out('MuMuManager.exe was not found. The JS menu needs an installed MuMu Emulator.');
    out('The full PowerShell menu can still locate/pin it: --ps');
    return;
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  try {
    for (;;) {
      out('');
      out('======================================');
      out('  MuMuManager CLI Menu ' + VERSION + ' (JavaScript)');
      out('  Manager: ' + manager);
      out('======================================');
      out('  [1] Status / instance list');
      out('  [2] Start instance');
      out('  [3] Stop instance');
      out('  [4] Restart instance');
      out('  [5] Watch MuMu network + updater');
      out('  [PS] Full PowerShell menu (all features)');
      out('  [0] Exit');
      out('');
      const choice = (await ask(rl, 'Select: ')).toLowerCase();
      if (choice === '0' || choice === 'q' || choice === 'exit') break;
      if (choice === '1') {
        try { showStatus({ json: false }); } catch (err) { out('Error: ' + err.message); }
        continue;
      }
      if (choice === 'ps') {
        rl.close();
        runPowerShellMenu();
        return;
      }
      if (['2', '3', '4', '5'].includes(choice)) {
        if (choice === '5') {
          rl.close();
          startWatcher({});
          return;
        }
        const index = await ask(rl, 'Instance index: ');
        const action = choice === '2' ? 'launch' : choice === '3' ? 'shutdown' : 'restart';
        try {
          controlInstance(action, index);
        } catch (err) {
          out('Error: ' + err.message);
        }
        continue;
      }
      out('Unknown option: ' + choice);
    }
  } finally {
    rl.close();
  }
}

// --- flag parsing ---------------------------------------------------------

function helpText() {
  return [
    'MuMuManager CLI Menu ' + VERSION + ' - JavaScript entry point',
    '',
    'Usage:',
    '  node mumu-menu.cjs                 interactive JS menu',
    '  node mumu-menu.cjs --status        instance table (read-only)',
    '  node mumu-menu.cjs --status --json machine-readable status',
    '  node mumu-menu.cjs --list          instance indexes, one per line',
    '  node mumu-menu.cjs --start <i>     start instance <i>',
    '  node mumu-menu.cjs --stop <i>      stop instance <i>',
    '  node mumu-menu.cjs --restart <i>   restart instance <i>',
    '  node mumu-menu.cjs --watch         network + updater watcher (read-only)',
    '      --interval <sec>               watcher cadence (default 5)',
    '      --log <path>                   watcher log (default: C:\\test\\mumu-network-update.txt)',
    '  node mumu-menu.cjs --ps            full PowerShell menu (all features)',
    '  node mumu-menu.cjs --version       version of both engines',
    '  node mumu-menu.cjs --help          this text',
    '',
    'The PowerShell menu (mumu-menu.ps1) stays the reference implementation and',
    'keeps working exactly as before; this entry point is an additive engine.',
  ].join('\n');
}

function main(argv) {
  const args = argv.slice(2);
  const has = (flag) => args.includes(flag);
  const valueAfter = (flag) => {
    const i = args.indexOf(flag);
    if (i < 0) return null;
    const v = args[i + 1];
    return v && !v.startsWith('-') ? v : null;
  };

  if (has('--help') || has('-h')) {
    out(helpText());
    return;
  }
  if (has('--version') || has('-v')) {
    out('JavaScript entry : ' + VERSION + ' (node ' + process.version + ')');
    if (fs.existsSync(MENU_PS1)) out('PowerShell menu  : ' + MENU_PS1);
    else out('PowerShell menu  : not found next to this file');
    return;
  }
  if (has('--ps') || has('--powershell')) {
    runPowerShellMenu();
    return;
  }
  if (has('--status')) {
    showStatus({ json: has('--json') });
    return;
  }
  if (has('--list')) {
    const manager = requireManager();
    listInstances(manager).forEach((i) => out(String(i.index) + '\t' + (i.name || '')));
    return;
  }
  for (const [flag, action] of [['--start', 'launch'], ['--stop', 'shutdown'], ['--restart', 'restart']]) {
    if (has(flag)) {
      const index = valueAfter(flag);
      if (index === null) die(flag + ' needs an instance index, e.g. ' + flag + ' 0');
      controlInstance(action, index);
      return;
    }
  }
  if (has('--watch')) {
    const interval = Number(valueAfter('--interval') || 5);
    if (!Number.isFinite(interval) || interval < 1) die('--interval must be a number of seconds (>= 1)');
    startWatcher({ logPath: valueAfter('--log'), intervalMs: Math.round(interval * 1000) });
    return;
  }

  const unknown = args.filter((a) => a.startsWith('-'));
  if (unknown.length) die('unknown option: ' + unknown[0] + ' (see --help)');

  if (!isTTY()) {
    out(helpText());
    return;
  }
  interactive().catch((err) => die(err.message));
}

main(process.argv);
