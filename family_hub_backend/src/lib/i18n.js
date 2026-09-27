import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_LOCALE, LOCALES } from './constants.js';
import { logger } from './logger.js';

/**
 * Server-side translations (docs/06-BACKEND_GUIDE.md §5).
 *
 * Files: `src/i18n/locales/<lang>/<namespace>.json`, loaded once at startup.
 * Key format: `<namespace>.<path.in.json>` — `t('hi', 'tasks.push.assigned.title')` reads
 * `locales/hi/tasks.json → { push: { assigned: { title } } }`.
 * Lookup order: requested locale → English → the key itself. `{name}` placeholders are
 * replaced from `vars` (unknown placeholders are left untouched).
 */

export const SUPPORTED_LOCALES = LOCALES;
export { DEFAULT_LOCALE };

const LOCALES_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../i18n/locales');

/** @type {Map<string, Map<string, string>>} locale → flattened key → text */
let catalogs = new Map();
/** Problems found while loading (e.g. invalid JSON) — exposed for tests/diagnostics. */
export const loadErrors = [];

function flatten(prefix, value, out) {
  if (typeof value === 'string') {
    out.set(prefix, value);
  } else if (typeof value === 'number' || typeof value === 'boolean') {
    out.set(prefix, String(value));
  } else if (value && typeof value === 'object' && !Array.isArray(value)) {
    for (const [k, v] of Object.entries(value)) flatten(prefix ? `${prefix}.${k}` : k, v, out);
  }
}

/** (Re)loads every catalog from disk. Called automatically on import. */
export function loadTranslations(dir = LOCALES_DIR) {
  const next = new Map();
  loadErrors.length = 0;
  let langs = [];
  try {
    langs = fs.readdirSync(dir, { withFileTypes: true }).filter((d) => d.isDirectory());
  } catch (err) {
    loadErrors.push({ file: dir, error: err.message });
    logger.warn(`i18n: cannot read ${dir}: ${err.message}`);
  }
  for (const lang of langs) {
    const code = lang.name.toLowerCase();
    const catalog = new Map();
    const langDir = path.join(dir, lang.name);
    let files = [];
    try {
      files = fs.readdirSync(langDir).filter((f) => f.endsWith('.json')).sort();
    } catch (err) {
      loadErrors.push({ file: lang.name, error: err.message });
      logger.warn(`i18n: cannot read ${lang.name}/: ${err.message}`);
    }
    for (const file of files) {
      const namespace = path.basename(file, '.json');
      try {
        const json = JSON.parse(fs.readFileSync(path.join(langDir, file), 'utf8'));
        flatten(namespace, json, catalog);
      } catch (err) {
        // A broken translation file must not take the API down: log it and fall back to English.
        loadErrors.push({ file: path.join(lang.name, file), error: err.message });
        logger.warn(`i18n: skipping ${lang.name}/${file}: ${err.message}`);
      }
    }
    next.set(code, catalog);
  }
  catalogs = next;
  return catalogs;
}

loadTranslations();

/**
 * Maps any locale-ish value (`'hi'`, `'hi-IN'`, `'pt_BR'`, `'EN'`) to a supported code;
 * unsupported / missing → `'en'`.
 */
export function normalizeLocale(value) {
  if (typeof value !== 'string') return DEFAULT_LOCALE;
  const primary = value.trim().toLowerCase().split(/[-_]/)[0];
  return SUPPORTED_LOCALES.includes(primary) ? primary : DEFAULT_LOCALE;
}

export function isSupportedLocale(value) {
  return typeof value === 'string' && SUPPORTED_LOCALES.includes(value);
}

/**
 * Picks the best supported locale from an `Accept-Language` header
 * (`"hi-IN,hi;q=0.9,en;q=0.8"` → `'hi'`). Honors q-values; `q=0` entries are ignored.
 * @param {string|string[]|undefined|null} acceptLanguage
 * @returns {string} a SUPPORTED_LOCALES code (default `'en'`)
 */
export function pickLocale(acceptLanguage) {
  const header = Array.isArray(acceptLanguage) ? acceptLanguage.join(',') : acceptLanguage;
  if (typeof header !== 'string' || !header.trim()) return DEFAULT_LOCALE;
  const candidates = header
    .split(',')
    .slice(0, 20) // bound the work for hostile headers
    .map((part, index) => {
      const [tag, ...params] = part.trim().split(';');
      let q = 1;
      for (const p of params) {
        const [k, v] = p.trim().split('=');
        if (k === 'q') q = Number.isFinite(Number(v)) ? Number(v) : 0;
      }
      return { tag: tag.trim().toLowerCase(), q, index };
    })
    .filter((c) => c.tag && c.q > 0)
    .sort((a, b) => b.q - a.q || a.index - b.index);
  for (const { tag } of candidates) {
    if (tag === '*') return DEFAULT_LOCALE;
    const primary = tag.split(/[-_]/)[0];
    if (SUPPORTED_LOCALES.includes(primary)) return primary;
  }
  return DEFAULT_LOCALE;
}

function interpolate(text, vars) {
  if (!vars || typeof text !== 'string' || !text.includes('{')) return text;
  return text.replace(/\{(\w+)\}/g, (match, name) =>
    Object.hasOwn(vars, name) && vars[name] !== undefined && vars[name] !== null ? String(vars[name]) : match,
  );
}

function lookup(locale, key) {
  return catalogs.get(locale)?.get(key);
}

/** true when `key` exists in `locale` or in English. */
export function hasTranslation(key, locale = DEFAULT_LOCALE) {
  return lookup(normalizeLocale(locale), key) !== undefined || lookup(DEFAULT_LOCALE, key) !== undefined;
}

/**
 * Translate `key` for `locale` with `{placeholder}` interpolation.
 * Fallback: locale → English → the key itself.
 * @param {string} locale
 * @param {string} key   `<namespace>.<path>`
 * @param {Record<string, unknown>} [vars]
 */
export function t(locale, key, vars) {
  const code = normalizeLocale(locale);
  const text = lookup(code, key) ?? lookup(DEFAULT_LOCALE, key) ?? key;
  return interpolate(text, vars);
}

/** Like `t` but returns `fallback` (interpolated) instead of the key when nothing is found. */
export function tOr(locale, key, fallback, vars) {
  return hasTranslation(key, locale) ? t(locale, key, vars) : interpolate(fallback, vars);
}
