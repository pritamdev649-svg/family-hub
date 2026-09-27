import { z } from 'zod';
import {
  countryCode,
  currencyCode,
  email,
  inviteCode,
  isoDate,
  locale,
  nullableField,
  password,
  personName,
  timeZone,
} from '../../lib/validate.js';
import { normalizePassword, passwordTooLongForBcrypt } from './auth.passwords.js';

/**
 * Request bodies of `/auth/*` (docs/03-API_CONTRACT.md §4). Unknown keys are stripped
 * (mass assignment of `role`, `familyId`, `emailVerified` … is impossible).
 * Emails are trimmed + lower-cased by the shared `email` block.
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const OLDEST_BIRTH_YEAR = 1900;

// ---------------------------------------------------------------- names

/**
 * C0/C1 control characters (newlines, tabs, NUL …) and the bidi embedding / override /
 * isolate controls used for "Trojan Source"-style spoofing (U+202A–U+202E, U+2066–U+2069).
 * Letters of every script, combining marks, ZWJ / ZWNJ (Indic scripts, emoji sequences) and
 * the plain LRM / RLM / ALM marks stay allowed.
 */
const FORBIDDEN_NAME_CHARS = /[\p{Cc}\u202A-\u202E\u2066-\u2069]/u;
/** Characters that render as nothing (Hangul fillers, Braille blank) — ignored by the "visible" check. */
const BLANK_LOOKING_CHARS = /[\u115F\u1160\u3164\uFFA0\u2800]/gu;
const VISIBLE_CHAR = /[\p{L}\p{N}\p{S}]/u;

const nfc = (v) => (typeof v === 'string' ? v.normalize('NFC') : v);

/**
 * Person / family name: the shared `personName` rules (trimmed, 1–60) on the NFC form, no
 * control or bidi-override characters, and at least one visible letter, digit or symbol
 * (emoji count), so names are never blank-looking or able to reorder the text around them in
 * push notifications and e-mails.
 */
export const displayName = z.preprocess(
  nfc,
  personName
    .refine((v) => !FORBIDDEN_NAME_CHARS.test(v), 'Name contains characters that are not allowed')
    .refine((v) => VISIBLE_CHAR.test(v.replace(BLANK_LOOKING_CHARS, '')), 'Name must contain a letter or digit'),
);

// ---------------------------------------------------------------- passwords

const nfkc = (v) => normalizePassword(v);

/**
 * New passwords, checked on their NFKC form (what gets hashed): contract rules (≥ 8,
 * letter + digit) and ≤ 72 UTF-8 bytes (bcrypt limit).
 */
export const newPassword = z.preprocess(nfkc, password.refine((v) => !passwordTooLongForBcrypt(v), 'Password is too long'));

/** A password typed to sign in / confirm: never re-checked against the rules, only bounded. */
const currentPassword = z.preprocess(
  nfkc,
  z.string({ error: 'Password is required' }).min(1, 'Password is required').max(128),
);

// ---------------------------------------------------------------- one-time codes

/**
 * First code point ("0") of the decimal-digit blocks of the scripts the app supports
 * (hi/mr Devanagari, bn, pa, gu, ta, te, kn, ml, ar Arabic-Indic + Extended/Persian) plus
 * Odia. Full-width and mathematical digits are covered by NFKC.
 */
const DIGIT_ZEROS = [0x30, 0x660, 0x6f0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66, 0xbe6, 0xc66, 0xce6, 0xd66];

/** Native decimal digits (e.g. Arabic-Indic ٤, Devanagari ४) → ASCII `0-9`; other characters unchanged. */
export function toAsciiDigits(value) {
  return value.normalize('NFKC').replace(/\p{Nd}/gu, (ch) => {
    const cp = ch.codePointAt(0);
    const zero = DIGIT_ZEROS.find((z0) => cp >= z0 && cp <= z0 + 9);
    return zero === undefined ? ch : String(cp - zero);
  });
}

const asciiDigits = (v) => (typeof v === 'string' ? toAsciiDigits(v) : v);

/** 6-digit code; spaces and dashes are ignored and native digits (٠-٩, ०-९ …) accepted. */
export const otpCode = z
  .string({ error: 'Code is required' })
  .max(64, 'Code must be 6 digits')
  .transform((v) => toAsciiDigits(v).replace(/[\s-]/g, ''))
  .pipe(z.string().regex(/^\d{6}$/, 'Code must be 6 digits'));

const dateOfBirth = nullableField(
  isoDate
    .refine((d) => d.getTime() <= Date.now() + DAY_MS, 'Date of birth cannot be in the future')
    .refine((d) => d.getUTCFullYear() >= OLDEST_BIRTH_YEAR, 'Invalid date of birth'),
);

const refreshToken = z.string({ error: 'Refresh token is required' }).trim().min(1, 'Refresh token is required').max(512);

export const familyInputSchema = z.object({
  name: displayName,
  country: countryCode,
  currency: currencyCode,
  timezone: timeZone,
});

/**
 * `family` only matters for `create` and `inviteCode` only for `join`; the other one is
 * ignored (the app sends it as null) instead of failing validation.
 */
function dropFieldsOfOtherMode(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return value;
  if (value.mode === 'create') {
    const { inviteCode: _ignored, ...rest } = value;
    return rest;
  }
  if (value.mode === 'join') {
    const { family: _ignored, ...rest } = value;
    return rest;
  }
  return value;
}

const registerObject = z
  .object({
    name: displayName,
    email,
    password: newPassword,
    locale: nullableField(locale),
    consentAccepted: z.literal(true, { error: 'You must accept the privacy policy and terms' }),
    dateOfBirth,
    mode: z.enum(['create', 'join'], { error: "Mode must be 'create' or 'join'" }),
    family: familyInputSchema.nullish(),
    // Native / full-width digits and letters (e.g. "ｄｅｍｏ-२३४५") → the shared invite-code rules.
    inviteCode: nullableField(z.preprocess(asciiDigits, inviteCode)),
  })
  .superRefine((v, ctx) => {
    if (v.mode === 'create' && !v.family) {
      ctx.addIssue({ code: 'custom', path: ['family'], message: 'Family details are required to create a family' });
    }
    if (v.mode === 'join' && !v.inviteCode) {
      ctx.addIssue({ code: 'custom', path: ['inviteCode'], message: 'An invite code is required to join a family' });
    }
  });

export const registerSchema = z.preprocess(dropFieldsOfOtherMode, registerObject);

export const loginSchema = z.object({ email, password: currentPassword });

export const refreshSchema = z.object({ refreshToken });

export const logoutSchema = z.object({
  refreshToken,
  deviceToken: nullableField(z.string().trim().min(1).max(4096)),
});

export const verifyEmailSchema = z.object({ otp: otpCode });

export const forgotPasswordSchema = z.object({ email });

export const resetPasswordSchema = z.object({ email, otp: otpCode, newPassword });

export const changePasswordSchema = z
  .object({ currentPassword, newPassword })
  .refine((v) => v.currentPassword !== v.newPassword, {
    path: ['newPassword'],
    message: 'The new password must be different from the current one',
  });
