import { store } from '../data/store.js';
import { unauthorized } from './errors.js';

/** Routes that are reachable without a bearer token. */
const PUBLIC_PATHS = new Set(['/auth/login', '/__chaos', '/health']);

export const requireAuth = (req, _res, next) => {
  if (req.method === 'OPTIONS' || PUBLIC_PATHS.has(req.path)) return next();

  const header = req.get('authorization') ?? '';
  const [scheme, token] = header.split(' ');

  if (scheme?.toLowerCase() !== 'bearer' || !token || !store.tokens.has(token)) {
    return next(
      unauthorized(
        'AUTH_TOKEN_INVALID',
        'Your session has ended. Please sign in again.',
      ),
    );
  }

  req.user = store.tokens.get(token);
  next();
};
