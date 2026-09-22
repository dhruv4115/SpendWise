import { Router } from 'express';
import {
  budgetsForMonth,
  merchantAggregates,
  monthFromQuery,
  prevMonthKey,
  store,
  summarize,
} from '../data/store.js';

const rupees = new Intl.NumberFormat('en-IN', {
  style: 'currency',
  currency: 'INR',
  maximumFractionDigits: 0,
});

const formatPaise = (paise) => rupees.format(Math.round(paise / 100));

const categoryName = (id) => store.categoriesById.get(id)?.name ?? id;

const percentChange = (current, previous) =>
  previous > 0 ? Math.round(((current - previous) / previous) * 100) : null;

/** Biggest absolute movement in one category against the previous month. */
const swingCard = (month, summary, previous) => {
  const categories = new Set([
    ...Object.keys(summary.byCategory),
    ...Object.keys(previous.byCategory),
  ]);

  let best = null;
  for (const category of categories) {
    const now = summary.byCategory[category] ?? 0;
    const before = previous.byCategory[category] ?? 0;
    const delta = now - before;
    if (!best || Math.abs(delta) > Math.abs(best.delta)) {
      best = { category, now, before, delta };
    }
  }

  if (!best || best.delta === 0) {
    return {
      id: `swing_${month}`,
      title: 'No category moved much',
      body: 'Your spending split looks the same as last month.',
      severity: 'info',
      dismissible: true,
    };
  }

  const name = categoryName(best.category);
  const change = percentChange(best.now, best.before);
  const direction = best.delta > 0 ? 'up' : 'down';
  const changeText = change === null ? '' : ` (${Math.abs(change)}%)`;

  return {
    id: `swing_${month}`,
    title: `${name} is ${direction} ${formatPaise(Math.abs(best.delta))}${changeText}`,
    body:
      best.delta > 0
        ? `You spent ${formatPaise(best.now)} on ${name.toLowerCase()} this month, against ${formatPaise(best.before)} last month. That is the biggest change in your budget.`
        : `You spent ${formatPaise(best.now)} on ${name.toLowerCase()} this month, down from ${formatPaise(best.before)} last month. Nice work.`,
    severity: best.delta > 0 && (change ?? 0) >= 25 ? 'warning' : 'info',
    dismissible: true,
  };
};

const trendCard = (month, summary) => {
  const change = percentChange(summary.totalPaise, summary.prevTotalPaise);

  if (summary.totalPaise <= 0) {
    return {
      id: `trend_${month}`,
      title: 'Nothing spent yet',
      body: 'No spending has landed in this month, so there is nothing to compare.',
      severity: 'info',
      dismissible: true,
    };
  }

  if (change === null) {
    return {
      id: `trend_${month}`,
      title: `You have spent ${formatPaise(summary.totalPaise)} this month`,
      body: 'There is no spending in the previous month to compare against.',
      severity: 'info',
      dismissible: true,
    };
  }

  const direction = change >= 0 ? 'more' : 'less';
  return {
    id: `trend_${month}`,
    title: `You have spent ${formatPaise(summary.totalPaise)} this month`,
    body: `That is ${Math.abs(change)}% ${direction} than the ${formatPaise(summary.prevTotalPaise)} you spent last month.`,
    severity: change >= 15 ? 'warning' : 'info',
    dismissible: true,
  };
};

/** A breached budget outranks a merchant observation — it needs an action. */
const budgetOrMerchantCard = (month) => {
  const breached = budgetsForMonth(month)
    .filter((budget) => budget.limitPaise > 0 && budget.spentPaise > budget.limitPaise)
    .sort((a, b) => b.spentPaise - a.spentPaise)[0];

  if (breached) {
    const over = breached.spentPaise - breached.limitPaise;
    return {
      id: `budget_${month}`,
      title: `${categoryName(breached.category)} is over budget`,
      body: `You have spent ${formatPaise(breached.spentPaise)} against a ${formatPaise(breached.limitPaise)} limit — ${formatPaise(over)} over.`,
      severity: 'critical',
      dismissible: false,
    };
  }

  const top = merchantAggregates(month)[0];
  if (!top) {
    return {
      id: `merchant_${month}`,
      title: 'No merchants to compare',
      body: 'Once transactions arrive we will show where most of your money goes.',
      severity: 'info',
      dismissible: true,
    };
  }

  return {
    id: `merchant_${month}`,
    title: `${top.merchantName} took the most this month`,
    body: `${top.visits} payments totalling ${formatPaise(top.totalPaise)}, averaging ${formatPaise(top.avgPaise)} each, mostly under ${categoryName(top.topCategory).toLowerCase()}.`,
    severity: 'info',
    dismissible: true,
  };
};

export const insightsRouter = Router();

insightsRouter.get('/', (req, res) => {
  const month = monthFromQuery(req.query.month);
  const summary = summarize(month);
  const previous = summarize(prevMonthKey(month));

  res.json({
    items: [
      trendCard(month, summary),
      swingCard(month, summary, previous),
      budgetOrMerchantCard(month),
    ],
  });
});
