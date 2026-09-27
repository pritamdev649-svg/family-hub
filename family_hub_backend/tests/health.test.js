/**
 * Health endpoint + app wiring (docs/03-API_CONTRACT.md §1, §3).
 * Core helpers, middleware and services are covered by tests/core.test.js.
 */
import { API, setupTestApp, teardownTestApp } from './helpers.js';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { after, before, describe, it } from 'node:test';

const { t } = await import('../src/lib/i18n.js');

const pkg = JSON.parse(fs.readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

let request;

before(async () => {
  ({ request } = await setupTestApp());
});

after(teardownTestApp);

function assertErrorEnvelope(res, status, code) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, false);
  assert.equal(res.body.error.code, code);
  assert.equal(typeof res.body.error.message, 'string');
  assert.ok(res.body.error.message.length > 0);
}

describe('GET /api/v1/health', () => {
  it('returns { status, db, version } in the success envelope', async () => {
    const res = await request.get(`${API}/health`);
    assert.equal(res.status, 200);
    assert.match(res.headers['content-type'], /application\/json/);
    assert.deepEqual(res.body, { success: true, data: { status: 'ok', db: 'up', version: pkg.version } });
  });

  it('is never cached and needs no authentication', async () => {
    const res = await request.get(`${API}/health`).set('Authorization', 'Bearer not-a-token');
    assert.equal(res.status, 200);
    assert.equal(res.headers['cache-control'], 'no-store');
  });

  it('sets security headers and hides the framework', async () => {
    const res = await request.get(`${API}/health`);
    assert.equal(res.headers['x-powered-by'], undefined);
    assert.equal(res.headers['x-content-type-options'], 'nosniff');
  });

  it('answers CORS preflight requests', async () => {
    const res = await request
      .options(`${API}/health`)
      .set('Origin', 'https://app.example.com')
      .set('Access-Control-Request-Method', 'GET');
    assert.equal(res.status, 204);
    assert.ok(res.headers['access-control-allow-origin']);
  });
});

describe('app wiring', () => {
  it('unknown route → 404 NOT_FOUND envelope (inside and outside the API prefix)', async () => {
    assertErrorEnvelope(await request.get(`${API}/definitely-not-a-route`), 404, 'NOT_FOUND');
    assertErrorEnvelope(await request.post('/nope').send({}), 404, 'NOT_FOUND');
  });

  it('negotiates the locale from Accept-Language (unsupported → en)', async () => {
    const hi = await request.get(`${API}/nope`).set('Accept-Language', 'hi-IN,hi;q=0.9,en;q=0.8');
    assert.equal(hi.headers['content-language'], 'hi');
    assert.equal(hi.body.error.message, t('hi', 'common.errors.NOT_FOUND'));
    const xx = await request.get(`${API}/nope`).set('Accept-Language', 'xx-YY');
    assert.equal(xx.headers['content-language'], 'en');
    assert.equal(xx.body.error.message, t('en', 'common.errors.NOT_FOUND'));
  });

  it('parses JSON bodies before the routes (malformed → 400, > 100 kb → 413)', async () => {
    const broken = await request.post(`${API}/health`).set('Content-Type', 'application/json').send('{"broken":');
    assertErrorEnvelope(broken, 400, 'BAD_REQUEST');
    const big = await request
      .post(`${API}/health`)
      .set('Content-Type', 'application/json')
      .send(JSON.stringify({ blob: 'x'.repeat(110 * 1024) }));
    assertErrorEnvelope(big, 413, 'PAYLOAD_TOO_LARGE');
  });

  it('every module mount point boots (placeholder or real router, never a crash)', async () => {
    const paths = [
      '/auth/me',
      '/me',
      '/family',
      '/family/members/64b7f0c2a1b2c3d4e5f60718/emergency-card',
      '/tasks',
      '/ledger/entries',
      '/goals',
      '/notices',
      '/sos/active',
      '/dashboard',
    ];
    for (const path of paths) {
      const res = await request.get(`${API}${path}`);
      assert.ok([401, 404].includes(res.status), `${path} → ${res.status}`);
      assert.equal(res.body.success, false, path);
      assert.ok(res.body.error?.code, path);
    }
  });

  // Keep last: it disconnects the database.
  it('reports db "down" (still 200) when MongoDB is not connected', async () => {
    const { disconnectDb } = await import('../src/config/db.js');
    await disconnectDb();
    const res = await request.get(`${API}/health`);
    assert.equal(res.status, 200);
    assert.equal(res.body.data.status, 'ok');
    assert.equal(res.body.data.db, 'down');
  });
});
