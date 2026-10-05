// Maps backend errors to i18n keys. The database raises snake_case codes
// (e.g. 'drink_change_cooldown'); Edge Functions return { error: code }.

import type { TFunction } from 'i18next';
import fr from '../i18n/fr.json';

export class AppError extends Error {
  constructor(public readonly code: string) {
    super(code);
  }
}

const KNOWN_CODES = new Set(Object.keys(fr.errors));

/** Normalizes a code: 'onboarding_incomplete:photos' -> 'onboarding_incomplete_photos'. */
export const errorKey = (code: string) => code.replace(/:/g, '_');

export function errorCode(error: unknown): string {
  if (error instanceof AppError) return error.code;
  const message = (error as { message?: unknown } | null)?.message;
  if (typeof message === 'string') {
    const key = errorKey(message.trim());
    if (KNOWN_CODES.has(key)) return key;
    if (/network|fetch/i.test(message)) return 'network';
  }
  return 'generic';
}

export const errorMessage = (t: TFunction, error: unknown) => t(`errors.${errorCode(error)}`);
