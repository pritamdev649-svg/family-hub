import { pickLocale } from '../lib/i18n.js';

/**
 * Sets `req.locale` (a supported language code) from `Accept-Language` and advertises it via
 * `Content-Language`. `req.localeFromHeader` tells whether the client sent the header;
 * `requireAuth` falls back to the user's stored locale when it did not.
 */
export function localeMiddleware(req, res, next) {
  const header = req.get('accept-language');
  req.locale = pickLocale(header);
  req.localeFromHeader = Boolean(header && header.trim());
  res.vary('Accept-Language');
  res.setHeader('Content-Language', req.locale);
  next();
}

/** Updates the request locale later in the chain (e.g. after loading the user). */
export function setRequestLocale(req, res, locale) {
  req.locale = locale;
  if (!res.headersSent) res.setHeader('Content-Language', locale);
}

export default localeMiddleware;
