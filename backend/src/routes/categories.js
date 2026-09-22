import { Router } from 'express';
import { store } from '../data/store.js';

export const categoriesRouter = Router();

categoriesRouter.get('/', (_req, res) => {
  res.json({ items: store.categories.map((category) => ({ ...category })) });
});
