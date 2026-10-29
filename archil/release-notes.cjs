#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const RELEASE_TAG = 'v10.4.1';
const RELEASE_DATE = '25.10.2026';

function readUtf8(file) {
  return fs.readFileSync(path.resolve(ROOT, file), 'utf8');
}

function readMe() {
  return readUtf8('README.md');
}

function readRelnotes() {
  return readUtf8('relnotes.md');
}

function readReleaseFiles() {
  return readUtf8('release-files.txt')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean)
    .filter((l) => !l.startsWith('#'));
}

function splitSections(text, re) {
  const out = [];
  const parts = text.split('\n');
  let cur = null;
  for (let i = 0; i < parts.length; i++) {
    const line = parts[i];
    const m = re.exec(line);
    if (m) {
      cur = { label: m[1], text: '' };
      out.push(cur);
    } else if (cur && line.trim()) {
      cur.text += (cur.text ? '\n' : '') + line;
    }
  }
  return out;
}

function extractChangelog(label, text, headingRe) {
  const sections = splitSections(text, headingRe);
  const section = sections.find((s) => s.label === label);
  if (!section) return '';
  return section.text
    .replace(/\r/g, '')
    .replace(/^### .*/, '')
    .replace(/^[-*•]\s+/gm, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function extractTableRows(text) {
  const rows = [];
  const lines = text.split(/\r?\n/);
  let inTable = false;
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith('|')) {
      if (inTable) {
        const cells = trimmed
          .split('|')
          .map((s) => s.trim())
          .filter(Boolean);
        if (cells.length >= 3) {
          const tag = cells[0].replace(/[#*]/g, '').trim();
          if (tag && /v\d/.test(tag)) {
            rows.push({ tag, date: cells[1] || '', note: cells.slice(2).join(' ').trim() });
          }
        }
      } else if (
        trimmed.includes('| Версия |') ||
        trimmed.includes('| Version |') ||
        trimmed.includes('| Версии |')
      ) {
        inTable = true;
      }
    } else if (inTable && trimmed) {
      inTable = false;
    }
  }
  return rows;
}

function printHuman() {
  const readme = readMe();
  const relnotes = readRelnotes();
  const files = readReleaseFiles();

  const ru = extractChangelog(
    'v10.4.1',
    relnotes,
    /^\s*##\s+(v\d+\.\d+\.\d+)\s*\(/m
  );
  const en = extractChangelog(
    'v10.4.1',
    readme,
    /^\s*###\s+(v\d+\.\d+\.\d+)(?:\s*\(.*\))?$/m
  );

  const ruRows = extractTableRows(relnotes);
  const enRows = extractTableRows(readme);

  const out = [];
  out.push(`Freebuff MuMuManager CLI Menu release notes: ${RELEASE_TAG} (${RELEASE_DATE})`);
  out.push('');
  out.push("### What's new");
  out.push('');
  out.push('#### RU');
  if (ru) {
    out.push(ru);
  } else {
    out.push('  - no Russian prose section found; see relnotes.md or README.md');
  }
  out.push('');
  out.push('#### EN');
  if (en) {
    out.push(en);
  } else {
    out.push('  - no English prose section found; see README.md');
  }
  out.push('');
  out.push('### Files in release set');
  out.push('');
  for (const f of files) {
    out.push(`  - ${f}`);
  }
  return out.join('\n');
}

console.log(printHuman());
