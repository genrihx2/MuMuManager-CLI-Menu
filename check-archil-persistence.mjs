#!/usr/bin/env node
/**
 * Archil persistence check for the MuMuManager CLI Menu repo.
 *
 * Writes a unique marker line into a fresh per-run directory in a first exec,
 * then reads it back in a second, separate exec on the same disk. Because each
 * exec runs in a fresh container, a successful read-back proves the file
 * outlived the container that wrote it. Exits non-zero on any failure.
 *
 * Run:  npm run check:archil
 * Needs ARCHIL_API_KEY (an API key starting with "key-"); ARCHIL_REGION and
 * ARCHIL_DISK_ID are optional. Without ARCHIL_DISK_ID a disk is created.
 */
import { randomUUID } from 'node:crypto';
import { createDisk, getDisk, runCommand } from './archil-storage.mjs';

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function log(message) {
  console.log(message);
}

async function resolveDisk() {
  const id = process.env.ARCHIL_DISK_ID;
  if (id) {
    return getDisk(id);
  }
  const name = `mumu-menu-persistence-${new Date().toISOString().slice(0, 10)}`;
  log(`ARCHIL_DISK_ID is not set; creating a disk named "${name}" ...`);
  const disk = await createDisk(name);
  log(`Created disk ${disk.id} (region ${disk.region})`);
  return disk;
}

async function main() {
  if (!process.env.ARCHIL_API_KEY) {
    fail(
      'ARCHIL_API_KEY is not set.\n' +
        'Set it to an Archil API key that starts with "key-" (not a disk/mount\n' +
        'token, which starts with "adt_") from https://console.archil.com/api-keys,\n' +
        'then run: npm run check:archil',
    );
  }

  const disk = await resolveDisk();
  const id = disk.id;

  const stamp = `${Date.now()}-${randomUUID().slice(0, 8)}`;
  // A fresh per-job subdirectory: exec mounts are shared, and dynamic ownership
  // claims a directory this job creates, avoiding "Read-only file system".
  const dir = `archil-persistence-check-${stamp}`;
  const marker = `archil-persistence-ok:${stamp}`;

  // Exec #1 — write the unique marker line into the fresh directory.
  const write = await runCommand(
    `mkdir -p '${dir}' && printf '%s\n' '${marker}' > '${dir}/marker.txt'`,
    id,
  );
  if (write.exitCode !== 0) {
    fail(`write exec exited ${write.exitCode}\nstderr: ${write.stderr.trim()}`);
  }
  log(`Exec #1 wrote ${dir}/marker.txt`);

  // Exec #2 — a separate exec must still see the file, proving persistence.
  const read = await runCommand(`cat '${dir}/marker.txt'`, id);
  if (read.exitCode !== 0) {
    fail(`read-back exec exited ${read.exitCode}\nstderr: ${read.stderr.trim()}`);
  }
  const roundTripped = read.stdout.trim();
  if (!roundTripped.includes(marker)) {
    fail(
      'read-back output did not contain the written marker\n' +
        `  wrote: ${marker}\n  read:  ${roundTripped}`,
    );
  }

  log(`Exec #2 read it back from disk ${id}`);
  log(`PASS: the disk persisted the file across two separate execs`);
  log(`  wrote: ${marker}`);
  log(`  read:  ${roundTripped}`);
  log(`Add ARCHIL_DISK_ID=${id} to your local .env to reuse this disk.`);
}

main().catch((error) => {
  fail(error instanceof Error ? error.message : String(error));
});
