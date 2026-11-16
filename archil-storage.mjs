/**
 * Server-side Archil disk storage for the MuMuManager CLI Menu repo.
 *
 * Configures the `disk` SDK from ARCHIL_API_KEY / ARCHIL_REGION and exposes
 * helpers for the disk named by ARCHIL_DISK_ID: run a command on it, and write
 * or read a file on it.
 *
 * Keep this module server-side only — the API key must never reach the browser
 * or a client bundle, so never import it from browser code and never expose the
 * key behind a NEXT_PUBLIC_/VITE_-style prefix.
 */
import * as archil from 'disk';

/** Region used when ARCHIL_REGION is unset. */
export const DEFAULT_REGION = 'aws-us-east-1';

let configured = false;
const diskCache = new Map();

/**
 * Configure the SDK once, from ARCHIL_API_KEY and ARCHIL_REGION.
 *
 * ARCHIL_BASE_URL / ARCHIL_S3_BASE_URL, when set, replace the control-plane and
 * object endpoints. The SDK already reads ARCHIL_S3_BASE_URL itself but has no
 * environment fallback for the control plane, so both are forwarded here: that
 * keeps a self-hosted or emulated endpoint reachable, and it is how the test
 * suite points the real SDK at a loopback stub instead of patching SDK
 * internals.
 */
export function configure() {
  const apiKey = process.env.ARCHIL_API_KEY;
  if (!apiKey) {
    throw new Error(
      'ARCHIL_API_KEY is not set. Set it to an Archil API key (starts with "key-") ' +
        'from https://console.archil.com/api-keys.',
    );
  }
  const baseUrl = process.env.ARCHIL_BASE_URL;
  const s3BaseUrl = process.env.ARCHIL_S3_BASE_URL;
  archil.configure({
    apiKey,
    region: process.env.ARCHIL_REGION || DEFAULT_REGION,
    ...(baseUrl ? { baseUrl } : {}),
    ...(s3BaseUrl ? { s3BaseUrl } : {}),
  });
  configured = true;
}

function ready() {
  if (!configured) configure();
}

/** The disk id from ARCHIL_DISK_ID (e.g. "dsk-…"). */
export function diskId() {
  const id = process.env.ARCHIL_DISK_ID;
  if (!id) {
    throw new Error(
      'ARCHIL_DISK_ID is not set. Set it to the id of an Archil disk (dsk-…).',
    );
  }
  return id;
}

/** Return the disk named by ARCHIL_DISK_ID, or an explicit disk id. */
export async function getDisk(id = diskId()) {
  ready();
  if (!diskCache.has(id)) {
    diskCache.set(id, await archil.getDisk(id));
  }
  return diskCache.get(id);
}

/**
 * Run a shell command on the disk. The disk is mounted at /mnt/data and is the
 * working directory; each call is a fresh container, so only files on the disk
 * persist. Returns { stdout, stderr, exitCode, timing }.
 */
export async function runCommand(command, id = diskId()) {
  const disk = await getDisk(id);
  return disk.exec(command);
}

function validateObjectKey(key) {
  if (typeof key !== 'string') {
    throw new TypeError('Object key must be a string.');
  }
  // The SDK leaves literal ".." segments in URLs, where Request normalization
  // can remove the selected disk id. Reject them before any SDK operation.
  if (key.split('/').includes('..')) {
    throw new Error('Object key must not contain parent-directory ("..") segments.');
  }
}

/** Write a file on the disk through the object API. Rejects parent segments. */
export async function writeFile(key, body, id = diskId()) {
  validateObjectKey(key);
  const disk = await getDisk(id);
  return disk.putObject(key, body);
}

/** Read a file as a string through the object API. Rejects parent segments. */
export async function readFile(key, id = diskId()) {
  validateObjectKey(key);
  const disk = await getDisk(id);
  const bytes = await disk.getObject(key);
  return new TextDecoder().decode(bytes);
}

/**
 * Create a new disk through the SDK. Returns the Disk only — the one-time mount
 * token stays inside the SDK so it is never printed or logged.
 */
export async function createDisk(name) {
  ready();
  const { disk } = await archil.createDisk({ name });
  return disk;
}

/** List this account's disks. */
export async function listDisks() {
  ready();
  return archil.listDisks();
}
