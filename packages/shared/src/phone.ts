// Phone numbers in E.164, as Supabase Auth expects. French national numbers are
// accepted without the country code since the test market is France.

export function normalizePhone(input: string): string | null {
  const compact = input.replace(/[\s.\-()]/g, '');
  let e164: string;
  if (/^0[1-9]\d{8}$/.test(compact)) e164 = `+33${compact.slice(1)}`;
  else if (/^00\d{8,15}$/.test(compact)) e164 = `+${compact.slice(2)}`;
  else if (/^\+\d{8,15}$/.test(compact)) e164 = compact;
  else return null;
  // A French number written +330...: drop the trunk zero.
  if (/^\+330\d{9}$/.test(e164)) e164 = `+33${e164.slice(4)}`;
  return e164;
}

/**
 * Text hashed (SHA-256) on the device for "bloquer mes contacts" (Q23): the digits of
 * the E.164 number, as Supabase Auth stores phones. Null for unusable numbers.
 * Mirrors private.phone_digests.
 */
export function contactDigestInput(rawNumber: string): string | null {
  const e164 = normalizePhone(rawNumber);
  return e164 ? e164.slice(1) : null;
}
