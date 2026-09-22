import { Router } from 'express';
import { monthFromQuery, summarize } from '../data/store.js';

export const summaryRouter = Router();

summaryRouter.get('/', (req, res) => {
  res.json(summarize(monthFromQuery(req.query.month)));
});
