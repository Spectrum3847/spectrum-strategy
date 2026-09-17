'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  toBool,
  resolveStatboticsPath,
  getNestedValue,
  compareEntry,
  buildScouterDmText,
  normalizeEmail,
  escapeSlack,
} = require('../lib/compare');

test('toBool handles booleans, numbers, and strings', () => {
  assert.equal(toBool(true), true);
  assert.equal(toBool(0), false);
  assert.equal(toBool(2), true);
  assert.equal(toBool('true'), true);
  assert.equal(toBool('YES'), true);
  assert.equal(toBool('1'), true);
  assert.equal(toBool('no'), false);
  assert.equal(toBool(null), false);
});

test('resolveStatboticsPath substitutes alliance and legacy prefixes', () => {
  assert.equal(
    resolveStatboticsPath('{alliance}_breakdown.autoPoints', 'blue'),
    'blue_breakdown.autoPoints',
  );
  assert.equal(
    resolveStatboticsPath('red_breakdown.autoPoints', 'blue'),
    'blue_breakdown.autoPoints',
  );
  assert.equal(
    resolveStatboticsPath('blue_breakdown.autoPoints', 'red'),
    'red_breakdown.autoPoints',
  );
});

test('getNestedValue walks dotted paths and tolerates gaps', () => {
  const obj = { a: { b: { c: 7 } } };
  assert.equal(getNestedValue(obj, 'a.b.c'), 7);
  assert.equal(getNestedValue(obj, 'a.x.c'), undefined);
  assert.equal(getNestedValue(null, 'a'), undefined);
});

const cfg = {
  perFieldTolerancePct: 50,
  perFieldAbsoluteMin: 2,
  minWrongFields: 3,
  minWrongFraction: 0.5,
  egregiousAbsMin: 5,
  egregiousPct: 200,
  mappings: [
    { scoutFieldCode: 'auto_a', statboticsPath: '{alliance}_breakdown.a' },
    { scoutFieldCode: 'auto_b', statboticsPath: '{alliance}_breakdown.b' },
    { scoutFieldCode: 'auto_c', statboticsPath: '{alliance}_breakdown.c' },
    {
      scoutFieldCode: 'climbed',
      statboticsPath: '{alliance}_breakdown.climb',
      type: 'boolean',
    },
  ],
};

function entryWith(fieldValues, alliance = 'Red') {
  return { alliance, fieldValues };
}

function matchWith(breakdown) {
  return { red_breakdown: breakdown };
}

test('compareEntry does not fire when values are within tolerance', () => {
  const result = compareEntry(
    entryWith({ auto_a: 10, auto_b: 5, auto_c: 3, climbed: true }),
    matchWith({ a: 10, b: 6, c: 3, climb: 1 }),
    cfg,
  );
  assert.equal(result.comparedCount, 4);
  assert.equal(result.wrongCount, 0);
  assert.equal(result.fires, false);
});

test('compareEntry fires on the majority trigger', () => {

  const result = compareEntry(
    entryWith({ auto_a: 30, auto_b: 20, auto_c: 15, climbed: true }),
    matchWith({ a: 10, b: 5, c: 3, climb: 1 }),
    cfg,
  );
  assert.equal(result.comparedCount, 4);
  assert.equal(result.wrongCount, 3);
  assert.equal(result.fires, true);
  assert.deepEqual(
    result.flaggedFields.map((f) => f.fieldCode),
    ['auto_a', 'auto_b', 'auto_c'],
  );
});

test('compareEntry fires on a single egregious field', () => {

  const result = compareEntry(
    entryWith({ auto_a: 40, auto_b: 5, auto_c: 3, climbed: true }),
    matchWith({ a: 10, b: 5, c: 3, climb: 1 }),
    cfg,
  );
  assert.equal(result.wrongCount, 1);
  assert.equal(result.egregious, true);
  assert.equal(result.fires, true);
});

test('compareEntry respects the absolute floor on small diffs', () => {

  const result = compareEntry(
    entryWith({ auto_a: 2, auto_b: 2, auto_c: 2 }),
    matchWith({ a: 1, b: 1, c: 1 }),
    cfg,
  );
  assert.equal(result.wrongCount, 0);
  assert.equal(result.fires, false);
});

test('compareEntry counts boolean mismatches toward the majority', () => {
  const result = compareEntry(
    entryWith({ auto_a: 30, auto_b: 20, climbed: false }),
    matchWith({ a: 10, b: 5, climb: 1 }),
    cfg,
  );
  assert.equal(result.comparedCount, 3);
  assert.equal(result.wrongCount, 3);
  assert.equal(result.fires, true);
});

test('compareEntry compares nothing when the mapping misses the entry', () => {
  const result = compareEntry(
    entryWith({ other_field: 4 }),
    matchWith({ a: 10 }),
    cfg,
  );
  assert.equal(result.comparedCount, 0);
  assert.equal(result.fires, false);
});

test('compareEntry resolves the blue alliance side', () => {
  const result = compareEntry(
    entryWith({ auto_a: 10 }, 'Blue'),
    { blue_breakdown: { a: 10 }, red_breakdown: { a: 99 } },
    { ...cfg, minWrongFields: 1 },
  );
  assert.equal(result.comparedCount, 1);
  assert.equal(result.wrongCount, 0);
});

test('escapeSlack escapes ampersand and angle brackets', () => {
  assert.equal(escapeSlack('a & b < c > d'), 'a &amp; b &lt; c &gt; d');
  assert.equal(escapeSlack(null), '');
  assert.equal(escapeSlack(42), '42');
});

test('buildScouterDmText addresses the scouter and escapes input', () => {
  const text = buildScouterDmText({
    egregious: true,
    tbaMatchKey: '2026test_qm1',
    teamNumber: 3847,
    wrongCount: 2,
    comparedCount: 5,
    flaggedFields: [{ fieldCode: 'a<b>', scoutedValue: '<x>', officialValue: 1 }],
  });
  assert.match(text, /your scouting for match 2026test_qm1 \(team 3847\)/);
  assert.match(text, /likely has a wrong entry/);
  assert.match(text, /2\/5 fields/);
  assert.equal(text.includes('<b>'), false);
  assert.equal(text.includes('<x>'), false);

  assert.equal(text.includes('Scouter:'), false);
});

test('normalizeEmail lowercases and trims; non-strings become empty', () => {
  assert.equal(normalizeEmail('  Foo@Bar.COM '), 'foo@bar.com');
  assert.equal(normalizeEmail(null), '');
  assert.equal(normalizeEmail(123), '');
});
