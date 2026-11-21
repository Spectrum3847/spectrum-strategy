import { test } from 'node:test';
import assert from 'node:assert/strict';

import { isShiftPushDue, isShiftStartingSoon, nextMatchNumber } from '../src/window.mjs';

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

test('push is due from 3 matches out until the shift starts', () => {
  const due = (away) => isShiftPushDue({ currentMatch: 10, blockStartMatch: 10 + away });
  assert.equal(due(4), false);
  assert.equal(due(3), true);
  assert.equal(due(1), true);
  assert.equal(due(0), true);
  assert.equal(due(-1), false);
});

test('push is not due without usable match numbers', () => {
  assert.equal(isShiftPushDue({ currentMatch: null, blockStartMatch: 12 }), false);
  assert.equal(isShiftPushDue({ currentMatch: 10, blockStartMatch: undefined }), false);
});
