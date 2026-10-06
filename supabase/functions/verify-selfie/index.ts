// Verifies the caller's latest selfie (liveness, age estimate, duplicate face) through
// the SelfieVerificationProvider; the SQL rules decide (private.apply_selfie_result).
// The selfie is deleted right away unless a human must review it.

import { selfieProvider } from '../_shared/providers/selfie/index.ts';
import { download } from '../_shared/storage.ts';
import { adminClient, configReader, json, requestUserId } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });
  const userId = await requestUserId(req);
  if (!userId) return json(401, { error: 'not_authenticated' });

  const admin = adminClient();
  const { data: submission, error } = await admin.rpc('service_latest_selfie', { p_user_id: userId });
  if (error) return json(500, { error: 'verification_failed' });
  if (!submission) return json(404, { error: 'selfie_not_found' });

  const file = await download(admin, 'selfies', submission.storage_path);
  if (!file) return json(404, { error: 'selfie_not_found' });

  try {
    const provider = await selfieProvider(configReader(admin));
    const result = await provider.verify({
      image: file.bytes,
      contentType: file.contentType,
      subjectId: userId,
      declaredAge: submission.declared_age,
    });
    const { data: outcome, error: recordError } = await admin.rpc('service_record_selfie_result', {
      p_submission_id: submission.id,
      p_live: result.live,
      p_estimated_age: result.estimatedAge,
      p_confidence: result.confidence,
      p_face_id: result.faceId,
    });
    if (recordError) throw new Error(recordError.code);
    if (outcome !== 'review') await admin.storage.from('selfies').remove([submission.storage_path]);
    return json(200, { outcome });
  } catch {
    console.error('verify-selfie: provider or record failed');
    return json(502, { error: 'verification_failed' });
  }
});
