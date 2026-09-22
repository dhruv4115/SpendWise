import { Router } from 'express';
import { merchantAggregates, monthFromQuery } from '../data/store.js';

export const merchantsRouter = Router();

merchantsRouter.get('/', (req, res) => {
  res.json({ items: merchantAggregates(monthFromQuery(req.query.month)) });
});
