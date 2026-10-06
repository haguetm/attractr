// One-click account deletion with real erasure (spec §12).
// 1. Removes every Storage object under the user's folder.
// 2. Deletes the auth user; ON DELETE CASCADE erases all database rows.
// Called by the app with the user's JWT. Never logs personal data.

import { removeUserFolder, USER_BUCKETS } from '../_shared/storage.ts';
import { adminClient, json, requestUserId } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });
  const userId = await requestUserId(req);
  if (!userId) return json(401, { error: 'not_authenticated' });

  const admin = adminClient();
  for (const bucket of USER_BUCKETS) {
    if (await removeUserFolder(admin, bucket, userId)) return json(500, { error: 'storage_cleanup_failed' });
  }

  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) {
    console.error('delete-account: auth deletion failed', error.status);
    return json(500, { error: 'deletion_failed' });
  }
  return json(200, { deleted: true });
});
