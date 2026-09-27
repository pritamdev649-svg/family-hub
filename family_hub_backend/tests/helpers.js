/**
 * Shared test helpers (docs/06-BACKEND_GUIDE.md §6).
 *
 *   import { setupTestApp, teardownTestApp, resetDb, registerFamilyAdmin } from './helpers.js';
 *   let request;
 *   before(async () => ({ request } = await setupTestApp()));
 *   beforeEach(resetDb);
 *   after(teardownTestApp);
 *
 * Import this file FIRST in a test file: it sets NODE_ENV=test before any src/ module
 * (and therefore config/env.js) is evaluated — every src/ import below is dynamic for that reason.
 */
import http from 'node:http';
import { MongoMemoryServer } from 'mongodb-memory-server';
import supertest from 'supertest';

process.env.NODE_ENV = 'test';

const mailer = await import('../src/services/mailer.js');
const push = await import('../src/services/push.js');

/** E-mails "sent" during the test file: `{ to, subject, text, html, template, locale, vars }[]`. */
export const outbox = mailer.outbox;
/** Push intents: `{ type, id, route, familyId, titleKey, bodyKey, vars, memberIds, messages, … }[]`. */
export const sentPushes = push.sentPushes;
/** Waits until recipients of every queued push are resolved (fills `memberIds` / `messages`). */
export const flushPushes = push.flushPushes;

export const API = '/api/v1';

let mongod;
let server;
let ctx;

/**
 * Starts an in-memory MongoDB (once per test file), connects mongoose, builds all indexes
 * and returns `{ app, request, server }` — `request` is a supertest instance bound to the app.
 */
export async function setupTestApp() {
  if (ctx) return ctx;
  mongod = await MongoMemoryServer.create();
  const { connectDb } = await import('../src/config/db.js');
  await connectDb(mongod.getUri('familyhub_test'));
  const { initModels } = await import('../src/models/index.js');
  await initModels(); // unique/TTL indexes must exist before duplicate-key tests
  const { createApp } = await import('../src/app.js');
  const app = createApp();
  server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  ctx = { app, request: supertest(server), server };
  return ctx;
}

/** Stops the server, flushes pushes, disconnects mongoose and stops MongoDB. */
export async function teardownTestApp() {
  await push.flushPushes();
  if (server) {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(() => resolve()));
  }
  const { disconnectDb } = await import('../src/config/db.js');
  await disconnectDb();
  if (mongod) await mongod.stop({ doCleanup: true });
  server = undefined;
  mongod = undefined;
  ctx = undefined;
}

/** Deletes every document (indexes are kept) and clears `outbox` / `sentPushes`. */
export async function resetDb() {
  await push.flushPushes();
  const { default: mongoose } = await import('mongoose');
  const collections = await mongoose.connection.db.collections();
  await Promise.all(collections.map((c) => c.deleteMany({})));
  outbox.length = 0;
  sentPushes.length = 0;
}

let seq = 0;
/** Unique, valid e-mail for this test process. */
export function uniqueEmail(prefix = 'user') {
  seq += 1;
  return `${prefix}.${process.pid}.${Date.now().toString(36)}.${seq}@example.com`;
}

export const DEFAULT_PASSWORD = 'secret123';

/** `{ Authorization: 'Bearer <accessToken>' }` from a tokens object or raw token. */
export function authHeader(tokensOrToken) {
  const token = typeof tokensOrToken === 'string' ? tokensOrToken : tokensOrToken?.accessToken;
  return { Authorization: `Bearer ${token}` };
}

function ensureCtx() {
  if (!ctx) throw new Error('Call setupTestApp() before using the request helpers');
  return ctx;
}

function fail(what, res) {
  const err = new Error(`${what} failed: HTTP ${res.status} ${JSON.stringify(res.body)}`);
  err.response = res;
  return err;
}

function withAuth(data, password) {
  return { ...data, password, auth: authHeader(data.tokens) };
}

/**
 * Registers a new user who creates a family (admin).
 * @param {object} [overrides] merged into the register body (`family` is merged too)
 * @returns {Promise<{ user, member, family, tokens, auth: { Authorization: string }, password: string }>}
 */
export async function registerFamilyAdmin(overrides = {}) {
  const { request } = ensureCtx();
  const { family: familyOverrides, ...rest } = overrides;
  const body = {
    name: 'Amit Sharma',
    email: uniqueEmail('admin'),
    password: DEFAULT_PASSWORD,
    locale: 'en',
    consentAccepted: true,
    dateOfBirth: '1985-02-01T00:00:00.000Z',
    mode: 'create',
    family: { name: 'Sharma Family', country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata', ...familyOverrides },
    inviteCode: null,
    ...rest,
  };
  const res = await request.post(`${API}/auth/register`).send(body);
  if (res.status !== 201) throw fail('registerFamilyAdmin', res);
  return withAuth(res.body.data, body.password);
}

/**
 * Registers a new user who joins an existing family with its invite code (member role).
 * @returns {Promise<{ user, member, family, tokens, auth: { Authorization: string }, password: string }>}
 */
export async function joinFamilyAs(inviteCode, overrides = {}) {
  const { request } = ensureCtx();
  const body = {
    name: 'Priya Sharma',
    email: uniqueEmail('member'),
    password: DEFAULT_PASSWORD,
    locale: 'en',
    consentAccepted: true,
    dateOfBirth: '1990-06-15T00:00:00.000Z',
    mode: 'join',
    inviteCode,
    ...overrides,
  };
  const res = await request.post(`${API}/auth/register`).send(body);
  if (res.status !== 201) throw fail('joinFamilyAs', res);
  return withAuth(res.body.data, body.password);
}

/**
 * Admin adds a member without an account (managed profile) — `POST /family/members`.
 * @param {{ Authorization: string }} adminAuth
 * @param {object} [body] merged over a default child profile with guardian consent
 * @returns {Promise<object>} the created Member
 */
export async function addManagedMember(adminAuth, body = {}) {
  const { request } = ensureCtx();
  const res = await request
    .post(`${API}/family/members`)
    .set(adminAuth)
    .send({
      name: 'Anaya',
      email: null,
      phone: null,
      dateOfBirth: '2016-08-01T00:00:00.000Z',
      gender: 'female',
      designation: 'Junior Explorer',
      role: 'member',
      guardianConsent: true,
      ...body,
    });
  if (res.status !== 201) throw fail('addManagedMember', res);
  return res.body.data;
}

/** Last e-mail sent to an address (or undefined). */
export function lastMailTo(email) {
  const to = String(email).toLowerCase();
  return [...outbox].reverse().find((m) => String(m.to).toLowerCase() === to);
}

/** Extracts the first 6-digit code from the last e-mail sent to `email`. */
export function lastOtpFor(email) {
  const mail = lastMailTo(email);
  if (!mail) return undefined;
  if (mail.vars?.code) return String(mail.vars.code);
  return /\b(\d{6})\b/.exec(mail.text ?? '')?.[1];
}
