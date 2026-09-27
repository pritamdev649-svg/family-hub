import { createApp } from '../src/app.js';
import { connectDb } from '../src/config/db.js';

let app;

export default async function handler(req, res) {
  await connectDb();
  if (!app) {
    app = createApp();
  }
  return app(req, res);
}
