// Moderates photos through the PhotoModerationProvider; thresholds are applied in SQL
// (private.apply_photo_result). Two callers:
//   - the app, right after adding a photo: { photoId } for one of its own photos;
//   - pg_cron with the service role key: {} processes pending photos in batch.

import { moderationProvider, type PhotoModerationProvider } from '../_shared/providers/moderation/index.ts';
import { download, isServiceCall } from '../_shared/storage.ts';
import { adminClient, configReader, json, requestUserId } from '../_shared/supabase.ts';
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

async function moderateOne(admin: SupabaseClient, provider: PhotoModerationProvider, photo: { id: string; storage_path: string }) {
  const file = await download(admin, 'photos', photo.storage_path);
  if (!file) return null;
  const scores = await provider.moderate({ image: file.bytes, contentType: file.contentType });
  const { data, error } = await admin.rpc('service_record_photo_result', {
    p_photo_id: photo.id,
    p_nudity: scores.nudity,
    p_violence: scores.violence,
  });
  if (error) throw new Error(error.code);
  return data as string;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });
  const admin = adminClient();

  try {
    const provider = await moderationProvider(configReader(admin));

    if (isServiceCall(req)) {
      const { data: pending, error } = await admin.rpc('service_pending_photos', { p_limit: 50 });
      if (error) throw new Error(error.code);
      let done = 0;
      for (const photo of pending ?? []) if (await moderateOne(admin, provider, photo)) done++;
      return json(200, { moderated: done });
    }

    const userId = await requestUserId(req);
    if (!userId) return json(401, { error: 'not_authenticated' });
    const body = await req.json().catch(() => null);
    const photoId = typeof body?.photoId === 'string' ? body.photoId : null;
    if (!photoId) return json(400, { error: 'invalid_request' });

    const { data: photo } = await admin
      .from('photos')
      .select('id, storage_path, moderation_status')
      .eq('id', photoId)
      .eq('user_id', userId)
      .maybeSingle();
    if (!photo) return json(404, { error: 'photo_not_found' });
    if (photo.moderation_status !== 'pending') return json(200, { outcome: photo.moderation_status });

    return json(200, { outcome: await moderateOne(admin, provider, photo) });
  } catch {
    console.error('moderate-photo: provider or record failed');
    return json(502, { error: 'moderation_failed' });
  }
});
