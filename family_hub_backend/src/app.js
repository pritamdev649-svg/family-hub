import compression from 'compression';
import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import { env } from './config/env.js';
import { JSON_BODY_LIMIT } from './lib/constants.js';
import { errorHandler, notFoundHandler } from './middleware/error.js';
import { localeMiddleware } from './middleware/locale.js';
import { globalLimiter } from './middleware/rateLimit.js';
import apiRouter from './routes/index.js';

export const API_PREFIX = '/api/v1';

/** Access-log URL without personal identifiers (the FCM token in `/me/devices/:token`). */
export function redactUrl(url = '') {
  return String(url).replace(/(\/me\/devices\/)[^/?#]+/, '$1:token');
}

morgan.token('safe-url', (req) => redactUrl(req.originalUrl ?? req.url));
const LOG_FORMAT = ':method :safe-url :status :response-time ms - :res[content-length]';

function corsOptions() {
  const origins = env.corsOrigins;
  const allowAll = origins.length === 0 || origins.includes('*');
  return {
    // Bearer tokens only — no cookies, so credentials are never needed.
    origin: allowAll ? '*' : (origin, cb) => cb(null, !origin || origins.includes(origin)),
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    exposedHeaders: ['Content-Language', 'Retry-After', 'RateLimit', 'RateLimit-Policy'],
    maxAge: 600,
  };
}

/**
 * Builds the Express application (no DB connection, no listen — see server.js).
 * Safe to call several times (tests create one app per file).
 */
export function createApp() {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', env.trustProxy);

  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(cors(corsOptions()));
  app.use(compression());
  if (!env.isTest) app.use(morgan(LOG_FORMAT));
  // Before the body parser so malformed-JSON / too-large errors are localized as well.
  app.use(localeMiddleware);
  app.use(globalLimiter);
  app.use(express.json({ limit: JSON_BODY_LIMIT }));

  app.get('/delete-account', (req, res) => {
    res.send(`
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Delete FamilyHub Account</title>
        <style>
          body { font-family: system-ui, -apple-system, sans-serif; max-width: 600px; margin: 40px auto; padding: 20px; line-height: 1.6; color: #333; }
          h1 { color: #d32f2f; }
          .container { background: #f9f9f9; padding: 30px; border-radius: 8px; border: 1px solid #eee; }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>Account Deletion Instructions</h1>
          <p>To delete your FamilyHub account and all associated data, please follow these steps from within the mobile app:</p>
          <ol>
            <li>Open the <strong>FamilyHub</strong> app on your device.</li>
            <li>Go to the <strong>Settings</strong> tab.</li>
            <li>Tap on <strong>Account & Privacy</strong>.</li>
            <li>Select <strong>Delete Account</strong> and follow the on-screen prompts.</li>
          </ol>
          <p><em>Note: If you are the only member of your family workspace, the entire workspace and its data (tasks, ledger, goals, notices) will be permanently deleted.</em></p>
        </div>
      </body>
      </html>
    `);
  });

  app.use(API_PREFIX, apiRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}

export default createApp;
