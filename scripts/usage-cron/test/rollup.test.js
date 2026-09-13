'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { buildRollup, windowStart, ranked } = require('../lib/rollup');

const NOW = new Date('2026-08-16T12:00:00.000Z');

function event(overrides = {}) {
  return {
    type: 'tab_open',
    detail: 'Strategy',
    deviceId: 'device-1',
    platform: 'android',
    appVersion: '1.0.0',
    createdAt: '2026-08-16T09:00:00.000Z',
    ...overrides,
  };
}

test('windowStart is the window before now, as an ISO string', () => {
  assert.equal(windowStart(NOW, 30), '2026-07-17T12:00:00.000Z');
});

test('counts tab opens and ranks them by use', () => {
  const rollup = buildRollup(
    [
      event({ detail: 'Scout' }),
      event({ detail: 'Strategy' }),
      event({ detail: 'Scout' }),
      event({ detail: 'Scout' }),
    ],
    NOW,
  );

  assert.deepEqual(rollup.tabs, [
    { name: 'Scout', count: 3 },
    { name: 'Strategy', count: 1 },
  ]);
});

test('splits by platform and app version', () => {
  const rollup = buildRollup(
    [
      event({ platform: 'android', appVersion: '1.0.0' }),
      event({ platform: 'ios', appVersion: '1.0.0' }),
      event({ platform: 'ios', appVersion: '1.1.0' }),
    ],
    NOW,
  );

  assert.deepEqual(rollup.platforms, [
    { name: 'ios', count: 2 },
    { name: 'android', count: 1 },
  ]);
  assert.deepEqual(rollup.appVersions, [
    { name: '1.0.0', count: 2 },
    { name: '1.1.0', count: 1 },
  ]);
});

test('a desktop-only tab is not read as unused, because platform is kept', () => {

  const rollup = buildRollup(
    [
      event({ detail: 'Database', platform: 'linux' }),
      event({ detail: 'Scout', platform: 'android' }),
      event({ detail: 'Scout', platform: 'android' }),
    ],
    NOW,
  );

  assert.equal(rollup.platforms.find((p) => p.name === 'linux').count, 1);
});

test('counts distinct devices, not events', () => {
  const rollup = buildRollup(
    [
      event({ deviceId: 'a' }),
      event({ deviceId: 'a' }),
      event({ deviceId: 'b' }),
    ],
    NOW,
  );

  assert.equal(rollup.eventsCounted, 3);
  assert.equal(rollup.deviceCount, 2);
});

test('drops events older than the window', () => {
  const rollup = buildRollup(
    [
      event({ createdAt: '2026-08-15T09:00:00.000Z' }),
      event({ createdAt: '2026-01-01T09:00:00.000Z', detail: 'Docs' }),
    ],
    NOW,
  );

  assert.equal(rollup.eventsCounted, 1);
  assert.equal(rollup.tabs.length, 1);
  assert.equal(rollup.tabs[0].name, 'Strategy');
});

test('drops an event with no usable timestamp rather than bucketing it', () => {

  const rollup = buildRollup(
    [event({ createdAt: undefined }), event({ createdAt: '' }), event()],
    NOW,
  );

  assert.equal(rollup.eventsCounted, 1);
});

test('only tab_open contributes to the tab counts', () => {
  const rollup = buildRollup(
    [
      event(),
      event({ type: 'app_open', detail: 'Strategy' }),
      event({ type: 'something_new', detail: 'Strategy' }),
    ],
    NOW,
  );

  assert.deepEqual(rollup.tabs, [{ name: 'Strategy', count: 1 }]);

  assert.equal(rollup.eventsCounted, 3);
});

test('an event with no detail does not become an empty-named tab', () => {
  const rollup = buildRollup([event({ detail: '' }), event()], NOW);

  assert.deepEqual(rollup.tabs, [{ name: 'Strategy', count: 1 }]);
});

test('the daily series is in date order and one entry per day', () => {
  const rollup = buildRollup(
    [
      event({ createdAt: '2026-08-16T01:00:00.000Z' }),
      event({ createdAt: '2026-08-14T01:00:00.000Z' }),
      event({ createdAt: '2026-08-16T02:00:00.000Z' }),
    ],
    NOW,
  );

  assert.deepEqual(rollup.daily, [
    { date: '2026-08-14', count: 1 },
    { date: '2026-08-16', count: 2 },
  ]);
});

test('an empty collection rolls up to zeroes, not to an error', () => {
  const rollup = buildRollup([], NOW);

  assert.equal(rollup.eventsCounted, 0);
  assert.equal(rollup.deviceCount, 0);
  assert.deepEqual(rollup.tabs, []);
  assert.deepEqual(rollup.daily, []);
});

test('ranked breaks ties by name, so the order does not wander', () => {
  assert.deepEqual(ranked({ Beta: 2, Alpha: 2 }), [
    { name: 'Alpha', count: 2 },
    { name: 'Beta', count: 2 },
  ]);
});
