import express from 'express';
import { pathToFileURL } from 'node:url';

import { store } from './data/store.js';
import { seedStore } from './data/seed.js';
import { requireAuth } from './middleware/auth.js';
import { idempotency } from './middleware/idempotency.js';
import { chaosMiddleware, chaosRouter } from './middleware/chaos.js';
import { errorHandler, notFoundHandler } from './middleware/errors.js';
import { authRouter } from './routes/auth.js';
import { budgetsRouter } from './routes/budgets.js';
import { categoriesRouter } from './routes/categories.js';
import { insightsRouter } from './routes/insights.js';
import { merchantsRouter } from './routes/merchants.js';
import { summaryRouter } from './routes/summary.js';
import { transactionsRouter } from './routes/transactions.js';

/** Wide open: this is a local mock API, never a deployed service. */
const cors = (req, res, next) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.set(
    'Access-Control-Allow-Headers',
    'Authorization,Content-Type,Idempotency-Key',
  );
  res.set('Access-Control-Expose-Headers', 'Idempotency-Replayed');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
};

/** Ids never reach the log line — only the shape of the path. */
const redactPath = (path) =>
  path
    .split('/')
    .map((segment) =>
      /^(txn|cat|mer|usr)_/.test(segment) || segment.length > 16 ? ':id' : segment,
    )
    .join('/');

const requestLogger = (req, res, next) => {
  const startedAt = process.hrtime.bigint();
  // Captured now: a router rewrites req.url while it dispatches, and 'finish'
  // can fire before it is restored.
  const path = redactPath(req.path);
  res.on('finish', () => {
    const ms = Number(process.hrtime.bigint() - startedAt) / 1e6;
    console.log(`${req.method} ${path} ${res.statusCode} ${ms.toFixed(1)}ms`);
  });
  next();
};

export const createApp = () => {
  if (!store.seeded) seedStore();

  const app = express();
  app.disable('x-powered-by');

  app.use(cors);
  app.use(express.json({ limit: '1mb' }));
  app.use(requestLogger);

  app.get('/health', (_req, res) => res.json({ status: 'ok' }));

  // Chaos runs first so it can break everything downstream, but it never
  // touches its own switch or sign-in.
  app.use(chaosMiddleware);
  app.use('/__chaos', chaosRouter);

  app.use(requireAuth);
  app.use(idempotency);

  app.use('/auth', authRouter);
  app.use('/transactions', transactionsRouter);
  app.use('/summary', summaryRouter);
  app.use('/budgets', budgetsRouter);
  app.use('/merchants', merchantsRouter);
  app.use('/insights', insightsRouter);
  app.use('/categories', categoriesRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
};

const isEntryPoint =
  process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isEntryPoint) {
  const port = Number(process.env.PORT ?? 3000);
  const app = createApp();
  app.listen(port, () => {
    console.log(
      `SpendWise mock API on http://localhost:${port} — ` +
        `${store.transactions.length} transactions across ${store.transactionsByMonth.size} months, ` +
        `${store.merchants.length} merchants, sign in with any email and "password123".`,
    );
  });
}
