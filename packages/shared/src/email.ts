// Email addresses for the sign-in code (free beta, docs/BETA.md). Deliberately simple:
// Supabase Auth makes the final check by sending the code.

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export function normalizeEmail(input: string): string | null {
  const email = input.trim().toLowerCase();
  return email.length <= 254 && EMAIL.test(email) ? email : null;
}
