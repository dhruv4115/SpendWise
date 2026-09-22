import { randomUUID } from 'node:crypto';

/**
 * Every failure the API produces on purpose is an AppError. The error
 * middleware is the only place that knows how to shape the wire envelope.
 */
export class AppError extends Error {
  constructor(status, code, message, details = {}) {
    super(message);
    this.name = 'AppError';
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export const badRequest = (code, message, details) =>
  new AppError(400, code, message, details);

export const validationFailed = (message, details) =>
  new AppError(422, 'VALIDATION_FAILED', message, details);

export const unauthorized = (code, message) => new AppError(401, code, message);

export const notFound = (code, message, details) =>
  new AppError(404, code, message, details);

export const conflict = (code, message, details) =>
  new AppError(409, code, message, details);

/** Ids and tokens never reach the log — only their shape. */
const redactPath = (path) =>
  path
    .split('/')
    .map((segment) =>
      /^(txn|cat|mer|usr)_/.test(segment) || segment.length > 16
        ? ':id'
        : segment,
    )
    .join('/');

export const notFoundHandler = (req, _res, next) => {
  next(
    notFound('ROUTE_NOT_FOUND', `No route matches ${req.method} ${req.path}.`),
  );
};

/** Express identifies the error handler by its four-argument signature. */
export const errorHandler = (err, req, res, _next) => {
  const traceId = randomUUID();
  // The body parser throws its own shape; everything else we raise ourselves.
  const failure =
    err?.type === 'entity.parse.failed'
      ? badRequest('BAD_JSON', 'That request body is not valid JSON.')
      : err;

  const isApp = failure instanceof AppError;
  const status = isApp ? failure.status : 500;
  const code = isApp ? failure.code : 'INTERNAL_ERROR';
  const message = isApp
    ? failure.message
    : 'Something went wrong on our side. Please try again.';
  const details = isApp ? failure.details : {};

  console.error(
    `${traceId} ${req.method} ${redactPath(req.path)} ${status} ${code}`,
  );
  if (!isApp) console.error(failure?.stack ?? failure);

  if (res.headersSent) return;
  res.status(status).json({ error: { code, message, details, traceId } });
};
