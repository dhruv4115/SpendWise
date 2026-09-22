import {
  store,
  monthKeyOf,
  reindex,
  budgetKey,
  spentForCategory,
} from './store.js';

export const SEED = 20260922;

/**
 * Linear congruential generator (Numerical Recipes constants). Deterministic
 * and dependency-free: the same seed always produces the same dataset, so a
 * screenshot taken today still matches the data tomorrow morning.
 */
const createRng = (seed) => {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(1664525, state) + 1013904223) >>> 0;
    return state / 4294967296;
  };
};

const intBetween = (rng, min, max) => min + Math.floor(rng() * (max - min + 1));

const pick = (rng, items) => items[Math.floor(rng() * items.length)];

const weightedPick = (rng, items, weightOf) => {
  const total = items.reduce((sum, item) => sum + weightOf(item), 0);
  let threshold = rng() * total;
  for (const item of items) {
    threshold -= weightOf(item);
    if (threshold <= 0) return item;
  }
  return items[items.length - 1];
};

/**
 * Card networks send noisy descriptors. "SWIGGY*1234", "SWIGGY *8891" and
 * "swiggy-2201" are all the same merchant: uppercase, strip digits / * / -,
 * collapse whitespace, trim, lowercase.
 */
export const normalizeMerchant = (raw) =>
  raw
    .toUpperCase()
    .replace(/[0-9*-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();

// --- static reference data -------------------------------------------------

const CATEGORIES = [
  { id: 'food', name: 'Food & Dining', icon: 'restaurant', color: '#E8590C' },
  { id: 'groceries', name: 'Groceries', icon: 'shopping_basket', color: '#2F9E44' },
  { id: 'transport', name: 'Transport', icon: 'directions_bus', color: '#1C7ED6' },
  { id: 'shopping', name: 'Shopping', icon: 'shopping_bag', color: '#9C36B5' },
  { id: 'bills', name: 'Bills & Utilities', icon: 'receipt_long', color: '#F08C00' },
  { id: 'entertainment', name: 'Entertainment', icon: 'movie', color: '#D6336C' },
  { id: 'health', name: 'Health', icon: 'medical_services', color: '#0CA678' },
  { id: 'travel', name: 'Travel', icon: 'flight', color: '#4C6EF5' },
  { id: 'education', name: 'Education', icon: 'school', color: '#5C7CFA' },
  { id: 'other', name: 'Other', icon: 'category', color: '#868E96' },
];

/** name, category, popularity weight, and hand-written raw variants. */
const MERCHANT_TABLE = [
  ['Swiggy', 'food', 9, ['SWIGGY*1234', 'SWIGGY *8891', 'swiggy-2201']],
  ['Zomato', 'food', 8, ['ZOMATO*4410', 'zomato-7781']],
  ['Dominos Pizza', 'food', 4, null],
  ['Cafe Coffee Day', 'food', 4, null],
  ['Burger King', 'food', 3, null],
  ['Haldirams', 'food', 3, null],
  ['Chai Point', 'food', 5, null],
  ['Big Basket', 'groceries', 6, ['BIG BASKET*9912', 'BIG BASKET *4420', 'big basket-118']],
  ['Blinkit', 'groceries', 7, null],
  ['Zepto', 'groceries', 5, null],
  ['Dmart', 'groceries', 4, null],
  ['Reliance Fresh', 'groceries', 3, null],
  ['Natures Basket', 'groceries', 2, null],
  ['Uber', 'transport', 8, ['UBER*3391', 'UBER *2210', 'uber-7781']],
  ['Ola Cabs', 'transport', 5, null],
  ['Rapido', 'transport', 5, null],
  ['Indian Oil', 'transport', 3, null],
  ['Namma Metro', 'transport', 6, null],
  ['Irctc', 'transport', 2, null],
  ['Amazon', 'shopping', 8, ['AMAZON*4421', 'AMAZON *1180', 'amazon-9931']],
  ['Flipkart', 'shopping', 6, null],
  ['Myntra', 'shopping', 4, null],
  ['Ajio', 'shopping', 3, null],
  ['Croma', 'shopping', 2, null],
  ['Decathlon', 'shopping', 2, null],
  ['Airtel Postpaid', 'bills', 3, null],
  ['Jio Recharge', 'bills', 3, null],
  ['Bescom Power', 'bills', 2, null],
  ['Act Fibernet', 'bills', 2, null],
  ['Tata Power', 'bills', 2, null],
  ['Bookmyshow', 'entertainment', 4, null],
  ['Netflix', 'entertainment', 2, null],
  ['Spotify', 'entertainment', 2, null],
  ['Pvr Cinemas', 'entertainment', 3, null],
  ['Apollo Pharmacy', 'health', 4, null],
  ['Pharmeasy', 'health', 3, null],
  ['Practo', 'health', 2, null],
  ['Cult Fit', 'health', 3, null],
  ['Makemytrip', 'travel', 3, null],
  ['Indigo Airlines', 'travel', 2, null],
  ['Oyo Rooms', 'travel', 2, null],
  ['Udemy', 'education', 2, null],
  ['Unacademy', 'education', 2, null],
  ['Paytm Wallet', 'other', 4, null],
  ['Google Play', 'other', 3, null],
];

/** Amount magnitudes in paise: [floor, ceiling] before the skew is applied. */
const AMOUNT_RANGE = {
  food: [12000, 95000],
  groceries: [45000, 480000],
  transport: [4000, 65000],
  shopping: [70000, 1450000],
  bills: [55000, 920000],
  entertainment: [19900, 160000],
  health: [25000, 750000],
  travel: [150000, 2600000],
  education: [190000, 1600000],
  other: [9900, 210000],
};

const MODE_WEIGHTS = {
  food: { UPI: 6, CARD: 3, NETBANKING: 0, CASH: 1, AUTOPAY: 0 },
  groceries: { UPI: 5, CARD: 4, NETBANKING: 0, CASH: 1, AUTOPAY: 0 },
  transport: { UPI: 6, CARD: 2, NETBANKING: 0, CASH: 2, AUTOPAY: 0 },
  shopping: { UPI: 3, CARD: 6, NETBANKING: 1, CASH: 0, AUTOPAY: 0 },
  bills: { UPI: 2, CARD: 1, NETBANKING: 3, CASH: 0, AUTOPAY: 5 },
  entertainment: { UPI: 3, CARD: 4, NETBANKING: 0, CASH: 0, AUTOPAY: 3 },
  health: { UPI: 4, CARD: 4, NETBANKING: 0, CASH: 2, AUTOPAY: 0 },
  travel: { UPI: 2, CARD: 6, NETBANKING: 2, CASH: 0, AUTOPAY: 0 },
  education: { UPI: 2, CARD: 5, NETBANKING: 3, CASH: 0, AUTOPAY: 0 },
  other: { UPI: 5, CARD: 3, NETBANKING: 1, CASH: 1, AUTOPAY: 0 },
};

const MODES = ['UPI', 'CARD', 'NETBANKING', 'CASH', 'AUTOPAY'];

/** Transactions per month, newest first. current-2 is the stress month. */
const MONTH_PLAN = [
  { offset: 0, count: 900 },
  { offset: -1, count: 1100 },
  { offset: -2, count: 5200 },
  { offset: -3, count: 800 },
  { offset: -4, count: 0 },
  { offset: -5, count: 700 },
];

const REFUND_RATE = 0.03;
const OFF_CATEGORY_RATE = 0.12;

// --- generation ------------------------------------------------------------

const buildMerchants = (rng) =>
  MERCHANT_TABLE.map(([name, category, weight, rawVariants]) => {
    const upper = name.toUpperCase();
    const variants = rawVariants ?? [
      `${upper}*${intBetween(rng, 1000, 9999)}`,
      `${upper} *${intBetween(rng, 1000, 9999)}`,
      `${name.toLowerCase()}-${intBetween(rng, 100, 999)}`,
    ];
    const key = normalizeMerchant(variants[0]);

    for (const variant of variants) {
      if (normalizeMerchant(variant) !== key) {
        throw new Error(
          `Seed error: "${variant}" normalises to "${normalizeMerchant(variant)}", expected "${key}".`,
        );
      }
    }
    return { key, name, category, weight, variants };
  });

const amountFor = (rng, category) => {
  const [min, max] = AMOUNT_RANGE[category];
  // Skewed toward the cheap end — most spends are small, a few are large.
  const skewed = Math.pow(rng(), 2.2);
  return Math.round(min + skewed * (max - min));
};

const modeFor = (rng, category) => {
  const weights = MODE_WEIGHTS[category];
  return weightedPick(rng, MODES, (mode) => weights[mode]);
};

const monthStartOf = (offset, now) =>
  new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + offset, 1));

const generateMonth = (rng, merchants, monthStart, count, now) => {
  const monthKey = monthKeyOf(monthStart);
  const compact = monthKey.replace('-', '');
  const isCurrentMonth = monthKey === monthKeyOf(now);
  const daysInMonth = new Date(
    Date.UTC(monthStart.getUTCFullYear(), monthStart.getUTCMonth() + 1, 0),
  ).getUTCDate();
  const lastDay = isCurrentMonth ? now.getUTCDate() : daysInMonth;

  const days = [];
  for (let day = 1; day <= lastDay; day += 1) {
    const weekday = new Date(
      Date.UTC(monthStart.getUTCFullYear(), monthStart.getUTCMonth(), day),
    ).getUTCDay();
    days.push({ day, weight: weekday === 0 || weekday === 6 ? 1.45 : 1 });
  }

  const transactions = [];
  for (let index = 0; index < count; index += 1) {
    const merchant = weightedPick(rng, merchants, (m) => m.weight);
    const category =
      rng() < OFF_CATEGORY_RATE
        ? pick(rng, CATEGORIES).id
        : merchant.category;
    const raw = pick(rng, merchant.variants);

    const { day } = weightedPick(rng, days, (d) => d.weight);
    const maxHour = isCurrentMonth && day === lastDay ? now.getUTCHours() : 17;
    const at = new Date(
      Date.UTC(
        monthStart.getUTCFullYear(),
        monthStart.getUTCMonth(),
        day,
        maxHour <= 3 ? Math.max(0, maxHour) : intBetween(rng, 3, maxHour),
        intBetween(rng, 0, 59),
        intBetween(rng, 0, 59),
      ),
    );

    const isRefund = rng() < REFUND_RATE;
    const magnitude = amountFor(rng, category);

    transactions.push({
      id: `txn_${compact}_${String(index + 1).padStart(4, '0')}`,
      merchantRaw: raw,
      merchantName: merchant.name,
      merchantKey: merchant.key,
      category,
      // Signed: debits negative, refunds positive.
      amountPaise: isRefund ? magnitude : -magnitude,
      at,
      mode: isRefund ? 'CARD' : modeFor(rng, category),
    });
  }
  return transactions;
};

/**
 * Four budgets on the current month, deliberately shaped so the UI always has
 * one healthy, one nearly-spent (>80%) and one breached (>100%) row to render.
 */
const seedBudgets = (monthKey) => {
  const ranked = CATEGORIES.map((category) => ({
    category: category.id,
    spent: spentForCategory(category.id, monthKey),
  }))
    .filter((entry) => entry.spent > 0)
    .sort((a, b) => b.spent - a.spent);

  const factors = [0.78, 1 / 0.86, 1 / 0.45, 1 / 0.3]; // breached, >80%, healthy, healthy
  const toRupee = (paise) => Math.max(100, Math.round(paise / 100) * 100);

  ranked.slice(0, 4).forEach((entry, index) => {
    const budget = {
      category: entry.category,
      month: monthKey,
      limitPaise: toRupee(entry.spent * factors[index]),
    };
    store.budgets.set(budgetKey(budget.category, budget.month), budget);
  });
};

/** Wipes and regenerates every in-memory collection. Safe to call twice. */
export const seedStore = (now = new Date()) => {
  const rng = createRng(SEED);

  store.categories = CATEGORIES.map((category) => ({ ...category }));
  store.merchants = buildMerchants(rng);
  store.transactions = [];
  store.budgets.clear();
  store.merchantRules.clear();
  store.tokens.clear();
  store.undoJournal.clear();
  store.idempotency.clear();
  store.chaos = { mode: 'off', latencyMs: 0, failRate: 0 };

  for (const { offset, count } of MONTH_PLAN) {
    if (count === 0) continue;
    store.transactions.push(
      ...generateMonth(rng, store.merchants, monthStartOf(offset, now), count, now),
    );
  }

  reindex();
  seedBudgets(monthKeyOf(now));
  store.seeded = true;
  return store;
};
