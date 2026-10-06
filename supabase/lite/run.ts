// Runs the database test suite on PGlite (embedded Postgres in WebAssembly), without
// Docker: Supabase stand-ins, then migrations, seeds and every supabase/tests file.
//
//   npm run db:test:lite                 all tests
//   npm run db:test:lite -- 012          only files whose name contains "012"
//
// It approximates the Supabase stack (see supabase-stubs.sql); `supabase test db` on the
// real stack stays the reference before any release.

import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { postgis } from '@electric-sql/pglite-postgis';
import { parse } from 'libpg-query';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = join(import.meta.dirname, '..');
const filter = process.argv[2];

// Lines that only make sense on the real stack (extensions PGlite does not ship).
const UNSUPPORTED = [
  /^[ \t]*create extension if not exists supabase_vault[^;]*;/gim,
  /^[ \t]*create extension if not exists pgtap[^;]*;/gim,
];
const adapt = (sql: string) => UNSUPPORTED.reduce((s, re) => s.replace(re, '-- (skipped on PGlite) $&'), sql);

const sqlFiles = (dir: string) =>
  readdirSync(join(root, dir)).filter((f) => f.endsWith('.sql')).sort().map((f) => join(dir, f));

/** Splits a SQL file into statements using the real Postgres parser. */
async function statements(sql: string): Promise<string[]> {
  const tree = (await parse(sql)) as { stmts: { stmt_location?: number; stmt_len?: number }[] };
  const bytes = Buffer.from(sql, 'utf8');
  return tree.stmts.map((s) => {
    const start = s.stmt_location ?? 0;
    const end = s.stmt_len ? start + s.stmt_len : bytes.length;
    return bytes.subarray(start, end).toString('utf8').trim();
  });
}

const firstLine = (s: string) => s.split('\n').find((l) => l.trim() && !l.trim().startsWith('--'))?.trim().slice(0, 110) ?? '';

async function main() {
  const db = new PGlite({ extensions: { pgcrypto, postgis } });

  await db.exec(readFileSync(join(root, 'lite/supabase-stubs.sql'), 'utf8'));

  for (const file of [...sqlFiles('migrations'), ...sqlFiles('seeds')]) {
    for (const stmt of await statements(adapt(readFileSync(join(root, file), 'utf8')))) {
      try {
        await db.exec(stmt);
      } catch (e) {
        console.error(`\n✗ ${file}\n  ${firstLine(stmt)}\n  ${(e as Error).message}`);
        process.exit(1);
      }
    }
    console.log(`✓ applied ${file}`);
  }

  await db.exec(readFileSync(join(root, 'lite/tap.sql'), 'utf8'));
  await db.exec('set search_path = public, extensions, tap');

  let failedFiles = 0;
  let total = 0;
  let failed = 0;
  for (const file of sqlFiles('tests').filter((f) => !filter || f.includes(filter))) {
    const lines: string[] = [];
    let error: string | null = null;
    for (const stmt of await statements(readFileSync(join(root, file), 'utf8'))) {
      try {
        const results = await db.exec(stmt);
        for (const r of results) {
          for (const row of r.rows) {
            const value = Object.values(row)[0];
            if (typeof value === 'string' && /^(not ok|ok|#|1\.\.)/.test(value)) lines.push(value);
          }
        }
      } catch (e) {
        error = `${firstLine(stmt)}\n    ${(e as Error).message}`;
        await db.exec('rollback').catch(() => undefined);
        break;
      }
    }
    const asserts = lines.filter((l) => /^(not )?ok /.test(l));
    const bad = asserts.filter((l) => l.startsWith('not ok'));
    const planLine = lines.find((l) => l.startsWith('# Looks like'));
    total += asserts.length;
    failed += bad.length;
    const ok = !error && bad.length === 0 && !planLine;
    if (!ok) failedFiles++;
    console.log(`${ok ? '✓' : '✗'} ${file} (${asserts.length - bad.length}/${asserts.length})`);
    for (const l of bad) console.log(`    ${l.replace(/\n/g, '\n    ')}`);
    if (planLine) console.log(`    ${planLine}`);
    if (error) console.log(`    error at: ${error}`);
    await db.exec('reset role; set search_path = public, extensions, tap').catch(() => undefined);
  }

  console.log(`\n${total - failed}/${total} assertions passed, ${failedFiles} file(s) failing`);
  await db.close();
  process.exit(failedFiles ? 1 : 0);
}

void main();
