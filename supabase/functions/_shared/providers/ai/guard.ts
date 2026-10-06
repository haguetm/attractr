// Output guard (spec §11): the answer is rejected when its shape is wrong or when it
// contains a forbidden topic (beauty rating, body, skin, age, origin, orientation,
// health, religion). Matching runs on lowercase text without accents.
//
// Commentary fields (per-photo advice, drink coherence, top tip) are strict. The bio
// rewrite and the quoted clichés may repeat a term the person wrote themselves (a bio
// that mentions their faith is theirs to keep); anything the model adds is rejected.

import type { ProfileAnalysis } from './types.ts';

export type GuardResult = { ok: true; value: ProfileAnalysis } | { ok: false; reason: string };

const FORBIDDEN: { category: string; pattern: RegExp }[] = [
  { category: 'beauty', pattern: /\b(tu es|t'es|vous etes|te rend\w*|vous rend\w*|l'air|parais|semble\w*)\s+(tres |plus |trop |si |vraiment )?(beaux?|belles?|jolie?s?|mignon\w*|moche\w*|laide?s?|canon|sexy|attirant\w*|seduisant\w*)\b/ },
  { category: 'beauty', pattern: /\b(sexy|attirant\w*|seduisant\w*|moche\w*|laideur|beaute|(ton|son|le|un|ce) physique|charme physique|canon|bombe|sex[- ]appeal|hot|attractive|beautiful|pretty|ugly|handsome|gorgeous)\b/ },
  { category: 'beauty', pattern: /\b\d+([.,]\d+)?\s*(\/|sur)\s*(10|20|100)\b|\bnote de beaute\b|\bscore\b|\brating\b/ },
  { category: 'body', pattern: /\b(corps|poids|kilos?|mince\w*|maigre\w*|surpoids|obese\w*|rondeurs?|muscl\w*|silhouette|poitrine|seins?|fesses?|ventre|abdos?|jambes?|cuisses?|cheveux|calvitie|chauve|barbe|dents|nez|levres|yeux|morphologie|body|weight|bald)\b/ },
  { category: 'skin', pattern: /\b(peau|teint|acne|rides?|bronz\w*|cicatrices?|tatou\w*|skin|complexion|wrinkles?)\b/ },
  { category: 'age', pattern: /\b(ages?|agee?s?|jeunes?|jeunesse|vieux|vieille\w*|vieilli\w*|rajeun\w*|\d+\s*ans|trentaine|quarantaine|cinquantaine|old|young|older|younger)\b/ },
  { category: 'origin', pattern: /\b(origines?|ethni\w*|races?|racial\w*|metis\w*|nationalite|couleur de peau|africain\w*|asiatique\w*|arabe\w*|maghreb\w*|europeen\w*|caucasien\w*|ethnic\w*|origin)\b/ },
  { category: 'orientation', pattern: /\b(orientation sexuelle|gay|gays|lesbienne\w*|homo\w*|hetero\w*|bisexuel\w*|bi|queer|transgenre\w*|straight|lesbian)\b/ },
  { category: 'health', pattern: /\b(sante|malad\w*|handicap\w*|enceinte|grossesse|depress\w*|anxi\w*|medicament\w*|therapie|diabet\w*|fauteuil roulant|health|disab\w*|pregnan\w*|illness)\b/ },
  { category: 'religion', pattern: /\b(religi\w*|chretien\w*|musulman\w*|islam\w*|juif|juive|juifs|judai\w*|catholique\w*|protestant\w*|bouddhis\w*|hindou\w*|athee\w*|croyante?s?|foi|priere\w*|voilee?s?|kippa|eglise|mosquee|synagogue|christian|muslim|jewish)\b/ },
];

export function normalize(text: string): string {
  return text.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[‘’ʼ]/g, "'").toLowerCase();
}

/** Forbidden terms found in `text`; terms also present in `allowedSource` are ignored. */
export function forbiddenTerms(text: string, allowedSource = ''): string[] {
  const t = normalize(text);
  const source = normalize(allowedSource);
  const found: string[] = [];
  for (const { category, pattern } of FORBIDDEN) {
    for (const m of t.matchAll(new RegExp(pattern.source, 'g'))) {
      const term = m[0];
      if (source && new RegExp(`\\b${term.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')}\\b`).test(source)) continue;
      found.push(`${category}:${term}`);
    }
  }
  return found;
}

const isText = (v: unknown, max: number): v is string => typeof v === 'string' && v.trim().length > 0 && v.length <= max;

export interface GuardContext {
  photoCount: number;
  /** The person's own bio and written answers. */
  sourceText: string;
  bioMaxLength: number;
}

export function guardAnalysis(raw: unknown, ctx: GuardContext): GuardResult {
  const fail = (reason: string): GuardResult => ({ ok: false, reason });
  if (typeof raw !== 'object' || raw === null) return fail('shape:root');
  const r = raw as Record<string, unknown>;
  const expected = Array.from({ length: ctx.photoCount }, (_, i) => i + 1);

  if (!Array.isArray(r.photos) || r.photos.length !== ctx.photoCount) return fail('shape:photos');
  const photos = r.photos as Record<string, unknown>[];
  const indexes = photos.map((p) => p?.index);
  if ([...indexes].sort((a, b) => Number(a) - Number(b)).join() !== expected.join()) return fail('shape:photo_indexes');
  if (!photos.every((p) => isText(p.strength, 300) && isText(p.improvement, 300))) return fail('shape:photo_text');

  if (!Array.isArray(r.photo_order) || [...r.photo_order].sort((a, b) => a - b).join() !== expected.join()) return fail('shape:photo_order');

  const bio = r.bio as Record<string, unknown> | undefined;
  if (typeof bio !== 'object' || bio === null) return fail('shape:bio');
  if (!Array.isArray(bio.cliches) || bio.cliches.length > 5 || !bio.cliches.every((c) => isText(c, 200))) return fail('shape:cliches');
  if (!isText(bio.rewrite, ctx.bioMaxLength) || !isText(bio.drink_fit, 300)) return fail('shape:bio_text');
  if (!isText(r.top_tip, 300)) return fail('shape:top_tip');

  const strict = [...photos.flatMap((p) => [p.strength as string, p.improvement as string]), bio.drink_fit as string, r.top_tip as string];
  const exempt = [bio.rewrite as string, ...(bio.cliches as string[])];
  const found = [
    ...strict.flatMap((t) => forbiddenTerms(t)),
    ...exempt.flatMap((t) => forbiddenTerms(t, ctx.sourceText)),
  ];
  if (found.length) return fail(`forbidden:${found[0].split(':')[0]}`);

  return {
    ok: true,
    value: {
      photos: photos.map((p) => ({ index: p.index as number, strength: (p.strength as string).trim(), improvement: (p.improvement as string).trim() })),
      photo_order: r.photo_order as number[],
      bio: { cliches: bio.cliches as string[], rewrite: (bio.rewrite as string).trim(), drink_fit: (bio.drink_fit as string).trim() },
      top_tip: (r.top_tip as string).trim(),
    },
  };
}
