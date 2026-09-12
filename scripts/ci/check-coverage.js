#!/usr/bin/env node
/**
 * check-coverage.js — CI coverage gate (RULES.md #2)
 *
 * Usage: node scripts/ci/check-coverage.js <test-results-dir> <threshold>
 *   e.g. node scripts/ci/check-coverage.js ./test-results 90
 *
 * Reads the JSON output of `sf apex run test --result-format json --code-coverage`
 * and fails (exit 1) when aggregate coverage is below <threshold>.
 *
 * If a file named `core-classes.txt` exists next to this script (one Apex class
 * name per line), each listed class must also individually meet the threshold.
 */
'use strict';

const fs = require('fs');
const path = require('path');

function fail(msg) {
  console.error(`COVERAGE GATE FAILED: ${msg}`);
  process.exit(1);
}

const [, , resultsDirArg, thresholdArg] = process.argv;
if (!resultsDirArg || !thresholdArg) {
  fail('usage: check-coverage.js <test-results-dir> <threshold>');
}
const threshold = Number(thresholdArg);
if (!Number.isFinite(threshold) || threshold <= 0 || threshold > 100) {
  fail(`invalid threshold: ${thresholdArg}`);
}
if (!fs.existsSync(resultsDirArg)) {
  fail(`results directory not found: ${resultsDirArg}`);
}

// Locate the test-result JSON produced by sf apex run test.
function findResultJson(dir) {
  const candidates = fs.readdirSync(dir).filter((f) => f.endsWith('.json') && !f.includes('codecoverage'));
  if (candidates.length === 0) return null;
  return path.join(dir, candidates[0]);
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    fail(`could not parse ${file}: ${e.message}`);
  }
}

const resultFile = findResultJson(resultsDirArg);
if (!resultFile) {
  fail(`no JSON test results found in ${resultsDirArg}. Did 'sf apex run test' run with --result-format json?`);
}
const data = readJson(resultFile);

if (!data.summary) {
  fail(`${resultFile} does not look like sf apex run test JSON output.`);
}

const summary = data.summary;
console.log('Test summary:');
for (const key of ['outcome', 'testsRan', 'passing', 'failing', 'skipped']) {
  if (summary[key] !== undefined) console.log(`  ${key}: ${summary[key]}`);
}

if (summary.failing > 0 || summary.outcome === 'Failed') {
  fail('one or more unit tests failed.');
}

// Aggregate coverage
let covered = null;
let total = null;

if (summary.codeCoverage && typeof summary.codeCoverage.totalLines === 'number') {
  covered = summary.codeCoverage.coveredLines;
  total = summary.codeCoverage.totalLines;
} else if (data.coverage && data.coverage.summary && typeof data.coverage.summary.totalLines === 'number') {
  covered = data.coverage.summary.coveredLines;
  total = data.coverage.summary.totalLines;
} else if (data.coverage && Array.isArray(data.coverage.coverageReport)) {
  covered = data.coverage.coverageReport.reduce((sum, c) => sum + (c.coveredLines || 0), 0);
  total = data.coverage.coverageReport.reduce((sum, c) => sum + (c.totalLines || 0), 0);
} else if (data.coverage && Array.isArray(data.coverage.coverage)) {
  covered = data.coverage.coverage.reduce((sum, c) => sum + (c.totalCovered || 0), 0);
  total = data.coverage.coverage.reduce((sum, c) => sum + (c.totalLines || 0), 0);
}

if (covered === null || !total) {
  const ccFile = fs.readdirSync(resultsDirArg).find((f) => f.includes('codecoverage') && f.endsWith('.json'));
  if (ccFile) {
    const ccData = readJson(path.join(resultsDirArg, ccFile));
    if (Array.isArray(ccData.coverageReport)) {
      covered = ccData.coverageReport.reduce((sum, c) => sum + (c.coveredLines || 0), 0);
      total = ccData.coverageReport.reduce((sum, c) => sum + (c.totalLines || 0), 0);
    } else if (Array.isArray(ccData)) {
      covered = ccData.reduce((sum, c) => sum + (c.totalCovered || 0), 0);
      total = ccData.reduce((sum, c) => sum + (c.totalLines || 0), 0);
    }
  }
}

if (covered === null || !total) {
  fail(
    `no coverage data found in ${resultFile}. Run with --code-coverage. If there are no Apex classes yet, add classes before enabling this gate.`
  );
}

const aggregatePct = Math.floor((covered / total) * 10000) / 100;
console.log(`\nAggregate coverage: ${aggregatePct}% (${covered}/${total} lines), threshold: ${threshold}%`);

if (aggregatePct < threshold) {
  fail(`aggregate coverage ${aggregatePct}% is below threshold ${threshold}%.`);
}

// Per-class gate for core/ classes, if core-classes.txt is present.
const coreListFile = path.join(__dirname, 'core-classes.txt');
if (fs.existsSync(coreListFile)) {
  const coreClasses = fs
    .readFileSync(coreListFile, 'utf8')
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean);

  const report = (() => {
    if (data.coverage && Array.isArray(data.coverage.coverageReport)) return data.coverage.coverageReport;
    if (data.coverage && Array.isArray(data.coverage.coverage)) return data.coverage.coverage;

    // Older CLI versions write a separate codecoverage file.
    const ccFile = fs.readdirSync(resultsDirArg).find((f) => f.includes('codecoverage') && f.endsWith('.json'));
    if (!ccFile) return [];

    const ccData = readJson(path.join(resultsDirArg, ccFile));
    if (Array.isArray(ccData.coverageReport)) return ccData.coverageReport;
    if (Array.isArray(ccData)) return ccData;
    return [];
  })();

  let allCorePass = true;
  for (const cls of coreClasses) {
    const entry = report.find((c) => c.name === cls);
    if (!entry) {
      console.warn(`  WARN: core class ${cls} not present in coverage report (missing or not deployed).`);
      allCorePass = false;
      continue;
    }
    const coveredLines = entry.coveredLines ?? entry.totalCovered ?? 0;
    const pct = entry.totalLines ? Math.floor((coveredLines / entry.totalLines) * 10000) / 100 : 0;
    const ok = pct >= threshold;
    if (!ok) allCorePass = false;
    console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${cls}: ${pct}%`);
  }
  if (!allCorePass) {
    fail('one or more core/ classes are below threshold.');
  }
}

console.log('\nCoverage gate passed.');
