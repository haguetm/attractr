import { type ConfigReader, providerMode } from '../config.ts';
import { GeoApiGouvGeocodingProvider } from './geoapigouv.ts';
import { MockGeocodingProvider } from './mock.ts';
import type { GeocodingProvider } from './types.ts';

export type { AreaCodes, ForwardResult, GeocodingProvider, GeoPoint } from './types.ts';

export async function geocodingProvider(config: ConfigReader): Promise<GeocodingProvider> {
  const mode = await providerMode(config, 'geocoding');
  return mode === 'mock' ? new MockGeocodingProvider() : new GeoApiGouvGeocodingProvider();
}
