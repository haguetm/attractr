// One-click account deletion with real erasure (spec §12).
// 1. Removes every Storage object under the user's folder.
// 2. Deletes the auth user; ON DELETE CASCADE erases all database rows.
// Called by the app with the user's JWT. Never logs personal data.

import { createClient } from 'jsr:@supabase/supabase-js@2';

// Buckets holding per-user files under `<user_id>/...` (created in phase 2 and later).
const USER_BUCKETS = ['photos', 'selfies'];

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json(401, { error: 'not_authenticated' });

  const url = Deno.env.get('SUPABASE_URL')!;
  const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json(401, { error: 'not_authenticated' });
  const userId = userData.user.id;

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  for (const bucket of USER_BUCKETS) {
    const failed = await removeFolder(admin, bucket, userId);
    if (failed) return json(500, { error: 'storage_cleanup_failed' });
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    console.error('delete-account: auth deletion failed', deleteError.status);
    return json(500, { error: 'deletion_failed' });
  }
  return json(200, { deleted: true });
});

/** Removes all objects under `<userId>/`. Returns true on failure. A missing bucket is not an error. */
async function removeFolder(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  userId: string,
): Promise<boolean> {
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
