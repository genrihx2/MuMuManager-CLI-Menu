import assert from 'node:assert/strict';
import test from 'node:test';
import { Disk, Disks } from 'disk';
import createClient from 'openapi-fetch';

async function storageFixture(t) {
  // Each test needs its own module-level disk cache.
  const storage = await import(`../archil-storage.mjs?test=${encodeURIComponent(t.name)}`);
  const environment = {
    ARCHIL_API_KEY: 'key-synthetic-test',
    ARCHIL_REGION: 'aws-us-east-1',
    ARCHIL_DISK_ID: 'dsk-default',
  };
  for (const [name, value] of Object.entries(environment)) {
    const previous = process.env[name];
    process.env[name] = value;
    t.after(() => {
      if (previous === undefined) delete process.env[name];
      else process.env[name] = previous;
    });
  }
  storage.configure();

  // Keep the installed SDK's object methods and Request construction; replace
  // disk discovery and the HTTP transport so no real service is contacted.
  const requests = [];
  const client = createClient({
    baseUrl: 'https://storage.example.invalid',
    headers: { Authorization: environment.ARCHIL_API_KEY },
    fetch: async (request) => {
      requests.push(request);
      return new Response('stored text ✓', { headers: { etag: 'test-etag' } });
    },
  });
  const lookup = t.mock.method(Disks.prototype, 'get', async (id) =>
    new Disk({ id }, client, environment.ARCHIL_REGION, 'https://storage.example.invalid'),
  );
  return { ...storage, requests, lookup };
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
    const { readFile, writeFile, requests, lookup } = await storageFixture(t);
    const operation = name === 'readFile' ? readFile : (key, id) => writeFile(key, 'new text ✓', id);
    for (const key of parentKeys) {
      // Exercise both an explicit disk and ARCHIL_DISK_ID.
      for (const id of ['dsk-selected', undefined]) {
        await assert.rejects(operation(key, id), /parent-directory/i);
      }
    }
    assert.equal(lookup.mock.callCount(), 0);
    assert.equal(requests.length, 0);
  });

  test(`${name} rejects non-string keys before disk lookup`, async (t) => {
    const { readFile, writeFile, requests, lookup } = await storageFixture(t);
    const operation = name === 'readFile' ? readFile : (key, id) => writeFile(key, 'new text ✓', id);
    for (const key of [undefined, null, 42, {}, [], new String('../dsk-other/file')]) {
      await assert.rejects(operation(key, 'dsk-selected'), TypeError);
    }
    assert.equal(lookup.mock.callCount(), 0);
    assert.equal(requests.length, 0);
  });
}

test('valid keys preserve the selected disk, encoding, bodies and return values', async (t) => {
  const { readFile, writeFile, requests } = await storageFixture(t);
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
  for (const id of ['dsk-selected', undefined]) {
    for (const [key, path] of keys) {
      assert.deepEqual(await writeFile(key, 'new text ✓', id), { etag: 'test-etag' });
      assert.equal(await readFile(key, id), 'stored text ✓');
      const [write, read] = requests.slice(-2);
      assert.equal(write.method, 'PUT');
      assert.equal(await write.text(), 'new text ✓');
      assert.equal(read.method, 'GET');
      for (const request of [write, read]) {
        assert.equal(request.url, `https://storage.example.invalid/${id ?? 'dsk-default'}/${path}`);
        assert.equal(request.headers.get('authorization'), 'key-synthetic-test');
      }
    }
  }
});
