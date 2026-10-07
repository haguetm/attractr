// Geocoding provider contract. Real implementation: geoapigouv.ts (geo.api.gouv.fr), behind the
// `providers.geocoding` flag in app_config; development uses MockGeocodingProvider.

export interface GeoPoint {
  lat: number;
  lon: number;
}

/** Administrative areas of a position. Codes are null when unknown. */
export interface AreaCodes {
  /** ISO 3166-1 alpha-2, upper case. */
  countryCode: string | null;
  /** French département (INSEE, e.g. "75", "2A", "971"). */
  departmentCode: string | null;
  /** French région (INSEE, e.g. "11"). */
  regionCode: string | null;
}

export interface ForwardResult extends GeoPoint, AreaCodes {
  /** Human label shown to the user (city), never stored. */
  label: string;
}

export interface GeocodingProvider {
  /** Areas of a position (all null at sea, for instance). */
  reverse(point: GeoPoint): Promise<AreaCodes>;
  /** Resolves a home address or city. Null when nothing matches. */
  forward(query: string): Promise<ForwardResult | null>;
}
