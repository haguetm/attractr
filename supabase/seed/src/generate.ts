import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { buildProfiles } from './profiles';
import { toSql } from './sql';

const target = fileURLToPath(new URL('../../seeds/20_profiles.sql', import.meta.url));
const profiles = buildProfiles();
writeFileSync(target, toSql(profiles), 'utf8');
console.log(`Wrote ${profiles.length} seed profiles to ${target}`);
