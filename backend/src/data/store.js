import { validationFailed } from '../middleware/errors.js';

/**
 * The whole "database". Everything lives in process memory and is rebuilt from
 * the deterministic seed on boot — there is no persistence by design.
 */
export const store = {
  categories: [],
  categoriesById: new Map(),
  merchants: [],
  transactions: [], // sorted: at DESC, then id DESC
  transactionsById: new Map(),
  transactionsByMonth: new Map(), // 'YYYY-MM' -> Transaction[]
  budgets: new Map(), // 'category|month' -> Budget
  merchantRules: new Map(), // merchantKey -> { merchantKey, category }
  tokens: new Map(), // token -> user
  undoJournal: new Map(), // undoToken -> journal entry
  idempotency: new Map(), // key -> { status, body, bodyHash }
  chaos: { mode: 'off', latencyMs: 0, failRate: 0 },
  seeded: false,
};

// --- month helpers ---------------------------------------------------------

export const MONTH_PATTERN = /^\d{4}-\d{2}$/;

export const monthKeyOf = (date) =>
  `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;

export const dayKeyOf = (date) => date.toISOString().slice(0, 10);

export const currentMonthKey = () => monthKeyOf(new Date());

export const shiftMonthKey = (monthKey, delta) => {
  const [year, month] = monthKey.split('-').map(Number);
  return monthKeyOf(new Date(Date.UTC(year, month - 1 + delta, 1)));
};

export const prevMonthKey = (monthKey) => shiftMonthKey(monthKey, -1);

/** `?month=` is optional everywhere and defaults to the current month. */
export const monthFromQuery = (raw) => {
  if (raw === undefined || raw === '') return currentMonthKey();
  if (typeof raw !== 'string' || !MONTH_PATTERN.test(raw)) {
    throw validationFailed('That month is not valid.', {
      month: 'Use the YYYY-MM format, for example 2026-09.',
    });
  }
  return raw;
};

// --- reads -----------------------------------------------------------------

export const transactionsInMonth = (monthKey) =>
  store.transactionsByMonth.get(monthKey) ?? [];

export const toWire = (txn) => ({
  id: txn.id,
  merchantRaw: txn.merchantRaw,
  merchantName: txn.merchantName,
  merchantKey: txn.merchantKey,
  category: txn.category,
  amountPaise: txn.amountPaise,
  at: txn.at.toISOString(),
  mode: txn.mode,
});

/** Spend is the negated sum: debits are negative, refunds positive. */
export const spentPaiseOf = (transactions) =>
  -transactions.reduce((sum, txn) => sum + txn.amountPaise, 0);

export const spentForCategory = (category, monthKey) =>
  spentPaiseOf(
    transactionsInMonth(monthKey).filter((txn) => txn.category === category),
  );

export const summarize = (monthKey) => {
  const items = transactionsInMonth(monthKey);
  const byCategory = {};
  const byDayMap = new Map();

  for (const txn of items) {
    byCategory[txn.category] = (byCategory[txn.category] ?? 0) - txn.amountPaise;
    const day = dayKeyOf(txn.at);
    byDayMap.set(day, (byDayMap.get(day) ?? 0) - txn.amountPaise);
  }

  return {
    month: monthKey,
    totalPaise: spentPaiseOf(items),
    prevTotalPaise: spentPaiseOf(transactionsInMonth(prevMonthKey(monthKey))),
    byCategory,
    byDay: [...byDayMap.entries()]
      .map(([date, paise]) => ({ date, paise }))
      .sort((a, b) => a.date.localeCompare(b.date)),
  };
};

export const merchantAggregates = (monthKey) => {
  const grouped = new Map();

  for (const txn of transactionsInMonth(monthKey)) {
    let entry = grouped.get(txn.merchantKey);
    if (!entry) {
      entry = {
        merchantKey: txn.merchantKey,
        merchantName: txn.merchantName,
        totalPaise: 0,
        visits: 0,
        byCategory: new Map(),
      };
      grouped.set(txn.merchantKey, entry);
    }
    entry.totalPaise -= txn.amountPaise;
    entry.visits += 1;
    entry.byCategory.set(
      txn.category,
      (entry.byCategory.get(txn.category) ?? 0) - txn.amountPaise,
    );
  }

  return [...grouped.values()]
    .map((entry) => ({
      merchantKey: entry.merchantKey,
      merchantName: entry.merchantName,
      totalPaise: entry.totalPaise,
      visits: entry.visits,
      avgPaise: entry.visits === 0 ? 0 : Math.round(entry.totalPaise / entry.visits),
      topCategory: [...entry.byCategory.entries()].sort(
        (a, b) => b[1] - a[1] || a[0].localeCompare(b[0]),
      )[0][0],
    }))
    .sort((a, b) => b.totalPaise - a.totalPaise || a.merchantKey.localeCompare(b.merchantKey));
};

// --- budgets ---------------------------------------------------------------

export const budgetKey = (category, monthKey) => `${category}|${monthKey}`;

export const budgetToWire = (budget) => ({
  category: budget.category,
  month: budget.month,
  limitPaise: budget.limitPaise,
  spentPaise: spentForCategory(budget.category, budget.month),
});

export const budgetsForMonth = (monthKey) =>
  [...store.budgets.values()]
    .filter((budget) => budget.month === monthKey)
    .sort((a, b) => a.category.localeCompare(b.category))
    .map(budgetToWire);

export const upsertBudget = (category, monthKey, limitPaise) => {
  const budget = { category, month: monthKey, limitPaise };
  store.budgets.set(budgetKey(category, monthKey), budget);
  return budgetToWire(budget);
};

// --- indexing --------------------------------------------------------------

/** Rebuilds the derived indexes. Called once, at the end of seeding. */
export const reindex = () => {
  store.transactions.sort(
    (a, b) => b.at - a.at || (a.id < b.id ? 1 : a.id > b.id ? -1 : 0),
  );
  store.transactionsById = new Map(store.transactions.map((txn) => [txn.id, txn]));
  store.transactionsByMonth = new Map();
  for (const txn of store.transactions) {
    const key = monthKeyOf(txn.at);
    const bucket = store.transactionsByMonth.get(key);
    if (bucket) bucket.push(txn);
    else store.transactionsByMonth.set(key, [txn]);
  }
  store.categoriesById = new Map(store.categories.map((cat) => [cat.id, cat]));
};
