#!/usr/bin/env node
'use strict';

var fs = require('fs');
var path = require('path');

var PKG_DIR = __dirname;
var pkgPath = path.resolve(PKG_DIR, 'package.json');
var pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));

var REPO_ROOT = path.resolve(PKG_DIR, '..');

function relToRepoRoot(absFile) {
  return path.relative(REPO_ROOT, absFile);
}

function makeManifest() {
  var out = [];
  (pkg.files || []).forEach(function (rel) {
    var abs = path.resolve(PKG_DIR, rel);
    if (!fs.existsSync(abs)) {
      console.warn(
        'release-notes: file listed in package.files but not present: ' +
          rel +
          ' (abs=' +
          abs +
          ')'
      );
      return;
    }
    out.push({
      path: relToRepoRoot(abs),
      size: fs.statSync(abs).size
    });
  });
  return out;
}

function gitHeadAt(dir) {
  try {
    var sha = require('child_process').execFileSync(
      'git',
      ['rev-parse', 'HEAD'],
      { cwd: dir, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }
    ).trim();
    return sha || null;
  } catch (e) {
    return null;
  }
}

function findGitRoot(start) {
  var cur = start;
  while (cur) {
    if (fs.existsSync(path.resolve(cur, '.git'))) return cur;
    var parent = path.dirname(cur);
    if (parent === cur) return null;
    cur = parent;
  }
  return null;
}

var notes = {
  package: pkg.name,
  version: pkg.version,
  kind: 'experiment',
  summary: pkg.description,
  repository: pkg.repository || null,
  released: {
    packagingTime: new Date().toISOString(),
    commitish: gitHeadAt(PKG_DIR),
    treeRoot: REPO_ROOT,
    packageFile: path.relative(REPO_ROOT, pkgPath),
    archiveManifest: makeManifest()
  },
  bundleFiles: pkg.files
      ? pkg.files
          .map(function (r) {
            return path.relative(REPO_ROOT, path.resolve(PKG_DIR, r));
          })
          .map(function (r) { return r.replace(/\\/g, '/'); })
      : [],
  changes: changesText()
};

var outPath = path.resolve(PKG_DIR, 'release-notes.json');
fs.writeFileSync(outPath, JSON.stringify(notes, null, 2) + '\n', 'utf8');
console.log('Wrote ' + outPath);

function changesText() {
  var parts = [
    'Package: ' + pkg.name + ' ' + pkg.version,
    'Type: experimental Archil disk persistence integration',
    'Artifacts (relative to repo root): ' + (pkg.files || []).join(', ')
  ];
  if (gitHeadAt(PKG_DIR)) parts.push('Committed at packaging time under the experiment tree.');
  return parts.join(' · ');
}
