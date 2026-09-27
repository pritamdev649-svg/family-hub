import { z } from 'zod';

/**
 * `GET /dashboard` takes no input (docs/03-API_CONTRACT.md §11). Like every other query schema,
 * unknown keys are stripped, not rejected: cache-busting parameters added by proxies / HTTP clients
 * (`?_=1700000000`) keep working, and nothing in the query can widen the scope — the family always
 * comes from the access token (`?familyId=` or `?month=` are ignored).
 */
export const dashboardQuery = z.object({});
