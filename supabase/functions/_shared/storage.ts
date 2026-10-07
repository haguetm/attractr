import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

/** Buckets holding per-user files under `<user_id>/`. */
export const USER_BUCKETS = ['photos', 'selfies'];

/** Removes all objects under `<userId>/`. Returns true on failure. A missing bucket is not an error. */
export async function removeUserFolder(admin: SupabaseClient, bucket: string, userId: string): Promise<boolean> {
  const storage = admin.storage.from(bucket);
  for (;;) {
    const { data, error } = await storage.list(userId, { limit: 1000 });
    if (error) return !/not found/i.test(error.message);
    if (!data || data.length === 0) return false;
    const { error: removeError } = await storage.remove(data.map((f) => `${userId}/${f.name}`));
    if (removeError) return true;
  }
}

/** Downloads a private file with the service role. */
export async function download(admin: SupabaseClient, bucket: string, path: string) {
  const { data, error } = await admin.storage.from(bucket).download(path);
  if (error || !data) return null;
  return { bytes: new Uint8Array(await data.arrayBuffer()), contentType: data.type || 'image/jpeg' };
}
