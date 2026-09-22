import { Router } from 'express';
import {
  budgetsForMonth,
  monthFromQuery,
  MONTH_PATTERN,
  store,
  upsertBudget,
} from '../data/store.js';
import { validationFailed } from '../middleware/errors.js';

export const budgetsRouter = Router();

budgetsRouter.get('/', (req, res) => {
  res.json({ items: budgetsForMonth(monthFromQuery(req.query.month)) });
});

budgetsRouter.put('/', (req, res) => {
  const { category, month, limitPaise } = req.body ?? {};
  const details = {};

  if (typeof category !== 'string' || !store.categoriesById.has(category)) {
    details.category = 'Unknown category.';
  }
  if (typeof month !== 'string' || !MONTH_PATTERN.test(month)) {
    details.month = 'Use the YYYY-MM format, for example 2026-09.';
  }
  if (!Number.isInteger(limitPaise)) {
    details.limitPaise = 'Use a whole number of paise.';
  } else if (limitPaise < 0) {
    details.limitPaise = 'A budget cannot be negative.';
  }

  if (Object.keys(details).length > 0) {
    throw validationFailed('We could not save that budget.', details);
  }

  res.json(upsertBudget(category, month, limitPaise));
});
