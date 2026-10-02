import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { buildCanaryEntry } from '../src/crons/canary.mjs';

const FIXTURE_PATH = fileURLToPath(
  new URL('./fixtures/scout_entry_keys.json', import.meta.url),
);

function fixtureKeys() {
  const raw = readFileSync(FIXTURE_PATH, 'utf8');
  return JSON.parse(raw);
}

test('the canary payload writes exactly the keys a fully populated ScoutEntry emits', () => {
  const entry = buildCanaryEntry();
  assert.deepEqual([...Object.keys(entry)].sort(), [...fixtureKeys()].sort());
});

test('every fixture key is actually populated in the canary payload, not merely present as undefined', () => {
  const entry = buildCanaryEntry();
  for (const key of fixtureKeys()) {
    assert.notEqual(entry[key], undefined, `${key} must be set`);
  }
});
