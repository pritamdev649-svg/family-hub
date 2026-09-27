import nodemailer from 'nodemailer';
import { env } from '../config/env.js';
import { hasTranslation, normalizeLocale, t } from '../lib/i18n.js';
import { logger } from '../lib/logger.js';

/**
 * E-mail sending (docs/06-BACKEND_GUIDE.md §3).
 *
 * Transports:
 *  - test        → nothing is sent; every mail is appended to the exported `outbox` array
 *                  (synchronously, so tests can assert right after the HTTP response).
 *  - SMTP_HOST   → nodemailer SMTP (pooled).
 *  - development without SMTP → the e-mail is printed to the console (OTP codes visible).
 *  - production without SMTP  → a warning is logged (no content, no address), nothing is sent.
 *
 * `sendMail` / `sendTemplate` never throw: failures are logged and reported as `{ sent: false }`
 * so a mail outage cannot break registration or password reset.
 */

/** Test outbox: `{ to, subject, text, html, template?, locale?, vars? }[]`. */
export const outbox = [];

let transporter;

export function isMailConfigured() {
  return Boolean(env.SMTP_HOST);
}

function getTransporter() {
  if (transporter !== undefined) return transporter;
  transporter = isMailConfigured()
    ? nodemailer.createTransport({
        host: env.SMTP_HOST,
        port: env.SMTP_PORT,
        secure: env.SMTP_SECURE,
        auth: env.SMTP_USER ? { user: env.SMTP_USER, pass: env.SMTP_PASS } : undefined,
        pool: true,
        maxConnections: 3,
        connectionTimeout: 10_000,
        greetingTimeout: 10_000,
        socketTimeout: 20_000,
      })
    : null;
  return transporter;
}

const HTML_ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => HTML_ESCAPES[c]);
}

/** Plain text → minimal, safe HTML (paragraphs + line breaks). */
export function textToHtml(text, { dir = 'ltr', lang = 'en' } = {}) {
  const paragraphs = String(text ?? '')
    .split(/\n{2,}/)
    .map((p) => `<p style="margin:0 0 16px">${escapeHtml(p).replace(/\n/g, '<br>')}</p>`)
    .join('');
  return (
    `<!doctype html><html lang="${escapeHtml(lang)}" dir="${dir}"><body style="margin:0;padding:24px;` +
    `font-family:-apple-system,Segoe UI,Roboto,Noto Sans,Arial,sans-serif;font-size:16px;line-height:1.5;color:#1f2937">` +
    `<div style="max-width:560px;margin:0 auto">${paragraphs}</div></body></html>`
  );
}

/**
 * Sends one e-mail.
 * @param {{ to: string, subject: string, text: string, html?: string }} mail
 * @returns {Promise<{ sent: boolean, messageId?: string }>}
 */
export async function sendMail({ to, subject, text, html, ...meta }) {
  if (!to || !subject) {
    logger.warn('sendMail called without recipient or subject');
    return { sent: false };
  }
  const message = { to, subject, text: text ?? '', html: html ?? textToHtml(text) };

  if (env.isTest) {
    outbox.push({ ...message, ...meta });
    return { sent: true, messageId: `test-${outbox.length}` };
  }

  const transport = getTransporter();
  if (!transport) {
    if (env.isProd) {
      logger.warn(`SMTP is not configured; e-mail "${meta.template ?? 'custom'}" was not sent`);
      return { sent: false };
    }
    logger.info(`\n----- E-MAIL (dev, not sent) -----\nTo: ${to}\nSubject: ${subject}\n\n${message.text}\n----------------------------------`);
    return { sent: true, messageId: 'console' };
  }

  try {
    const info = await transport.sendMail({ from: env.MAIL_FROM, ...message });
    return { sent: true, messageId: info?.messageId };
  } catch (err) {
    logger.error(`E-mail "${meta.template ?? 'custom'}" failed: ${err?.code ?? ''} ${err?.message ?? err}`);
    return { sent: false };
  }
}

const RTL_LOCALES = new Set(['ar']);

/**
 * Renders a localized e-mail from i18n keys.
 * `template` = `"<namespace>.<name>"` → keys `<namespace>.email.<name>.subject|text`
 * (e.g. `auth.verifyEmail` → `auth.email.verifyEmail.subject`). The body is wrapped with
 * `common.email.greeting` (when `vars.name` is set), `common.email.signature` and
 * `common.email.footer`. `vars.appName` defaults to APP_NAME.
 *
 * @returns {{ subject: string, text: string, html: string, locale: string }}
 */
export function renderTemplate({ locale, template, vars = {} }) {
  const code = normalizeLocale(locale);
  const dot = String(template ?? '').indexOf('.');
  if (dot <= 0) throw new Error(`Invalid e-mail template "${template}" (expected "<namespace>.<name>")`);
  const namespace = template.slice(0, dot);
  const name = template.slice(dot + 1);
  const allVars = { appName: env.APP_NAME, ...vars };
  const subjectKey = `${namespace}.email.${name}.subject`;
  const textKey = `${namespace}.email.${name}.text`;
  if (!hasTranslation(subjectKey, code) || !hasTranslation(textKey, code)) {
    logger.warn(`E-mail template "${template}" is missing translations (${subjectKey} / ${textKey})`);
  }
  const lines = [];
  if (allVars.name) lines.push(t(code, 'common.email.greeting', allVars));
  lines.push(t(code, textKey, allVars));
  lines.push(t(code, 'common.email.signature', allVars));
  lines.push(t(code, 'common.email.footer', allVars));
  const text = lines.filter(Boolean).join('\n\n');
  return {
    subject: t(code, subjectKey, allVars),
    text,
    html: textToHtml(text, { dir: RTL_LOCALES.has(code) ? 'rtl' : 'ltr', lang: code }),
    locale: code,
  };
}

/**
 * Sends a localized template e-mail (in the *recipient's* locale).
 * @param {{ to: string, locale?: string, template: string, vars?: object }} opts
 * @returns {Promise<{ sent: boolean, messageId?: string }>}
 */
export async function sendTemplate({ to, locale, template, vars = {} }) {
  let rendered;
  try {
    rendered = renderTemplate({ locale, template, vars });
  } catch (err) {
    logger.error(`E-mail template error: ${err.message}`);
    return { sent: false };
  }
  return sendMail({
    to,
    subject: rendered.subject,
    text: rendered.text,
    html: rendered.html,
    template,
    locale: rendered.locale,
    vars,
  });
}

/** Closes pooled SMTP connections (graceful shutdown). */
export function closeMailer() {
  if (transporter) transporter.close();
  transporter = undefined;
}
