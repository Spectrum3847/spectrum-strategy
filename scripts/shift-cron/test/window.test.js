'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { isShiftStartingSoon, nextMatchNumber } = require('../lib/window');

test('fires 2 matches out', () => {
  assert.equal(
    isShiftStartingSoon({ currentMatch: 10, blockStartMatch: 12 }),
    true,
  );
});

test('fires 3 matches out', () => {
  assert.equal(
    isShiftStartingSoon({ currentMatch: 10, blockStartMatch: 13 }),
    true,
  );
});

test('does not fire 1 match out', () => {
  assert.equal(
    isShiftStartingSoon({ currentMatch: 10, blockStartMatch: 11 }),
    false,
  );
});

test('does not fire 4 matches out', () => {
  assert.equal(
    isShiftStartingSoon({ currentMatch: 10, blockStartMatch: 14 }),
    false,
  );
});

test('does not fire once the shift has started', () => {
  assert.equal(
    isShiftStartingSoon({ currentMatch: 12, blockStartMatch: 12 }),
    false,
  );
  assert.equal(
    isShiftStartingSoon({ currentMatch: 13, blockStartMatch: 12 }),
    false,
  );
});

test('respects custom bounds', () => {
  assert.equal(
    isShiftStartingSoon({
      currentMatch: 10,
      blockStartMatch: 11,
      lowerMatches: 1,
      upperMatches: 1,
    }),
    true,
  );
});

test('non-finite input never fires', () => {
  assert.equal(
    isShiftStartingSoon({ currentMatch: NaN, blockStartMatch: 12 }),
    false,
  );
  assert.equal(
    isShiftStartingSoon({ currentMatch: 10, blockStartMatch: undefined }),
    false,
  );
});

test('nextMatchNumber is 1 with no played matches', () => {
  assert.equal(nextMatchNumber([]), 1);
  assert.equal(nextMatchNumber(undefined), 1);
});

test('nextMatchNumber is one past the highest played match', () => {
  assert.equal(nextMatchNumber([1, 2, 3]), 4);
  assert.equal(nextMatchNumber([5, 1, 3]), 6);
});
