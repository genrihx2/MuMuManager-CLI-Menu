#!/usr/bin/env node
/**
 * Node wrapper for the MuMuManager CLI Menu.
 *
 * Usage (repo root only):
 *   node mumu-menu.cjs        # delegates to .\\mumu-menu.ps1
 *   npm run menu              # same, via package.json script
 *
 * The real menu is mumu-menu.ps1 (PowerShell). This wrapper only locates the
 * repo folder relative to itself and delegates to PowerShell. It does not
 * replace the PowerShell menu and does not make MuMu or an interactive PowerShell
 * session unnecessary.
 *
 * Must be run from the repo root: the wrapper resolves mumu-menu.ps1 relative to
 * its own location and refuses to run if the expected menu file is not beside/under it.
 *
 * When run from a non-interactive terminal (no TTY), the wrapper prints a clear
 * message and exits instead of spawning an interactive PowerShell menu that would
 * just hang.
 */
'use strict';

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const isTTY = process.stdin.isTTY;

const WRAPPER_DIR = __dirname;
const MENU_REL = 'mumu-menu.ps1';
const MENU_PATH = path.resolve(WRAPPER_DIR, MENU_REL);

function fail(msg) {
  process.stderr.write('mumu-menu: ' + msg + '\n');
  process.exit(1);
}

if (!fs.existsSync(MENU_PATH)) {
  fail(
    'mumu-menu.ps1 not found next to this wrapper (' +
      MENU_PATH +
      '). Run this from the MuMuManager-CLI-Menu repository root.'
  );
}

if (!isTTY) {
  process.stdout.write(
    'mumu-menu: the interactive PowerShell menu requires a TTY. ' +
      'Run .\\mumu-menu.ps1 from an interactive PowerShell session.\n'
  );
  process.exit(0);
}

const psArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', MENU_PATH];

let psExe = 'powershell.exe';
try {
  const systemRoot = process.env.SystemRoot || 'C:\\Windows';
  const pwsh = 'pwsh.exe';
  if (fs.existsSync(path.join(systemRoot, pwsh))) {
    psExe = pwsh;
  } else if (fs.existsSync(pwsh)) {
    psExe = pwsh;
  }
} catch (e) {
  // best-effort only
}

const ps = spawn(psExe, psArgs, { stdio: 'inherit', windowsVerbatimArguments: true });

ps.on('error', function (err) {
  if (err.code === 'ENOENT') {
    fail(
      'PowerShell not found (tried ' +
        psExe +
        '). Install PowerShell and run this from the MuMuManager-CLI-Menu repo root.'
    );
  }
  fail('Could not start PowerShell: ' + err.message);
});

ps.on('close', function (code) {
  if (code !== 0) {
    process.exit(code || 1);
  }
});

process.on('exit', function () {
  try { ps.kill(); } catch (e) {}
});
