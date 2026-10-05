import { type ConfigReader, providerMode } from '../config.ts';
import { MockGeocodingProvider } from './mock.ts';
import type { GeocodingProvider } from './types.ts';

export type { ForwardResult, GeocodingProvider, GeoPoint } from './types.ts';

export async function geocodingProvider(config: ConfigReader): Promise<GeocodingProvider> {
  const mode = await providerMode(config, 'geocoding');
  if (mode === 'mock') return new MockGeocodingProvider();
  throw new Error('real geocoding provider not implemented yet');
}
