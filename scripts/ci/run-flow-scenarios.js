#!/usr/bin/env node
/**
 * run-flow-scenarios.js — whole-chain flow/integration test driver.
 *
 * STATUS: stub. Flow scenarios activate with milestone v0.3 (RateLimiter +
 * RollbackGuard), per the roadmap in README.md and Section 12.2 of the
 * blueprint. Until then this script:
 *   1. verifies the target org is reachable,
 *   2. exits 0 with an explicit SKIP notice (never a silent pass),
 *   3. documents exactly which scenarios must exist before the stub is removed.
 *
 * Required scenarios at v0.3+ (each maps to a threat-model row):
 *   - injected bulk mutation against a single-record contract -> BLOCK + audit event
 *   - rate limit exceeded in rolling window                    -> THROTTLED
 *   - partial failure mid-bulk                                 -> full rollback, no partial commit
 *   - every BLOCK produces exactly one AgentGuard_Audit__e event
 */
'use strict';

const { execFileSync } = require('child_process');

const args = process.argv.slice(2);
const orgIdx = args.indexOf('--org');
const org = orgIdx !== -1 ? args[orgIdx + 1] : null;

if (!org) {
  console.error('usage: run-flow-scenarios.js --org <orgAlias>');
  process.exit(2);
}

function sf(cmdArgs) {
  return execFileSync('sf', cmdArgs, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

try {
  const out = JSON.parse(sf(['org', 'display', '--target-org', org, '--json']));
  console.log(`Org reachable: ${out.result.alias || out.result.username} (${out.result.id})`);
} catch (e) {
  console.error(`Cannot reach org "${org}". Is it created and authenticated?`);
  console.error(e.stderr || e.message);
  process.exit(1);
}

console.warn('');
console.warn('SKIP: flow/integration scenarios not yet implemented.');
console.warn('This gate becomes mandatory at v0.3 — see scripts/ci/run-flow-scenarios.js header');
console.warn('for the required scenario list. Do not remove this notice until they ship.');
process.exit(0);
