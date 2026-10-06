#!/usr/bin/env node
// Deploys Edge Functions to a hosted Supabase project, never the dev-* ones
// (e.g. dev-impersonate, spec §13: impossible to enable in production).
// Usage: node scripts/deploy-functions.mjs --project-ref <ref>

import { execFileSync } from 'node:child_process';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const args = process.argv.slice(2);
const refIndex = args.indexOf('--project-ref');
const projectRef = refIndex >= 0 ? args[refIndex + 1] : undefined;
if (!projectRef) {
  console.error('Usage: node scripts/deploy-functions.mjs --project-ref <ref>');
  process.exit(1);
}

const dir = join(import.meta.dirname, '..', 'supabase', 'functions');
const functions = readdirSync(dir).filter(
  (name) => !name.startsWith('_') && !name.startsWith('.') && statSync(join(dir, name)).isDirectory(),
);
const skipped = functions.filter((name) => name.startsWith('dev-'));
const deployable = functions.filter((name) => !name.startsWith('dev-'));

console.log(`Skipping development-only functions: ${skipped.join(', ') || 'none'}`);
for (const name of deployable) {
  console.log(`Deploying ${name}…`);
  execFileSync('npx', ['supabase', 'functions', 'deploy', name, '--project-ref', projectRef], {
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
}
