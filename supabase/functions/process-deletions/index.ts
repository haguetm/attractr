// Called by pg_cron with the cron secret. Erases queued accounts (closed minor
// accounts, moderation closures): Storage files then the auth user, whose deletion
// cascades to every row. Also removes Storage files queued for cleanup (selfies).

import { isCronCall } from '../_shared/secrets.ts';
import { removeUserFolder, USER_BUCKETS } from '../_shared/storage.ts';
import { adminClient, json } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  if (!isCronCall(req)) return json(401, { error: 'not_authenticated' });
  const admin = adminClient();

  let erased = 0;
  const { data: deletions } = await admin.rpc('service_pending_deletions', { p_limit: 50 });
  for (const { user_id: userId } of (deletions ?? []) as { user_id: string }[]) {
    let failed = false;
    for (const bucket of USER_BUCKETS) failed = (await removeUserFolder(admin, bucket, userId)) || failed;
    if (failed) continue;
    const { error } = await admin.auth.admin.deleteUser(userId);
    if (error && error.status !== 404) continue;
    await admin.rpc('service_mark_deletion', { p_user_id: userId });
    erased++;
  }

  const { data: files } = await admin.rpc('service_pending_storage_cleanup', { p_limit: 200 });
  const done: number[] = [];
  for (const file of (files ?? []) as { id: number; bucket: string; path: string }[]) {
    const { error } = await admin.storage.from(file.bucket).remove([file.path]);
    if (!error) done.push(file.id);
  }
  if (done.length) await admin.rpc('service_mark_storage_cleanup', { p_ids: done });

  return json(200, { erased, files: done.length });
});
