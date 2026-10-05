import { geocodingProvider } from '../_shared/providers/geocoding/index.ts';
import { adminClient, configReader, json, requestUserId } from '../_shared/supabase.ts';
import { LocationError, parseLocationRequest, resolveLocation } from './handler.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });
  const userId = await requestUserId(req);
  if (!userId) return json(401, { error: 'not_authenticated' });

  try {
    const request = parseLocationRequest(await req.json().catch(() => null));
    const admin = adminClient();
    const update = await resolveLocation(request, await geocodingProvider(configReader(admin)));
    const { error } = await admin.rpc('service_set_location', {
      p_user_id: userId,
      p_lat: update.lat,
      p_lon: update.lon,
      p_source: update.source,
      p_country_code: update.countryCode,
    });
    if (error) {
      console.error('update-location: rpc failed', error.code);
      return json(500, { error: 'location_update_failed' });
    }
    // Only the label and country go back to the app; coordinates stay server-side.
    return json(200, { label: update.label, countryCode: update.countryCode });
  } catch (e) {
    if (e instanceof LocationError) return json(400, { error: e.message });
    console.error('update-location: unexpected error');
    return json(500, { error: 'location_update_failed' });
  }
});
