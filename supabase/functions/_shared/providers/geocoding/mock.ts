import type { AreaCodes, ForwardResult, GeocodingProvider, GeoPoint } from './types.ts';

// Rough bounding boxes, enough for development and the seed cities.
// Smaller boxes first: Belgium and Switzerland overlap the French box.
const COUNTRY_BOXES: { code: string; minLat: number; maxLat: number; minLon: number; maxLon: number }[] = [
  { code: 'BE', minLat: 50.68, maxLat: 51.5, minLon: 2.55, maxLon: 6.4 },
  { code: 'CH', minLat: 46.1, maxLat: 47.8, minLon: 5.95, maxLon: 10.5 },
  { code: 'FR', minLat: 41.3, maxLat: 51.1, minLon: -5.2, maxLon: 9.6 },
];

export const MOCK_CITIES: ForwardResult[] = [
  { label: 'Paris', lat: 48.8566, lon: 2.3522, countryCode: 'FR', departmentCode: '75', regionCode: '11' },
  { label: 'Marseille', lat: 43.2965, lon: 5.3698, countryCode: 'FR', departmentCode: '13', regionCode: '93' },
  { label: 'Lyon', lat: 45.764, lon: 4.8357, countryCode: 'FR', departmentCode: '69', regionCode: '84' },
  { label: 'Toulouse', lat: 43.6047, lon: 1.4442, countryCode: 'FR', departmentCode: '31', regionCode: '76' },
  { label: 'Nice', lat: 43.7102, lon: 7.262, countryCode: 'FR', departmentCode: '06', regionCode: '93' },
  { label: 'Nantes', lat: 47.2184, lon: -1.5536, countryCode: 'FR', departmentCode: '44', regionCode: '52' },
  { label: 'Montpellier', lat: 43.6119, lon: 3.8772, countryCode: 'FR', departmentCode: '34', regionCode: '76' },
  { label: 'Strasbourg', lat: 48.5734, lon: 7.7521, countryCode: 'FR', departmentCode: '67', regionCode: '44' },
  { label: 'Bordeaux', lat: 44.8378, lon: -0.5792, countryCode: 'FR', departmentCode: '33', regionCode: '75' },
  { label: 'Lille', lat: 50.6292, lon: 3.0573, countryCode: 'FR', departmentCode: '59', regionCode: '32' },
  { label: 'Rennes', lat: 48.1173, lon: -1.6778, countryCode: 'FR', departmentCode: '35', regionCode: '53' },
  { label: 'Grenoble', lat: 45.1885, lon: 5.7245, countryCode: 'FR', departmentCode: '38', regionCode: '84' },
  { label: 'Bruxelles', lat: 50.8503, lon: 4.3517, countryCode: 'BE', departmentCode: null, regionCode: null },
  { label: 'Genève', lat: 46.2044, lon: 6.1432, countryCode: 'CH', departmentCode: null, regionCode: null },
];

/** Areas of the nearest known city are reused within this distance. */
const NEAREST_CITY_KM = 40;

const normalize = (s: string) =>
  s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase().replace(/[^a-z]/g, '');

function km(a: GeoPoint, b: GeoPoint): number {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(h));
}

export class MockGeocodingProvider implements GeocodingProvider {
  reverse(point: GeoPoint): Promise<AreaCodes> {
    const box = COUNTRY_BOXES.find(
      (b) => point.lat >= b.minLat && point.lat <= b.maxLat && point.lon >= b.minLon && point.lon <= b.maxLon,
    );
    const nearest = MOCK_CITIES
      .map((c) => ({ c, d: km(point, c) }))
      .sort((x, y) => x.d - y.d)[0];
    const city = nearest && nearest.d <= NEAREST_CITY_KM ? nearest.c : null;
    return Promise.resolve({
      countryCode: city?.countryCode ?? box?.code ?? null,
      departmentCode: city?.departmentCode ?? null,
      regionCode: city?.regionCode ?? null,
    });
  }

  forward(query: string): Promise<ForwardResult | null> {
    const q = normalize(query);
    if (q.length < 2) return Promise.resolve(null);
    const city = MOCK_CITIES.find((c) => q.includes(normalize(c.label)));
    return Promise.resolve(city ? { ...city } : null);
  }
}
