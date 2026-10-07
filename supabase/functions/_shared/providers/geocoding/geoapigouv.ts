// Real geocoding provider: the French government's geo API (geo.api.gouv.fr, run by
// DINUM/Etalab). Free, no key, returns the INSEE département and région codes the
// feed needs. V1 targets France only (DECISIONS Q25): outside France it finds nothing
// and the country stays unknown.
//
// Privacy: positions are rounded to ~1 km before they leave the server, like the
// position stored in the database (private.snap_point).

import type { AreaCodes, ForwardResult, GeocodingProvider, GeoPoint } from './types.ts';

const BASE_URL = 'https://geo.api.gouv.fr';
const TIMEOUT_MS = 5000;
const FIELDS = 'nom,centre,codeDepartement,codeRegion';

interface Commune {
  nom?: unknown;
  centre?: { coordinates?: unknown };
  codeDepartement?: unknown;
  codeRegion?: unknown;
}

const NO_AREA: AreaCodes = { countryCode: null, departmentCode: null, regionCode: null };

/** ~1.1 km of latitude; enough to find the commune, too coarse to locate a home. */
const round = (value: number) => Math.round(value * 100) / 100;

const text = (value: unknown, pattern: RegExp) =>
  typeof value === 'string' && pattern.test(value) ? value : null;

function areas(c: Commune): AreaCodes {
  const departmentCode = text(c.codeDepartement, /^[0-9][0-9AB][0-9]?$/);
  return {
    // Every commune of the API is French, overseas ones included.
    countryCode: departmentCode ? 'FR' : null,
    departmentCode,
    regionCode: text(c.codeRegion, /^[0-9]{2}$/),
  };
}

export class GeoApiGouvGeocodingProvider implements GeocodingProvider {
  constructor(private readonly fetcher: typeof fetch = fetch) {}

  private async communes(params: Record<string, string>): Promise<Commune[]> {
    const url = `${BASE_URL}/communes?${new URLSearchParams({ ...params, fields: FIELDS, format: 'json' })}`;
    const response = await this.fetcher(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!response.ok) throw new Error(`geocoding failed: ${response.status}`);
    const body: unknown = await response.json();
    return Array.isArray(body) ? (body as Commune[]) : [];
  }

  async reverse(point: GeoPoint): Promise<AreaCodes> {
    const [commune] = await this.communes({ lat: String(round(point.lat)), lon: String(round(point.lon)) });
    return commune ? areas(commune) : NO_AREA;
  }

  async forward(query: string): Promise<ForwardResult | null> {
    const q = query.trim();
    // A postal code, else the commune name: "12 rue X, Lyon" keeps its last part and
    // words with digits are dropped ("Paris 11e" -> "Paris").
    const postalCode = q.match(/\b\d{5}\b/)?.[0];
    const name = q.split(',').pop()!.replace(/\S*\d\S*/g, '').replace(/\s+/g, ' ').trim();
    if (!postalCode && name.length < 2) return null;
    const params: Record<string, string> = postalCode
      ? { codePostal: postalCode, limit: '1' }
      : { nom: name, boost: 'population', limit: '1' };

    const [commune] = await this.communes(params);
    const coordinates = commune?.centre?.coordinates;
    if (!commune || !Array.isArray(coordinates) || typeof coordinates[0] !== 'number' || typeof coordinates[1] !== 'number') {
      return null;
    }
    const found = areas(commune);
    if (!found.departmentCode) return null;
    return {
      label: typeof commune.nom === 'string' ? commune.nom : name,
      lon: coordinates[0],
      lat: coordinates[1],
      ...found,
    };
  }
}
