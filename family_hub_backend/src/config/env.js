import fs from 'node:fs';
import dotenv from 'dotenv';
import { z } from 'zod';

/**
 * Validated, frozen configuration. Import `{ env }` — never read `process.env` elsewhere
 * (except logger.js, which must work before this module loads).
 *
 * Test mode: tests set `NODE_ENV=test` before importing the app (tests/helpers.js). Files
 * run by `node --test` without NODE_ENV are detected through NODE_TEST_CONTEXT, so a
 * developer's `.env` can never switch a test run to development/production behaviour.
 * The `.env` file is not loaded in test mode (hermetic tests).
 */
if (!process.env.NODE_ENV && process.env.NODE_TEST_CONTEXT) process.env.NODE_ENV = 'test';
if (process.env.NODE_ENV !== 'test') dotenv.config({ quiet: true });

const bool = z
  .union([z.boolean(), z.string()])
  .transform((v) => v === true || ['true', '1', 'yes'].includes(String(v).trim().toLowerCase()));

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(4000),
  CORS_ORIGINS: z.string().default('*'),
  APP_NAME: z.string().default('FamilyHub'),
  /** Express "trust proxy" (false | true | hop count | "loopback" …) — set behind a load balancer. */
  TRUST_PROXY: z.string().default('false'),
  /** Enables the rate limiters inside tests (they are skipped in test mode by default). */
  RATE_LIMIT_IN_TEST: bool.default(false),

  MONGODB_URI: z.string().default('mongodb://127.0.0.1:27017/familyhub'),

  JWT_ACCESS_SECRET: z.string().min(32, 'JWT_ACCESS_SECRET must be at least 32 characters'),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  FIELD_ENCRYPTION_KEY: z.string().optional().default(''),

  SMTP_HOST: z.string().optional().default(''),
  SMTP_PORT: z.coerce.number().int().positive().default(587),
  SMTP_SECURE: bool.default(false),
  SMTP_USER: z.string().optional().default(''),
  SMTP_PASS: z.string().optional().default(''),
  MAIL_FROM: z.string().default('FamilyHub <no-reply@familyhub.app>'),

  FIREBASE_SERVICE_ACCOUNT_PATH: z.string().optional().default(''),
  FIREBASE_SERVICE_ACCOUNT_BASE64: z.string().optional().default(''),

  CLOUDINARY_CLOUD_NAME: z.string().optional().default(''),
  CLOUDINARY_API_KEY: z.string().optional().default(''),
  CLOUDINARY_API_SECRET: z.string().optional().default(''),
});

const defaultsForNonProd = {
  JWT_ACCESS_SECRET: 'dev-only-insecure-secret-change-me-please-0123456789',
};

function fail(lines) {
  // eslint-disable-next-line no-console
  console.error(`Invalid environment configuration:\n${lines.map((l) => `  - ${l}`).join('\n')}`);
  process.exit(1);
}

function parseTrustProxy(value) {
  const v = String(value).trim().toLowerCase();
  if (v === '' || v === 'false' || v === '0') return false;
  if (v === 'true') return true;
  if (/^\d+$/.test(v)) return Number(v);
  return value.trim(); // e.g. "loopback", "10.0.0.0/8"
}

function readVersion() {
  try {
    const pkg = JSON.parse(fs.readFileSync(new URL('../../package.json', import.meta.url), 'utf8'));
    return String(pkg.version ?? '0.0.0');
  } catch {
    return '0.0.0';
  }
}

function load() {
  const raw = { ...process.env };
  const nodeEnv = raw.NODE_ENV ?? 'development';
  if (nodeEnv !== 'production') {
    for (const [k, v] of Object.entries(defaultsForNonProd)) {
      if (!raw[k]) raw[k] = v;
    }
  }
  const parsed = schema.safeParse(raw);
  if (!parsed.success) {
    fail(parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`));
  }
  const env = parsed.data;
  const problems = [];
  if (env.FIELD_ENCRYPTION_KEY && Buffer.from(env.FIELD_ENCRYPTION_KEY, 'base64').length !== 32) {
    problems.push('FIELD_ENCRYPTION_KEY must be 32 random bytes, base64 encoded');
  }
  if (env.NODE_ENV === 'production') {
    if (!env.FIELD_ENCRYPTION_KEY) problems.push('FIELD_ENCRYPTION_KEY is required in production');
    if (/change-me/i.test(env.JWT_ACCESS_SECRET)) problems.push('JWT_ACCESS_SECRET still has the example value');
  }
  if (problems.length) fail(problems);

  return Object.freeze({
    ...env,
    isProd: env.NODE_ENV === 'production',
    isTest: env.NODE_ENV === 'test',
    isDev: env.NODE_ENV === 'development',
    corsOrigins: env.CORS_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean),
    trustProxy: parseTrustProxy(env.TRUST_PROXY),
    version: readVersion(),
  });
}

export const env = load();
