import { assertEquals, assertRejects, assertThrows } from 'jsr:@std/assert@1';
import { providerMode } from '../_shared/providers/config.ts';
import { MockGeocodingProvider } from '../_shared/providers/geocoding/mock.ts';
import { LocationError, parseLocationRequest, resolveLocation } from './handler.ts';

const geocoder = new MockGeocodingProvider();

Deno.test('parses device and home requests', () => {
  assertEquals(parseLocationRequest({ mode: 'device', lat: 48.85, lon: 2.35 }), { mode: 'device', lat: 48.85, lon: 2.35 });
  assertEquals(parseLocationRequest({ mode: 'home', query: '  Lyon ' }), { mode: 'home', query: 'Lyon' });
  assertEquals(parseLocationRequest({ mode: 'passport', query: 'Nice' }), { mode: 'passport', query: 'Nice' });
});

Deno.test('rejects malformed requests', () => {
  assertThrows(() => parseLocationRequest(null), LocationError, 'invalid_mode');
  assertThrows(() => parseLocationRequest({ mode: 'device', lat: 91, lon: 0 }), LocationError, 'invalid_coordinates');
  assertThrows(() => parseLocationRequest({ mode: 'device', lat: '48', lon: 2 }), LocationError, 'invalid_coordinates');
  assertThrows(() => parseLocationRequest({ mode: 'home', query: 'x' }), LocationError, 'invalid_address');
});

Deno.test('device position gets its areas from the geocoder', async () => {
  const lyon = await resolveLocation({ mode: 'device', lat: 45.76, lon: 4.83 }, geocoder);
  assertEquals([lyon.countryCode, lyon.departmentCode, lyon.regionCode], ['FR', '69', '84']);
  assertEquals((await resolveLocation({ mode: 'device', lat: 50.85, lon: 4.35 }, geocoder)).countryCode, 'BE');
  const countryside = await resolveLocation({ mode: 'device', lat: 47.0, lon: 2.5 }, geocoder);
  assertEquals([countryside.countryCode, countryside.departmentCode], ['FR', null]);
  assertEquals((await resolveLocation({ mode: 'device', lat: 0, lon: -30 }, geocoder)).countryCode, null);
});

Deno.test('home address resolves to a city', async () => {
  const r = await resolveLocation({ mode: 'home', query: '12 rue X, Montpellier' }, geocoder);
  assertEquals([r.label, r.countryCode, r.departmentCode, r.regionCode, r.source], ['Montpellier', 'FR', '34', '76', 'home']);
  await assertRejects(() => resolveLocation({ mode: 'home', query: 'Atlantis' }, geocoder), LocationError, 'address_not_found');
});

Deno.test('mock providers are refused in production', async () => {
  const config = { get: (key: string) => Promise.resolve(key === 'providers.mode' ? 'mock' : null) };
  assertEquals(await providerMode(config, 'geocoding', 'development'), 'mock');
  await assertRejects(() => providerMode(config, 'geocoding', 'production'), Error, 'refused in production');
});
