// Development tool: lists seed profiles and signs the app in as one of them, so
// a tester can see that profile's feed. Guarded by ./guard.ts. Never deploy to production.

import { adminClient, configReader, json } from '../_shared/supabase.ts';
import { impersonationAllowed, parseImpersonateRequest } from './guard.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const admin = adminClient();
  const guard = impersonationAllowed({
    appEnv: Deno.env.get('APP_ENV'),
    supabaseUrl: Deno.env.get('SUPABASE_URL') ?? '',
    flag: await configReader(admin).get('dev.impersonation_enabled'),
  });
  // Indistinguishable from a missing function when not allowed.
  if (!guard.ok) return json(404, { error: 'not_found' });

  const request = parseImpersonateRequest(await req.json().catch(() => null));
  if (!request) return json(400, { error: 'invalid_request' });

  if (request.action === 'list') {
    const { data, error } = await admin
      .from('profiles')
      .select('id, first_name, birth_date, gender, department_code, verification_status, profile_drinks(drink)')
      .eq('is_seed', true)
      .order('department_code')
      .order('first_name');
    if (error) return json(500, { error: 'list_failed' });
    return json(200, {
      profiles: data.map((p) => ({
        id: p.id,
        firstName: p.first_name,
        birthDate: p.birth_date,
        gender: p.gender,
        departmentCode: p.department_code,
        verified: p.verification_status === 'verified',
        drinks: (p.profile_drinks as { drink: string }[]).map((d) => d.drink).sort(),
      })),
    });
  }

  const { data: target } = await admin.from('profiles').select('is_seed').eq('id', request.userId).maybeSingle();
  if (!target?.is_seed) return json(403, { error: 'not_a_seed_profile' });

  const { data: user, error: userError } = await admin.auth.admin.getUserById(request.userId);
  const email = user?.user?.email;
  if (userError || !email) return json(500, { error: 'seed_user_without_email' });

  const { data: link, error: linkError } = await admin.auth.admin.generateLink({ type: 'magiclink', email });
  if (linkError || !link.properties?.hashed_token) return json(500, { error: 'link_failed' });

  // The app exchanges this one-time token for a session with auth.verifyOtp.
  return json(200, { tokenHash: link.properties.hashed_token });
});
