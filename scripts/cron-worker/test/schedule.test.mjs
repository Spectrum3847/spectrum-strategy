import { test } from 'node:test';
import assert from 'node:assert/strict';

import { applyAcceptedTrades } from '../src/schedule.mjs';

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

test('a trade for a block the giver no longer has changes nothing', () => {

  const result = applyAcceptedTrades(ROTATIONS, [
    {
      status: 'accepted',
      requesterUid: 'u0',
      targetUid: 'u1',
      requesterBlock: { startMatch: 2, endMatch: 7 },
    },
  ]);
  assert.deepEqual(result, ROTATIONS);
});

test('the taker gets the block at the giver station', () => {
  const rotations = [
    { uid: 'u0', name: 'Scouter 0', shifts: [{ startMatch: 1, endMatch: 6, station: 'R2' }] },
    { uid: 'u1', name: 'Scouter 1', shifts: [] },
  ];
  const result = applyAcceptedTrades(rotations, [
    {
      status: 'accepted',
      requesterUid: 'u0',
      targetUid: 'u1',
      requesterBlock: { startMatch: 1, endMatch: 6 },
    },
  ]);
  assert.deepEqual(result[1].shifts, [{ startMatch: 1, endMatch: 6, station: 'R2' }]);
});

test('keeps every column when several names share the empty uid', () => {
  const rotations = [
    { uid: '', name: 'Typed A', shifts: [{ startMatch: 1, endMatch: 6 }] },
    { uid: '', name: 'Typed B', shifts: [{ startMatch: 7, endMatch: 12 }] },
    { uid: 'u2', name: 'Scouter 2', shifts: [] },
  ];
  const result = applyAcceptedTrades(rotations, [
    { status: 'accepted', requesterUid: '', targetUid: 'u2', requesterBlock: { startMatch: 1, endMatch: 6 } },
  ]);
  assert.equal(result.length, 3);
  assert.deepEqual(result, rotations);
});
