import { Router } from 'express';
import { store } from '../data/store.js';
import { AppError, validationFailed } from './errors.js';

const MODES = new Set(['off', 'slow', 'error', 'offline']);
const MAX_LATENCY_MS = 30_000;

/** The chaos switch and sign-in stay reachable however broken the API is. */
const EXEMPT_PATHS = new Set(['/auth/login', '/__chaos']);

export const chaosMiddleware = (req, res, next) => {
  const { mode, latencyMs, failRate } = store.chaos;
  if (mode === 'off' || EXEMPT_PATHS.has(req.path) || req.method === 'OPTIONS') {
    return next();
  }

  if (mode === 'offline') {
    req.socket.destroy();
    return;
  }

  if (mode === 'slow') {
    setTimeout(next, latencyMs);
    return;
  }

  if (mode === 'error') {
    if (Math.random() < failRate) {
      return next(
        new AppError(
          503,
          'UPSTREAM_UNAVAILABLE',
          'We cannot reach the bank right now. Please try again in a moment.',
        ),
      );
    }
    return next();
  }

  next();
};

export const chaosRouter = Router();

chaosRouter.get('/', (_req, res) => {
  res.json({ ...store.chaos });
});

chaosRouter.post('/', (req, res) => {
  const { mode, latencyMs, failRate } = req.body ?? {};
  const details = {};

  if (mode !== undefined && (typeof mode !== 'string' || !MODES.has(mode))) {
    details.mode = 'Use one of: off, slow, error, offline.';
  }
  if (
    latencyMs !== undefined &&
    (!Number.isInteger(latencyMs) || latencyMs < 0 || latencyMs > MAX_LATENCY_MS)
  ) {
    details.latencyMs = `Use a whole number of milliseconds between 0 and ${MAX_LATENCY_MS}.`;
  }
  if (
    failRate !== undefined &&
    (typeof failRate !== 'number' ||
      Number.isNaN(failRate) ||
      failRate < 0 ||
      failRate > 1)
  ) {
    details.failRate = 'Use a number between 0 and 1.';
  }
  if (Object.keys(details).length > 0) {
    throw validationFailed('That chaos configuration is not valid.', details);
  }

  store.chaos = {
    mode: mode ?? store.chaos.mode,
    latencyMs: latencyMs ?? store.chaos.latencyMs,
    failRate: failRate ?? store.chaos.failRate,
  };

  res.json({ ...store.chaos });
});
