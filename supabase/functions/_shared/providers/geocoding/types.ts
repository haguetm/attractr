// Geocoding provider contract. The real implementation comes later, behind the
// `providers.geocoding` flag in app_config; development uses MockGeocodingProvider.

export interface GeoPoint {
  lat: number;
  lon: number;
}

export interface ForwardResult extends GeoPoint {
  /** ISO 3166-1 alpha-2, upper case. */
  countryCode: string;
  /** Human label shown to the user (city), never stored. */
  label: string;
}

export interface GeocodingProvider {
  /** Country of a position, or null when unknown (e.g. at sea). */
  reverseCountry(point: GeoPoint): Promise<string | null>;
  /** Resolves a home address or city. Null when nothing matches. */
  forward(query: string): Promise<ForwardResult | null>;
}
