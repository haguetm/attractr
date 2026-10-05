// Sets the caller's position (device GPS or home address) and its country.
// Coordinates are snapped to ~1 km by the database; they are never logged.

import type { GeocodingProvider } from '../_shared/providers/geocoding/index.ts';

export type LocationRequest =
  | { mode: 'device'; lat: number; lon: number }
  | { mode: 'home'; query: string };

export type LocationUpdate = {
  lat: number;
  lon: number;
  source: 'device' | 'home';
  countryCode: string | null;
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
    const countryCode = await geocoder.reverseCountry(req);
    return { lat: req.lat, lon: req.lon, source: 'device', countryCode, label: null };
  }
  const found = await geocoder.forward(req.query);
  if (!found) throw new LocationError('address_not_found');
  return { lat: found.lat, lon: found.lon, source: 'home', countryCode: found.countryCode, label: found.label };
}
