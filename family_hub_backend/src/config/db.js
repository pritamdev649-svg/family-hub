import mongoose from 'mongoose';
import { env } from './env.js';
import { logger } from '../lib/logger.js';

mongoose.set('strictQuery', true);

let listenersAttached = false;

function attachListeners() {
  if (listenersAttached) return;
  listenersAttached = true;
  const conn = mongoose.connection;
  conn.on('disconnected', () => logger.warn('MongoDB disconnected'));
  conn.on('reconnected', () => logger.info('MongoDB reconnected'));
  conn.on('error', (err) => logger.error(`MongoDB error: ${err.message}`));
}

/**
 * Connects mongoose (idempotent: an existing/pending connection is reused).
 * @param {string} [uri]
 * @returns {Promise<mongoose.Connection>}
 */
export async function connectDb(uri = env.MONGODB_URI) {
  attachListeners();
  if (mongoose.connection.readyState === 1) return mongoose.connection;
  await mongoose.connect(uri, {
    serverSelectionTimeoutMS: 10_000,
    // Uniqueness rules of the contract rely on indexes, so build them at startup.
    autoIndex: true,
    maxPoolSize: env.isTest ? 5 : 20,
  });
  logger.info(`MongoDB connected (${mongoose.connection.name})`);
  return mongoose.connection;
}

export async function disconnectDb() {
  if (mongoose.connection.readyState === 0) return;
  await mongoose.disconnect();
}

export function isDbUp() {
  return mongoose.connection.readyState === 1;
}
