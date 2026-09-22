import { Router } from 'express';
import { randomUUID } from 'node:crypto';
import {
  store,
  toWire,
  transactionsInMonth,
  MONTH_PATTERN,
} from '../data/store.js';
import {
  badRequest,
  notFound,
  validationFailed,
} from '../middleware/errors.js';

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

// --- query parsing ---------------------------------------------------------

const parseIntQuery = (raw, field) => {
  if (raw === undefined || raw === '') return undefined;
  const value = Number(raw);
  if (!Number.isInteger(value)) {
    throw validationFailed(`${field} must be a whole number of paise.`, {
      [field]: 'Use a whole number of paise.',
    });
  }
  return value;
};

const parseDateQuery = (raw, field) => {
  if (raw === undefined || raw === '') return undefined;
  const value = new Date(raw);
  if (Number.isNaN(value.getTime())) {
    throw validationFailed(`${field} is not a valid date.`, {
      [field]: 'Use an ISO-8601 date, for example 2026-09-01.',
    });
  }
  return value;
};

const encodeCursor = (txn) =>
  Buffer.from(`${txn.at.toISOString()}|${txn.id}`, 'utf8').toString('base64url');

const decodeCursor = (raw) => {
  if (raw === undefined || raw === '') return undefined;
  const decoded = Buffer.from(String(raw), 'base64url').toString('utf8');
  const separator = decoded.lastIndexOf('|');
  const at = separator === -1 ? NaN : Date.parse(decoded.slice(0, separator));
  if (Number.isNaN(at)) {
    throw badRequest(
      'CURSOR_INVALID',
      'That page link is no longer valid. Please reload the list.',
    );
  }
  return { at, id: decoded.slice(separator + 1) };
};

/** The feed is sorted at DESC, id DESC, so "after" means strictly smaller. */
const isAfterCursor = (txn, cursor) => {
  const at = txn.at.getTime();
  if (at !== cursor.at) return at < cursor.at;
  return txn.id < cursor.id;
};

export const transactionsRouter = Router();

// --- feed ------------------------------------------------------------------

transactionsRouter.get('/', (req, res) => {
  const { month, category, q, cursor } = req.query;

  if (month !== undefined && month !== '' && !MONTH_PATTERN.test(String(month))) {
    throw validationFailed('That month is not valid.', {
      month: 'Use the YYYY-MM format, for example 2026-09.',
    });
  }
  if (category !== undefined && category !== '' && !store.categoriesById.has(String(category))) {
    throw validationFailed('That category does not exist.', {
      category: 'Unknown category.',
    });
  }

  const minPaise = parseIntQuery(req.query.minPaise, 'minPaise');
  const maxPaise = parseIntQuery(req.query.maxPaise, 'maxPaise');
  const from = parseDateQuery(req.query.from, 'from');
  const to = parseDateQuery(req.query.to, 'to');
  const decodedCursor = decodeCursor(cursor);

  const rawLimit = req.query.limit;
  let limit = DEFAULT_LIMIT;
  if (rawLimit !== undefined && rawLimit !== '') {
    const parsed = Number(rawLimit);
    if (!Number.isInteger(parsed) || parsed < 1) {
      throw validationFailed('That page size is not valid.', {
        limit: `Use a whole number between 1 and ${MAX_LIMIT}.`,
      });
    }
    limit = Math.min(parsed, MAX_LIMIT);
  }

  const needle = typeof q === 'string' ? q.trim().toLowerCase() : '';
  const source =
    month === undefined || month === ''
      ? store.transactions
      : transactionsInMonth(String(month));

  const page = [];
  let nextCursor = null;

  for (const txn of source) {
    if (decodedCursor && !isAfterCursor(txn, decodedCursor)) continue;
    if (category && txn.category !== String(category)) continue;
    if (needle && !txn.merchantName.toLowerCase().includes(needle)) continue;
    // Amount filters compare magnitudes, so they match spends and refunds alike.
    const magnitude = Math.abs(txn.amountPaise);
    if (minPaise !== undefined && magnitude < minPaise) continue;
    if (maxPaise !== undefined && magnitude > maxPaise) continue;
    if (from && txn.at < from) continue;
    if (to && txn.at > to) continue;

    if (page.length === limit) {
      nextCursor = encodeCursor(page[page.length - 1]);
      break;
    }
    page.push(txn);
  }

  res.json({ items: page.map(toWire), nextCursor });
});

// --- undo (declared before /:id so the literal path wins) ------------------

transactionsRouter.post('/undo', (req, res) => {
  const { undoToken } = req.body ?? {};

  if (typeof undoToken !== 'string' || undoToken === '') {
    throw validationFailed('An undo token is required.', {
      undoToken: 'Required.',
    });
  }

  const journal = store.undoJournal.get(undoToken);
  if (!journal) {
    throw notFound(
      'UNDO_TOKEN_INVALID',
      'That change has already been undone, or the undo has expired.',
    );
  }
  store.undoJournal.delete(undoToken);

  for (const entry of journal.entries) {
    const txn = store.transactionsById.get(entry.id);
    if (txn) txn.category = entry.prevCategory;
  }

  if (journal.rule) {
    if (journal.rule.created) {
      store.merchantRules.delete(journal.rule.merchantKey);
    } else {
      store.merchantRules.set(journal.rule.merchantKey, {
        merchantKey: journal.rule.merchantKey,
        category: journal.rule.previousCategory,
      });
    }
  }

  res.json({ restoredIds: journal.entries.map((entry) => entry.id) });
});

// --- detail ----------------------------------------------------------------

transactionsRouter.get('/:id', (req, res) => {
  const txn = store.transactionsById.get(req.params.id);
  if (!txn) {
    throw notFound('TRANSACTION_NOT_FOUND', 'We could not find that transaction.');
  }
  res.json(toWire(txn));
});

// --- recategorise ----------------------------------------------------------

transactionsRouter.patch('/:id', (req, res) => {
  const { category, applyToMerchant } = req.body ?? {};

  if (typeof category !== 'string' || !store.categoriesById.has(category)) {
    throw validationFailed('That category does not exist.', {
      category: 'Unknown category.',
    });
  }
  if (applyToMerchant !== undefined && typeof applyToMerchant !== 'boolean') {
    throw validationFailed('applyToMerchant must be true or false.', {
      applyToMerchant: 'Use true or false.',
    });
  }

  const txn = store.transactionsById.get(req.params.id);
  if (!txn) {
    throw notFound('TRANSACTION_NOT_FOUND', 'We could not find that transaction.');
  }

  const spreadToMerchant = applyToMerchant === true;
  const targets = spreadToMerchant
    ? store.transactions.filter((item) => item.merchantKey === txn.merchantKey)
    : [txn];

  const entries = [];
  for (const target of targets) {
    if (target.category === category) continue;
    entries.push({ id: target.id, prevCategory: target.category });
    target.category = category;
  }

  let rule = null;
  if (spreadToMerchant) {
    const existing = store.merchantRules.get(txn.merchantKey) ?? null;
    rule = {
      merchantKey: txn.merchantKey,
      previousCategory: existing?.category ?? null,
      created: existing === null,
    };
    store.merchantRules.set(txn.merchantKey, {
      merchantKey: txn.merchantKey,
      category,
    });
  }

  const undoToken = randomUUID();
  store.undoJournal.set(undoToken, { entries, rule, createdAt: new Date() });

  res.json({
    updated: toWire(txn),
    changedIds: entries.map((entry) => entry.id),
    undoToken,
  });
});
