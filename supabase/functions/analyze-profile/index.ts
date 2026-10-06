// AI profile analysis (spec §11). Called by the app with the user JWT; the provider is
// only ever reached from here. Photos are downloaded with the service role, kept in
// memory for the call only, and the answer must pass the output guard (one retry).

import { aiProvider, type AnalysisPhoto, guardAnalysis } from '../_shared/providers/ai/index.ts';
import { download } from '../_shared/storage.ts';
import { adminClient, configReader, json, requestUserId } from '../_shared/supabase.ts';

const SUPPORTED = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
const KNOWN_ERRORS = ['profile_not_active', 'ai_consent_required', 'ai_analysis_rate_limited', 'ai_analysis_no_photo'];

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });
  const userId = await requestUserId(req);
  if (!userId) return json(401, { error: 'not_authenticated' });
  const admin = adminClient();

  const { data: claim, error: claimError } = await admin.rpc('service_claim_ai_analysis', { p_user_id: userId });
  if (claimError) {
    const code = KNOWN_ERRORS.find((c) => claimError.message.includes(c));
    return json(code ? 409 : 500, { error: code ?? 'ai_analysis_failed' });
  }
  const analysisId = claim.analysis_id as string;

  try {
    const config = configReader(admin);
    const provider = await aiProvider(config);
    const photoIds: string[] = [];
    const photos: AnalysisPhoto[] = [];
    for (const p of claim.photos as { id: string; storage_path: string }[]) {
      const file = await download(admin, 'photos', p.storage_path);
      if (!file || !SUPPORTED.includes(file.contentType)) continue;
      photoIds.push(p.id);
      photos.push({ index: photos.length + 1, image: file.bytes, contentType: file.contentType as AnalysisPhoto['contentType'] });
    }
    if (!photos.length) throw new Error('no usable photo');

    const prompts = claim.prompts as { question: string; answer: string }[];
    const input = { photos, bio: claim.bio as string | null, prompts, drinks: claim.drinks as string[] };
    const ctx = {
      photoCount: photos.length,
      sourceText: [input.bio ?? '', ...prompts.map((p) => p.answer)].join('\n'),
      bioMaxLength: Number((await config.get('profile.bio_max_length')) ?? 500),
    };

    let checked = guardAnalysis(await provider.analyze(input), ctx);
    if (!checked.ok) checked = guardAnalysis(await provider.analyze(input), ctx);
    if (!checked.ok) throw new Error(`guard rejected: ${checked.reason}`);

    const a = checked.value;
    const result = {
      photos: a.photos.map((p) => ({ photo_id: photoIds[p.index - 1], strength: p.strength, improvement: p.improvement })),
      photo_order: a.photo_order.map((i) => photoIds[i - 1]),
      bio: a.bio,
      top_tip: a.top_tip,
    };
    const { data: kept, error } = await admin.rpc('service_record_ai_analysis', {
      p_analysis_id: analysisId, p_model: provider.model, p_result: result,
    });
    if (error) throw new Error('record failed');
    return kept ? json(200, { status: 'completed' }) : json(409, { error: 'ai_consent_required' });
  } catch (e) {
    // Reason only (no content, no user data) in the logs.
    console.error('analyze-profile failed:', e instanceof Error ? e.message.slice(0, 80) : 'unknown');
    await admin.rpc('service_release_ai_analysis', { p_analysis_id: analysisId });
    return json(502, { error: 'ai_analysis_failed' });
  }
});
