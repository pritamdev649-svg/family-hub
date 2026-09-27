/* eslint-disable no-console */
/**
 * Minimal leveled logger. Never log personal data (emails, names, tokens, locations, bodies).
 *
 * LOG_LEVEL = debug | info | warn | error | silent (default: info; silent in tests unless
 * DEBUG_TESTS=1). Reads process.env directly so it works before config/env.js is loaded.
 */
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40, silent: 100 };

function threshold() {
  if (process.env.NODE_ENV === 'test' && !process.env.DEBUG_TESTS) return LEVELS.silent;
  const configured = String(process.env.LOG_LEVEL ?? '').toLowerCase();
  if (configured in LEVELS) return LEVELS[configured];
  return process.env.DEBUG ? LEVELS.debug : LEVELS.info;
}

function stamp() {
  return new Date().toISOString();
}

function make(level, sink) {
  return (...args) => {
    if (LEVELS[level] < threshold()) return false;
    sink(`[${stamp()}] ${level.toUpperCase()}`, ...args);
    return true;
  };
}

export const logger = {
  debug: make('debug', console.debug),
  info: make('info', console.log),
  warn: make('warn', console.warn),
  error: make('error', console.error),
};

export default logger;
