import type { ForwardResult, GeocodingProvider, GeoPoint } from './types.ts';

// Rough bounding boxes, enough for development and the seed cities.
const COUNTRY_BOXES: { code: string; minLat: number; maxLat: number; minLon: number; maxLon: number }[] = [
  { code: 'BE', minLat: 50.68, maxLat: 51.5, minLon: 2.55, maxLon: 6.4 },
  { code: 'CH', minLat: 46.1, maxLat: 47.8, minLon: 5.95, maxLon: 10.5 },
  { code: 'FR', minLat: 41.3, maxLat: 51.1, minLon: -5.2, maxLon: 9.6 },
];

const CITIES: ForwardResult[] = [
  { label: 'Paris', lat: 48.8566, lon: 2.3522, countryCode: 'FR' },
  { label: 'Marseille', lat: 43.2965, lon: 5.3698, countryCode: 'FR' },
  { label: 'Lyon', lat: 45.764, lon: 4.8357, countryCode: 'FR' },
  { label: 'Toulouse', lat: 43.6047, lon: 1.4442, countryCode: 'FR' },
  { label: 'Nice', lat: 43.7102, lon: 7.262, countryCode: 'FR' },
  { label: 'Nantes', lat: 47.2184, lon: -1.5536, countryCode: 'FR' },
  { label: 'Montpellier', lat: 43.6119, lon: 3.8772, countryCode: 'FR' },
  { label: 'Strasbourg', lat: 48.5734, lon: 7.7521, countryCode: 'FR' },
  { label: 'Bordeaux', lat: 44.8378, lon: -0.5792, countryCode: 'FR' },
  { label: 'Lille', lat: 50.6292, lon: 3.0573, countryCode: 'FR' },
  { label: 'Rennes', lat: 48.1173, lon: -1.6778, countryCode: 'FR' },
  { label: 'Grenoble', lat: 45.1885, lon: 5.7245, countryCode: 'FR' },
  { label: 'Bruxelles', lat: 50.8503, lon: 4.3517, countryCode: 'BE' },
  { label: 'Genève', lat: 46.2044, lon: 6.1432, countryCode: 'CH' },
];

const normalize = (s: string) =>
  s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase().replace(/[^a-z]/g, '');

export class MockGeocodingProvider implements GeocodingProvider {
  reverseCountry({ lat, lon }: GeoPoint): Promise<string | null> {
    // Smaller boxes first: Belgium and Switzerland overlap the French box.
    const box = COUNTRY_BOXES.find((b) => lat >= b.minLat && lat <= b.maxLat && lon >= b.minLon && lon <= b.maxLon);
    return Promise.resolve(box?.code ?? null);
  }

  forward(query: string): Promise<ForwardResult | null> {
    const q = normalize(query);
    if (q.length < 2) return Promise.resolve(null);
    const city = CITIES.find((c) => q.includes(normalize(c.label)));
    return Promise.resolve(city ? { ...city } : null);
  }
}
