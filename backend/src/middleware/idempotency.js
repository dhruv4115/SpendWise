import { createHash } from 'node:crypto';
import { store } from '../data/store.js';
import { badRequest, conflict } from './errors.js';

const MUTATING = new Set(['POST', 'PUT', 'PATCH']);

/** Sign-in and the chaos switch accept a key but do not demand one. */
const KEY_OPTIONAL = new Set(['/auth/login', '/__chaos']);

/** Key order must not change the fingerprint, so serialise deterministically. */
const canonical = (value) => {
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null';
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  return `{${Object.keys(value)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`)
    .join(',')}}`;
};

const fingerprint = (req) =>
  createHash('sha256')
    .update(`${req.method} ${req.path} ${canonical(req.body ?? null)}`)
    .digest('hex');

export const idempotency = (req, res, next) => {
  if (!MUTATING.has(req.method)) return next();

  const key = req.get('idempotency-key');
  if (!key) {
    if (KEY_OPTIONAL.has(req.path)) return next();
    return next(
      badRequest(
        'IDEMPOTENCY_KEY_REQUIRED',
        'This request must carry an Idempotency-Key header.',
      ),
    );
  }

  const bodyHash = fingerprint(req);
  const stored = store.idempotency.get(key);

  if (stored) {
    if (stored.bodyHash !== bodyHash) {
      return next(
        conflict(
          'IDEMPOTENCY_CONFLICT',
          'This Idempotency-Key was already used for a different request.',
        ),
      );
    }
    res.set('Idempotency-Replayed', 'true');
    return res.status(stored.status).json(stored.body);
  }

  // Record the first successful outcome so a retry replays it verbatim.
  // Failures are not recorded: the caller may fix the request and retry.
  const sendJson = res.json.bind(res);
  res.json = (body) => {
    if (res.statusCode >= 200 && res.statusCode < 400) {
      store.idempotency.set(key, { status: res.statusCode, body, bodyHash });
    }
    return sendJson(body);
  };

  next();
};
