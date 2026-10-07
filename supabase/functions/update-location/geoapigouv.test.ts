import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { GeoApiGouvGeocodingProvider } from '../_shared/providers/geocoding/geoapigouv.ts';

// Answers shaped like geo.api.gouv.fr /communes, recorded per query string.
function fakeApi(answers: Record<string, unknown>, calls: string[] = []) {
  return ((input: string | URL | Request) => {
    const url = new URL(String(input));
    calls.push(url.search);
    const key = url.searchParams.get('codePostal') ?? url.searchParams.get('nom') ??
      `${url.searchParams.get('lat')},${url.searchParams.get('lon')}`;
    if (!(key in answers)) return Promise.resolve(new Response('[]', { status: 200 }));
    const answer = answers[key];
    return Promise.resolve(answer instanceof Response ? answer : Response.json(answer));
  }) as typeof fetch;
}

const LYON = { nom: 'Lyon', centre: { type: 'Point', coordinates: [4.8351, 45.758] }, codeDepartement: '69', codeRegion: '84' };
const AJACCIO = { nom: 'Ajaccio', centre: { type: 'Point', coordinates: [8.7369, 41.9267] }, codeDepartement: '2A', codeRegion: '94' };

Deno.test('reverse: département and région of a French position, rounded to ~1 km before sending', async () => {
  const calls: string[] = [];
  const geo = new GeoApiGouvGeocodingProvider(fakeApi({ '45.76,4.84': [LYON] }, calls));
  assertEquals(await geo.reverse({ lat: 45.76412, lon: 4.83566 }), { countryCode: 'FR', departmentCode: '69', regionCode: '84' });
  assertEquals(calls[0]!.includes('45.76412'), false, 'the exact position never leaves the server');
});

Deno.test('reverse: Corsica and overseas codes are kept as they are', async () => {
  const geo = new GeoApiGouvGeocodingProvider(fakeApi({
    '41.93,8.74': [AJACCIO],
    '16.24,-61.53': [{ nom: 'Les Abymes', codeDepartement: '971', codeRegion: '01' }],
  }));
  assertEquals((await geo.reverse({ lat: 41.927, lon: 8.737 })).departmentCode, '2A');
  assertEquals(await geo.reverse({ lat: 16.24, lon: -61.53 }), { countryCode: 'FR', departmentCode: '971', regionCode: '01' });
});

Deno.test('reverse: outside France nothing is known', async () => {
  const geo = new GeoApiGouvGeocodingProvider(fakeApi({}));
  assertEquals(await geo.reverse({ lat: 50.85, lon: 4.35 }), { countryCode: null, departmentCode: null, regionCode: null });
});

Deno.test('forward: commune name from a typed address, or a postal code', async () => {
  const geo = new GeoApiGouvGeocodingProvider(fakeApi({ Lyon: [LYON], '69003': [LYON], Paris: [{ ...LYON, nom: 'Paris', codeDepartement: '75', codeRegion: '11' }] }));
  assertEquals(await geo.forward('12 rue de la République, Lyon'), {
    label: 'Lyon', lat: 45.758, lon: 4.8351, countryCode: 'FR', departmentCode: '69', regionCode: '84',
  });
  assertEquals((await geo.forward('3 place Bellecour 69003 Lyon'))?.departmentCode, '69');
  assertEquals((await geo.forward('Paris 11e'))?.label, 'Paris');
  assertEquals(await geo.forward('Atlantis'), null);
  assertEquals(await geo.forward('12'), null);
});

Deno.test('forward: malformed answers are ignored', async () => {
  const geo = new GeoApiGouvGeocodingProvider(fakeApi({
    Nowhere: [{ nom: 'Nowhere', codeDepartement: '69' }],
    Weird: [{ nom: 'Weird', centre: { coordinates: [1, 2] }, codeDepartement: 'DROP TABLE' }],
    Odd: { not: 'an array' },
  }));
  assertEquals(await geo.forward('Nowhere'), null);
  assertEquals(await geo.forward('Weird'), null);
  assertEquals(await geo.forward('Odd'), null);
});

Deno.test('an API error fails the call instead of storing an unknown area', async () => {
  const geo = new GeoApiGouvGeocodingProvider(fakeApi({ '45.76,4.84': new Response('busy', { status: 503 }) }));
  await assertRejects(() => geo.reverse({ lat: 45.76, lon: 4.84 }), Error, 'geocoding failed: 503');
});
