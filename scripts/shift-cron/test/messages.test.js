'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildShiftStartDmText,
  buildTradeRequestDmText,
  matchRangeLabel,
} = require('../lib/messages');

test('matchRangeLabel collapses a single-match block', () => {
  assert.equal(matchRangeLabel(5, 5), 'match 5');
});

test('matchRangeLabel spans a multi-match block', () => {
  assert.equal(matchRangeLabel(1, 6), 'matches 1-6');
});

test('shift start DM mentions the match range', () => {
  const text = buildShiftStartDmText({ startMatch: 7, endMatch: 12 });
  assert.match(text, /matches 7-12/);
});

test('trade request DM names the requester and the block', () => {
  const text = buildTradeRequestDmText({
    requesterDisplayName: 'Alex',
    startMatch: 3,
    endMatch: 3,
  });
  assert.match(text, /Alex/);
  assert.match(text, /match 3/);
});

test('trade request DM falls back when the requester has no name', () => {
  const text = buildTradeRequestDmText({
    requesterDisplayName: '',
    startMatch: 3,
    endMatch: 3,
  });
  assert.match(text, /A teammate/);
});
