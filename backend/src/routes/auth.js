import { Router } from 'express';
import { createHash, randomBytes } from 'node:crypto';
import { store } from '../data/store.js';
import { unauthorized } from '../middleware/errors.js';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const DEMO_PASSWORD = 'password123';

const displayNameFor = (email) =>
  email
    .split('@')[0]
    .split(/[._+-]+/)
    .filter(Boolean)
    .map((part) => part[0].toUpperCase() + part.slice(1).toLowerCase())
    .join(' ') || 'SpendWise Customer';

export const authRouter = Router();

authRouter.post('/login', (req, res) => {
  const { email, password } = req.body ?? {};

  const valid =
    typeof email === 'string' &&
    typeof password === 'string' &&
    EMAIL_PATTERN.test(email) &&
    password === DEMO_PASSWORD;

  if (!valid) {
    throw unauthorized(
      'AUTH_INVALID_CREDENTIALS',
      'That email or password is not right.',
    );
  }

  const token = randomBytes(24).toString('hex');
  const user = {
    id: `usr_${createHash('sha256').update(email.toLowerCase()).digest('hex').slice(0, 12)}`,
    name: displayNameFor(email),
    email,
  };

  store.tokens.set(token, user);
  res.json({ token, user });
});
