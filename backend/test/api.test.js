import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import request from 'supertest';

import { createApp } from '../src/server.js';
import { monthKeyOf, shiftMonthKey } from '../src/data/store.js';

const app = createApp();

const CURRENT_MONTH = monthKeyOf(new Date());
const BIG_MONTH = shiftMonthKey(CURRENT_MONTH, -2);
const EMPTY_MONTH = shiftMonthKey(CURRENT_MONTH, -4);
const SMALL_MONTH = shiftMonthKey(CURRENT_MONTH, -5);

let bearer = '';

before(async () => {
  const res = await request(app)
    .post('/auth/login')
    .send({ email: 'asha@example.com', password: 'password123' });
  assert.equal(res.status, 200);
  bearer = res.body.token;
});

/** Synchronous on purpose: supertest's Test is a thenable, so an async wrapper
 *  would fire the request before the caller could chain .set()/.send(). */
const authed = (method, path) =>
  request(app)[method](path).set('Authorization', `Bearer ${bearer}`);

/** Pages through the whole feed for a query, following nextCursor. */
const collect = async (query, limit = 200) => {
  const items = [];
  let cursor = null;
  do {
    const url = `/transactions?${query}&limit=${limit}${cursor ? `&cursor=${cursor}` : ''}`;
    const res = await (authed('get', url));
    assert.equal(res.status, 200, JSON.stringify(res.body));
    items.push(...res.body.items);
    cursor = res.body.nextCursor;
  } while (cursor);
  return items;
};

// --- auth ------------------------------------------------------------------

test('login rejects bad credentials with 401 AUTH_INVALID_CREDENTIALS', async () => {
  const res = await request(app)
    .post('/auth/login')
    .send({ email: 'asha@example.com', password: 'wrong-password' });

  assert.equal(res.status, 401);
  assert.equal(res.body.error.code, 'AUTH_INVALID_CREDENTIALS');
  assert.ok(res.body.error.traceId);
  assert.ok(res.body.error.message.length > 0);
});

test('login returns a token and the user', async () => {
  const res = await request(app)
    .post('/auth/login')
    .send({ email: 'asha.rao@example.com', password: 'password123' });

  assert.equal(res.status, 200);
  assert.match(res.body.token, /^[0-9a-f]{48}$/);
  assert.equal(res.body.user.email, 'asha.rao@example.com');
  assert.equal(res.body.user.name, 'Asha Rao');
  assert.ok(res.body.user.id.startsWith('usr_'));
});

test('a protected route without a bearer token is 401 AUTH_TOKEN_INVALID', async () => {
  const res = await request(app).get('/transactions');

  assert.equal(res.status, 401);
  assert.equal(res.body.error.code, 'AUTH_TOKEN_INVALID');
});

// --- paging ----------------------------------------------------------------

test('cursor paging returns disjoint pages and a null final cursor', async () => {
  const query = `month=${SMALL_MONTH}&category=education`;
  const everything = await collect(query);
  assert.ok(everything.length > 6, 'need enough rows to page through');

  const seen = new Set();
  const paged = [];
  let cursor = null;
  let requests = 0;

  do {
    const url = `/transactions?${query}&limit=3${cursor ? `&cursor=${cursor}` : ''}`;
    const res = await (authed('get', url));
    assert.equal(res.status, 200);
    assert.ok(res.body.items.length <= 3);

    for (const item of res.body.items) {
      assert.ok(!seen.has(item.id), `page overlap on ${item.id}`);
      seen.add(item.id);
      paged.push(item);
    }
    cursor = res.body.nextCursor;
    requests += 1;
  } while (cursor && requests < 500);

  assert.equal(cursor, null, 'the last page must report a null cursor');
  assert.deepEqual(
    paged.map((item) => item.id),
    everything.map((item) => item.id),
  );
});

// --- recategorise + undo ---------------------------------------------------

test('applyToMerchant recategorises every matching transaction and undo restores them', async () => {
  const before = await collect(`q=Swiggy`);
  assert.ok(before.length > 50, 'expected many Swiggy rows across months');
  assert.ok(new Set(before.map((t) => t.merchantKey)).size === 1);
  assert.equal(before[0].merchantKey, 'swiggy');
  const months = new Set(before.map((t) => t.at.slice(0, 7)));
  assert.ok(months.size > 1, 'the rule must span more than one month');

  const patch = await (authed('patch', `/transactions/${before[0].id}`))
    .set('Idempotency-Key', randomUUID())
    .send({ category: 'travel', applyToMerchant: true });

  assert.equal(patch.status, 200);
  assert.equal(patch.body.updated.category, 'travel');
  assert.ok(patch.body.undoToken);
  assert.equal(
    patch.body.changedIds.length,
    before.filter((t) => t.category !== 'travel').length,
  );

  const after = await collect(`q=Swiggy`);
  assert.ok(after.every((t) => t.category === 'travel'));

  const undo = await (authed('post', '/transactions/undo'))
    .set('Idempotency-Key', randomUUID())
    .send({ undoToken: patch.body.undoToken });

  assert.equal(undo.status, 200);
  assert.equal(undo.body.restoredIds.length, patch.body.changedIds.length);

  const restored = await collect(`q=Swiggy`);
  assert.deepEqual(
    restored.map((t) => [t.id, t.category]),
    before.map((t) => [t.id, t.category]),
  );

  const reuse = await (authed('post', '/transactions/undo'))
    .set('Idempotency-Key', randomUUID())
    .send({ undoToken: patch.body.undoToken });
  assert.equal(reuse.status, 404);
  assert.equal(reuse.body.error.code, 'UNDO_TOKEN_INVALID');
});

test('an unknown category is 422 VALIDATION_FAILED with details.category', async () => {
  const feed = await (authed('get', `/transactions?limit=1`));
  const res = await (authed('patch', `/transactions/${feed.body.items[0].id}`))
    .set('Idempotency-Key', randomUUID())
    .send({ category: 'crypto', applyToMerchant: false });

  assert.equal(res.status, 422);
  assert.equal(res.body.error.code, 'VALIDATION_FAILED');
  assert.ok(res.body.error.details.category);
});

// --- summary ---------------------------------------------------------------

test('a refund reduces its category total in the summary', async () => {
  const items = await collect(`month=${BIG_MONTH}&category=food`);
  const refunds = items.filter((item) => item.amountPaise > 0);
  assert.ok(refunds.length > 0, 'the seed must contain refunds');

  const summary = await (authed('get', `/summary?month=${BIG_MONTH}`));
  assert.equal(summary.status, 200);

  const spent = -items.reduce((sum, item) => sum + item.amountPaise, 0);
  const withoutRefunds = -items
    .filter((item) => item.amountPaise < 0)
    .reduce((sum, item) => sum + item.amountPaise, 0);

  assert.equal(summary.body.byCategory.food, spent);
  assert.ok(spent < withoutRefunds, 'refunds must pull the category total down');
  assert.equal(
    summary.body.totalPaise,
    Object.values(summary.body.byCategory).reduce((a, b) => a + b, 0),
  );
});

test('an empty month returns a zeroed summary', async () => {
  const res = await (authed('get', `/summary?month=${EMPTY_MONTH}`));

  assert.equal(res.status, 200);
  assert.equal(res.body.month, EMPTY_MONTH);
  assert.equal(res.body.totalPaise, 0);
  assert.deepEqual(res.body.byCategory, {});
  assert.deepEqual(res.body.byDay, []);

  const feed = await (authed('get', `/transactions?month=${EMPTY_MONTH}`));
  assert.deepEqual(feed.body.items, []);
  assert.equal(feed.body.nextCursor, null);
});

// --- budgets ---------------------------------------------------------------

test('a negative budget limit is 422 with details.limitPaise', async () => {
  const res = await (authed('put', '/budgets'))
    .set('Idempotency-Key', randomUUID())
    .send({ category: 'food', month: CURRENT_MONTH, limitPaise: -1 });

  assert.equal(res.status, 422);
  assert.equal(res.body.error.code, 'VALIDATION_FAILED');
  assert.ok(res.body.error.details.limitPaise);
});

test('a saved budget counts the whole month, not just later spending', async () => {
  const res = await (authed('put', '/budgets'))
    .set('Idempotency-Key', randomUUID())
    .send({ category: 'health', month: BIG_MONTH, limitPaise: 5_000_00 });

  assert.equal(res.status, 200);
  const summary = await (authed('get', `/summary?month=${BIG_MONTH}`));
  assert.equal(res.body.spentPaise, summary.body.byCategory.health);
});

// --- idempotency -----------------------------------------------------------

test('replaying an idempotency key returns the identical body', async () => {
  const key = randomUUID();
  const body = { category: 'travel', month: CURRENT_MONTH, limitPaise: 12_345_00 };

  const first = await (authed('put', '/budgets'))
    .set('Idempotency-Key', key)
    .send(body);
  const replay = await (authed('put', '/budgets'))
    .set('Idempotency-Key', key)
    .send(body);

  assert.equal(first.status, 200);
  assert.equal(replay.status, 200);
  assert.equal(replay.headers['idempotency-replayed'], 'true');
  assert.equal(first.headers['idempotency-replayed'], undefined);
  assert.deepEqual(replay.body, first.body);
});

test('the same idempotency key with a different body is 409', async () => {
  const key = randomUUID();

  const first = await (authed('put', '/budgets'))
    .set('Idempotency-Key', key)
    .send({ category: 'bills', month: CURRENT_MONTH, limitPaise: 90_000_00 });
  assert.equal(first.status, 200);

  const conflicting = await (authed('put', '/budgets'))
    .set('Idempotency-Key', key)
    .send({ category: 'bills', month: CURRENT_MONTH, limitPaise: 95_000_00 });

  assert.equal(conflicting.status, 409);
  assert.equal(conflicting.body.error.code, 'IDEMPOTENCY_CONFLICT');
});

test('a mutating call without an idempotency key is 400', async () => {
  const res = await (authed('put', '/budgets')).send({
    category: 'food',
    month: CURRENT_MONTH,
    limitPaise: 1_000_00,
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'IDEMPOTENCY_KEY_REQUIRED');
});

// --- reference data --------------------------------------------------------

test('categories, merchants and insights answer for a month', async () => {
  const categories = await (authed('get', '/categories'));
  assert.equal(categories.body.items.length, 10);
  assert.ok(categories.body.items.every((c) => /^#[0-9A-F]{6}$/i.test(c.color)));

  const merchants = await (authed('get', `/merchants?month=${BIG_MONTH}`));
  const totals = merchants.body.items.map((m) => m.totalPaise);
  assert.deepEqual(totals, [...totals].sort((a, b) => b - a));
  assert.ok(merchants.body.items.every((m) => m.visits > 0 && m.topCategory));

  const insights = await (authed('get', `/insights?month=${BIG_MONTH}`));
  assert.equal(insights.body.items.length, 3);
  assert.ok(
    insights.body.items.every(
      (card) =>
        card.id &&
        card.title &&
        card.body &&
        ['info', 'warning', 'critical'].includes(card.severity) &&
        typeof card.dismissible === 'boolean',
    ),
  );
});
