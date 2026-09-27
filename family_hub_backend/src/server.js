import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createApp } from './app.js';
import { env } from './config/env.js';
import { connectDb, disconnectDb } from './config/db.js';
import { logger } from './lib/logger.js';
import { closeMailer } from './services/mailer.js';
import { flushPushes, initPush } from './services/push.js';

/**
 * Process entry point: connect MongoDB → init push → listen, with graceful shutdown on
 * SIGINT/SIGTERM (stop accepting connections, finish in-flight requests and pushes,
 * close DB/SMTP, exit; forced exit after 10 s).
 */

const SHUTDOWN_TIMEOUT_MS = 10_000;

/**
 * Starts the API. Also used by scripts/dev-memory.js.
 * @param {{ port?: number, mongoUri?: string, onShutdown?: () => Promise<void>|void }} [opts]
 *        `onShutdown` runs after the DB is disconnected, right before the process exits.
 * @returns {Promise<{ server: import('node:http').Server, shutdown: (signal?: string, code?: number) => Promise<void> }>}
 */
export async function startServer({ port = env.PORT, mongoUri, onShutdown } = {}) {
  await connectDb(mongoUri);
  initPush();

  const app = createApp();
  const server = app.listen(port);
  await new Promise((resolve, reject) => {
    server.once('listening', resolve);
    server.once('error', reject);
  });
  // Slightly above typical load-balancer idle timeouts to avoid 502s on reused sockets.
  server.keepAliveTimeout = 65_000;
  server.headersTimeout = 66_000;
  logger.info(`${env.APP_NAME} API v${env.version} listening on http://localhost:${port}/api/v1 (${env.NODE_ENV})`);
  if (env.isProd && env.corsOrigins.includes('*')) logger.warn('CORS_ORIGINS is "*" in production');

  let shuttingDown = false;
  async function shutdown(signal = 'shutdown', code = 0) {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info(`${signal} received, shutting down…`);
    const timer = setTimeout(() => {
      logger.error('Graceful shutdown timed out, forcing exit');
      process.exit(1);
    }, SHUTDOWN_TIMEOUT_MS);
    timer.unref();
    try {
      await new Promise((resolve) => {
        server.close(() => resolve());
        server.closeIdleConnections?.();
      });
      await flushPushes();
      closeMailer();
      await disconnectDb();
      if (onShutdown) await onShutdown();
      logger.info('Shutdown complete');
    } catch (err) {
      logger.error(`Error during shutdown: ${err?.message ?? err}`);
      code = code || 1;
    } finally {
      clearTimeout(timer);
      process.exit(code);
    }
  }

  process.once('SIGINT', () => void shutdown('SIGINT'));
  process.once('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('unhandledRejection', (reason) => {
    logger.error('Unhandled promise rejection:', reason instanceof Error ? reason.stack : reason);
  });
  process.on('uncaughtException', (err) => {
    logger.error('Uncaught exception:', err?.stack ?? err);
    void shutdown('uncaughtException', 1);
  });

  return { server, shutdown };
}

// Run when executed directly (`node src/server.js`), not when imported.
function isMainModule() {
  try {
    return Boolean(process.argv[1]) && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMainModule()) {
  startServer().catch((err) => {
    logger.error(`Failed to start: ${err?.stack ?? err}`);
    process.exit(1);
  });
}
