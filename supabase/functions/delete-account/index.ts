// One-click account deletion with real erasure (spec §12).
// 1. Removes every Storage object under the user's folder.
// 2. Deletes the auth user; ON DELETE CASCADE erases all database rows.
// Called by the app with the user's JWT. Never logs personal data.

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { adminClient, json, requestUserId } from '../_shared/supabase.ts';

// Buckets holding per-user files under `<user_id>/`.
const USER_BUCKETS = ['photos', 'selfies'];

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });
  const userId = await requestUserId(req);
  if (!userId) return json(401, { error: 'not_authenticated' });

  const admin = adminClient();
  for (const bucket of USER_BUCKETS) {
    if (await removeFolder(admin, bucket, userId)) return json(500, { error: 'storage_cleanup_failed' });
  }

  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) {
    console.error('delete-account: auth deletion failed', error.status);
    return json(500, { error: 'deletion_failed' });
  }
  return json(200, { deleted: true });
});

/** Removes all objects under `<userId>/`. Returns true on failure. A missing bucket is not an error. */
async function removeFolder(admin: SupabaseClient, bucket: string, userId: string): Promise<boolean> {
  const storage = admin.storage.from(bucket);
  for (;;) {
    const { data, error } = await storage.list(userId, { limit: 1000 });
    if (error) return !/not found/i.test(error.message);
    if (!data || data.length === 0) return false;
    const { error: removeError } = await storage.remove(data.map((f) => `${userId}/${f.name}`));
    if (removeError) {
      console.error('delete-account: storage removal failed', bucket);
      return true;
    }
  }
}
