// Sets the caller's position (device GPS or home address), its country and its
// administrative areas. Coordinates are snapped to ~1 km by the database; they are
// never logged nor returned.

import type { AreaCodes, GeocodingProvider } from '../_shared/providers/geocoding/index.ts';

export type LocationRequest =
  | { mode: 'device'; lat: number; lon: number }
  | { mode: 'home'; query: string };

export type LocationUpdate = AreaCodes & {
  lat: number;
  lon: number;
  source: 'device' | 'home';
  label: string | null;
};

export class LocationError extends Error {}

export function parseLocationRequest(body: unknown): LocationRequest {
  const b = (body ?? {}) as Record<string, unknown>;
  if (b.mode === 'device') {
    const { lat, lon } = b;
    if (typeof lat !== 'number' || typeof lon !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lon)
        || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
      throw new LocationError('invalid_coordinates');
    }
    return { mode: 'device', lat, lon };
  }
  if (b.mode === 'home') {
    if (typeof b.query !== 'string' || b.query.trim().length < 2 || b.query.length > 200) {
      throw new LocationError('invalid_address');
    }
    return { mode: 'home', query: b.query.trim() };
  }
  throw new LocationError('invalid_mode');
}

export async function resolveLocation(req: LocationRequest, geocoder: GeocodingProvider): Promise<LocationUpdate> {
  if (req.mode === 'device') {
    const areas = await geocoder.reverse(req);
    return { lat: req.lat, lon: req.lon, source: 'device', label: null, ...areas };
  }
  const found = await geocoder.forward(req.query);
  if (!found) throw new LocationError('address_not_found');
  const { label, lat, lon, countryCode, departmentCode, regionCode } = found;
  return { lat, lon, source: 'home', label, countryCode, departmentCode, regionCode };
}
