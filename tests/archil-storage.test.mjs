import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';

// Regression tests for archil-storage.mjs.
//
// The transport stub is a loopback HTTP server, not a patched SDK: the module
// is pointed at it through the SDK's documented endpoint options (baseUrl /
// s3BaseUrl), so the real SDK still parses, encodes and normalizes every URL.
// That is exactly the property the path-traversal fix relies on.
//
// The previous version of this file replaced the SDK's private `_client` with
// an openapi-fetch client whose `fetch` returned canned responses. It passed on
// disk 1.8.0 and broke on 1.12.0 (`this._client.raw is not a function`) because
// it asserted on internals that changed. Nothing here may reach into the SDK.

const SELECTED_DISK = 'dsk-selected';
const DEFAULT_DISK = 'dsk-default';
const API_KEY = 'key-synthetic-test';

/**
 * A stand-in for the Archil control plane and S3 endpoint: enough to answer
 * disk discovery, PutObject and GetObject, while recording every request the
 * SDK actually sends.
 */
async function startTransportStub() {
  const requests = [];
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      const body = Buffer.concat(chunks);
      requests.push({ method: req.method, url: req.url ?? '', headers: req.headers, body });

      // Closing each connection keeps the SDK's pooled agent from holding an
      // idle keep-alive socket after the suite finishes.
      res.setHeader('Connection', 'close');

      const control = /^\/api\/disks\/([^/?]+)/.exec(req.url ?? '');
      if (control) {
        const id = decodeURIComponent(control[1]);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, data: { id, name: id } }));
        return;
      }
      if (req.method === 'GET') {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('stored text ✓');
        return;
      }
      res.writeHead(200, { ETag: 'test-etag' });
      res.end();
    });
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  return {
    origin: 'http://127.0.0.1:' + port,
    requests,
    async close() {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    },
  };
}

async function storageFixture(t) {
  const stub = await startTransportStub();
  t.after(() => stub.close());

  const environment = {
    ARCHIL_API_KEY: API_KEY,
    ARCHIL_REGION: 'aws-us-east-1',
    ARCHIL_DISK_ID: DEFAULT_DISK,
    ARCHIL_BASE_URL: stub.origin,
    ARCHIL_S3_BASE_URL: stub.origin,
  };
  for (const [name, value] of Object.entries(environment)) {
    const previous = process.env[name];
    process.env[name] = value;
    t.after(() => {
      if (previous === undefined) delete process.env[name];
      else process.env[name] = previous;
    });
  }

  // Each test needs its own module-level disk cache.
  const storage = await import('../archil-storage.mjs?test=' + encodeURIComponent(t.name));
  storage.configure();
  return { ...storage, requests: stub.requests, origin: stub.origin };
}

/** Object (S3) traffic, i.e. everything that is not a control-plane call. */
function objectRequests(requests, origin) {
  return requests.filter((request) => !new URL(request.url, origin).pathname.startsWith('/api/'));
}

/** disk 1.8.0 sends the bare key, 1.12.0 sends "Bearer <key>". */
function assertAuthenticated(request) {
  assert.ok(
    String(request.headers.authorization ?? '').endsWith(API_KEY),
    'the request must carry the API key',
  );
}

const parentKeys = [
  '../dsk-other/secret.txt',
  '/../dsk-other/secret.txt',
  'folder/../../dsk-other/secret.txt',
  'folder/../file.txt',
  'folder//../file.txt',
  'folder/..',
  '..',
  '../',
];

for (const name of ['readFile', 'writeFile']) {
  test(`${name} rejects parent segments before disk lookup or object requests`, async (t) => {
    const { readFile, writeFile, requests } = await storageFixture(t);
    const operation = name === 'readFile' ? readFile : (key, id) => writeFile(key, 'new text ✓', id);
    for (const key of parentKeys) {
      // Exercise both an explicit disk and ARCHIL_DISK_ID.
      for (const id of [SELECTED_DISK, undefined]) {
        await assert.rejects(operation(key, id), /parent-directory/i);
      }
    }
    assert.deepEqual(requests, [], 'a rejected key must not reach the network, not even disk discovery');
  });

  test(`${name} rejects non-string keys before disk lookup`, async (t) => {
    const { readFile, writeFile, requests } = await storageFixture(t);
    const operation = name === 'readFile' ? readFile : (key, id) => writeFile(key, 'new text ✓', id);
    for (const key of [undefined, null, 42, {}, [], new String('../dsk-other/file')]) {
      await assert.rejects(operation(key, SELECTED_DISK), TypeError);
    }
    assert.deepEqual(requests, [], 'a rejected key must not reach the network, not even disk discovery');
  });
}

test('valid keys stay inside the selected disk, with the SDK encoding and bodies intact', async (t) => {
  const { readFile, writeFile, requests, origin } = await storageFixture(t);
  const keys = [
    ['reports/2026/data.json', 'reports/2026/data.json'],
    ['/leading.txt', 'leading.txt'],
    ['folder/./file.txt', 'folder/file.txt'],
    ['folder//file.txt', 'folder//file.txt'],
    ['folder/', 'folder/'],
    ['..hidden/name..txt', '..hidden/name..txt'],
    ['folder/日本語 #?.txt', 'folder/%E6%97%A5%E6%9C%AC%E8%AA%9E%20%23%3F.txt'],
    ['%2e%2e/dsk-other/file.txt', '%252e%252e/dsk-other/file.txt'],
    ['..\\dsk-other\\file.txt', '..%5Cdsk-other%5Cfile.txt'],
  ];

  for (const id of [SELECTED_DISK, undefined]) {
    const disk = id ?? DEFAULT_DISK;
    for (const [key, path] of keys) {
      assert.deepEqual(await writeFile(key, 'new text ✓', id), { etag: 'test-etag' });
      assert.equal(await readFile(key, id), 'stored text ✓');

      const [write, read] = objectRequests(requests, origin).slice(-2);
      assert.equal(write.method, 'PUT');
      assert.equal(write.body.toString('utf8'), 'new text ✓');
      assert.equal(read.method, 'GET');

      for (const request of [write, read]) {
        const pathname = new URL(request.url, origin).pathname;
        assert.equal(pathname, '/' + disk + '/' + path);
        // The disk id must remain the first path segment: that is what the
        // traversal fix protects when Request normalization runs.
        assert.equal(pathname.split('/')[1], disk);
        assertAuthenticated(request);
      }
    }
  }
});

test('disk discovery is requested once per disk and cached', async (t) => {
  const { readFile, writeFile, requests, origin } = await storageFixture(t);
  await writeFile('a.txt', 'first ✓', SELECTED_DISK);
  await readFile('a.txt', SELECTED_DISK);
  await writeFile('b.txt', 'second ✓');

  const pathnameOf = (request) => new URL(request.url, origin).pathname;
  const lookups = requests.filter((request) => pathnameOf(request) === '/api/disks/' + SELECTED_DISK);
  assert.equal(lookups.length, 1);
  assert.equal(lookups[0].method, 'GET');
  assertAuthenticated(lookups[0]);

  // ARCHIL_DISK_ID asks for a different disk, which is discovered once too.
  const defaultLookups = requests.filter((request) => pathnameOf(request) === '/api/disks/' + DEFAULT_DISK);
  assert.equal(defaultLookups.length, 1);
});
