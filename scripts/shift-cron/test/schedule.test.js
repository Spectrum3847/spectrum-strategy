'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { applyAcceptedTrades } = require('../lib/schedule');

const ROTATIONS = [
  { uid: 'u0', name: 'Scouter 0', shifts: [{ startMatch: 1, endMatch: 6 }] },
  { uid: 'u1', name: 'Scouter 1', shifts: [{ startMatch: 7, endMatch: 12 }] },
];

test('a pending trade does not change the rotation', () => {
  const trades = [
    {
      status: 'pending',
      requesterUid: 'u0',
      targetUid: 'u1',
      requesterBlock: { startMatch: 1, endMatch: 6 },
    },
  ];
  const result = applyAcceptedTrades(ROTATIONS, trades);
  assert.deepEqual(
    result.find((r) => r.uid === 'u0').shifts,
    [{ startMatch: 1, endMatch: 6 }],
  );
});

test('an accepted one-way trade moves the block to the target', () => {
  const trades = [
    {
      status: 'accepted',
      requesterUid: 'u0',
      targetUid: 'u1',
      requesterBlock: { startMatch: 1, endMatch: 6 },
    },
  ];
  const result = applyAcceptedTrades(ROTATIONS, trades);
  assert.deepEqual(result.find((r) => r.uid === 'u0').shifts, []);
  assert.deepEqual(result.find((r) => r.uid === 'u1').shifts, [
    { startMatch: 7, endMatch: 12 },
    { startMatch: 1, endMatch: 6 },
  ]);
});

test('an accepted two-way swap trades both blocks', () => {
  const trades = [
    {
      status: 'accepted',
      requesterUid: 'u0',
      targetUid: 'u1',
      requesterBlock: { startMatch: 1, endMatch: 6 },
      targetBlock: { startMatch: 7, endMatch: 12 },
    },
  ];
  const result = applyAcceptedTrades(ROTATIONS, trades);
  assert.deepEqual(result.find((r) => r.uid === 'u0').shifts, [
    { startMatch: 7, endMatch: 12 },
  ]);
  assert.deepEqual(result.find((r) => r.uid === 'u1').shifts, [
    { startMatch: 1, endMatch: 6 },
  ]);
});

test('does not mutate the input rotations', () => {
  const before = JSON.stringify(ROTATIONS);
  applyAcceptedTrades(ROTATIONS, [
    {
      status: 'accepted',
      requesterUid: 'u0',
      targetUid: 'u1',
      requesterBlock: { startMatch: 1, endMatch: 6 },
    },
  ]);
  assert.equal(JSON.stringify(ROTATIONS), before);
});
