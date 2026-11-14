import { test } from 'node:test';
import assert from 'node:assert/strict';

import { runJob } from '../src/index.mjs';
import { buildPushEnv, EVENT_KEY, fcm, readPush, subscriptionDoc } from './support/push_env.mjs';

const shift = (startMatch, extra = {}) => ({ startMatch, endMatch: startMatch + 5, ...extra });

async function scenario(overrides = {}) {
  const subscriptions = {
    s1: await subscriptionDoc('u1', fcm('u1-phone')),
    s2: await subscriptionDoc('u2', fcm('u2-phone')),
    ...overrides.subscriptions,
  };
  return buildPushEnv({
    rotations: [
      { uid: 'u1', shifts: [shift(11, { station: 'R1' })] },
      { uid: 'u2', shifts: [shift(12)] },
    ],
    ...overrides,
    subscriptions,
  });
}

test('pushes a scout 3 matches before a shift, and not 4', async () => {
  const { env, pushes } = await scenario();
  const result = await runJob(env, 'shift');

  assert.equal(result.shiftPushed, 1);
  assert.deepEqual(
    pushes.map((p) => p.url),
    [fcm('u1-phone')],
  );
});

test('the push window opens at 3 matches out and closes when the shift starts', async () => {
  const cases = [
    { start: 12, due: false },
    { start: 11, due: true },
    { start: 9, due: true },
    { start: 8, due: true },
    { start: 7, due: false },
  ];
  for (const { start, due } of cases) {
    const { env, pushes } = await buildPushEnv({
      rotations: [{ uid: 'u1', shifts: [shift(start)] }],
      subscriptions: { s1: await subscriptionDoc('u1', fcm('u1-phone')) },
    });
    await runJob(env, 'shift');
    assert.equal(pushes.length, due ? 1 : 0, `block starting at ${start}`);
  }
});

test('the device receives the match range and station, and tapping opens the Scout tab', async () => {
  const { env, pushes, store } = await scenario();
  await runJob(env, 'shift');
  assert.equal(pushes.length, 1);

  const { headers, body } = pushes[0].init;
  assert.equal(headers['Content-Encoding'], 'aes128gcm');
  assert.equal(headers.Urgency, 'high');
  assert.deepEqual(await readPush(pushes[0].url, body), {
    title: 'Your scouting shift starts in 3 matches',
    body: 'Scout matches 11-16 at R1. Head to the stands.',
    tag: `shift-${EVENT_KEY}-11`,
    url: '/scout',
  });
  assert.ok(store.pushSubscriptions.s1, 'a healthy subscription stays');
});

test('a scout gets one reminder per shift: a second run against the saved state sends nothing', async () => {
  const first = await scenario();
  await runJob(first.env, 'shift');
  assert.equal(first.pushes.length, 1);
  const saved = first.patches.at(-1);
  assert.equal(saved.pushedShifts[`${EVENT_KEY}:u1:11`], true);

  const second = await scenario({ state: saved });
  const result = await runJob(second.env, 'shift');
  assert.equal(result.shiftPushed, 0);
  assert.equal(second.pushes.length, 0);
});

test('the push dedupe is separate from the Slack one', async () => {
  const { env, pushes } = await scenario({
    state: { dmedShifts: { [`${EVENT_KEY}:u1:11`]: true } },
  });
  await runJob(env, 'shift');
  assert.equal(pushes.length, 1);
});

test('a subscription the push service answers 410 or 404 to is deleted', async () => {
  const { env, store } = await scenario({
    pushStatus: { [fcm('u1-phone')]: 410, [fcm('u1-old')]: 404 },
    subscriptions: { s3: await subscriptionDoc('u1', fcm('u1-old')) },
  });
  const result = await runJob(env, 'shift');
  assert.equal(result.shiftPushed, 0);
  assert.equal(store.pushSubscriptions.s1, undefined);
  assert.equal(store.pushSubscriptions.s3, undefined);
  assert.ok(store.pushSubscriptions.s2, "another scout's subscription is untouched");
  assert.equal(result.failed, undefined, 'a gone subscription is cleanup, not a failure');
});

test('one dead device does not stop the scout\'s other device, and the shift is settled', async () => {
  const { env, store, patches } = await scenario({
    pushStatus: { [fcm('u1-tablet')]: 410 },
    subscriptions: { s3: await subscriptionDoc('u1', fcm('u1-tablet')) },
  });
  const result = await runJob(env, 'shift');
  assert.equal(result.shiftPushed, 1);
  assert.equal(store.pushSubscriptions.s3, undefined);
  assert.ok(store.pushSubscriptions.s1);
  assert.equal(patches.at(-1).pushedShifts[`${EVENT_KEY}:u1:11`], true);
});

test('a push service outage is reported and retried on the next run', async () => {
  const { env, patches, store } = await scenario({ pushStatus: { [fcm('u1-phone')]: 503 } });
  const result = await runJob(env, 'shift');
  assert.equal(result.failed, 1);
  assert.equal(patches.at(-1).pushedShifts?.[`${EVENT_KEY}:u1:11`], undefined);
  assert.ok(store.pushSubscriptions.s1, 'a transient failure keeps the subscription');
});

test('a scout with no saved device is not marked, so a later subscription still gets the reminder', async () => {
  const { env, patches, pushes } = await buildPushEnv({
    rotations: [{ uid: 'u1', shifts: [shift(11)] }],
    subscriptions: {},
  });
  await runJob(env, 'shift');
  assert.equal(pushes.length, 0);
  assert.equal(patches.at(-1).pushedShifts?.[`${EVENT_KEY}:u1:11`], undefined);
});

test('without the VAPID secrets the shift job still runs and sends no push', async () => {
  const { env, pushes, store } = await scenario({ vapid: false });
  const result = await runJob(env, 'shift');
  assert.equal(result.shiftPushed, 0);
  assert.equal(result.failed, undefined);
  assert.equal(pushes.length, 0);
  assert.ok(store.pushSubscriptions.s1);
});

test('a dry run sends no push and writes no state', async () => {
  const { env, pushes, patches } = await scenario({ dryRun: true });
  await runJob(env, 'shift');
  assert.equal(pushes.length, 0);
  assert.equal(patches.length, 0);
});

test('the subscriptions are read once per run, however many scouts are due', async () => {
  const requests = [];
  const { env } = await buildPushEnv({
    rotations: [
      { uid: 'u1', shifts: [shift(11)] },
      { uid: 'u2', shifts: [shift(11)] },
      { uid: 'u3', shifts: [shift(11)] },
    ],
    subscriptions: {
      s1: await subscriptionDoc('u1', fcm('a')),
      s2: await subscriptionDoc('u2', fcm('b')),
      s3: await subscriptionDoc('u3', fcm('c')),
    },
  });
  const original = env.fetchImpl;
  env.fetchImpl = async (url, init) => {
    requests.push(String(url));
    return original(url, init);
  };
  const result = await runJob(env, 'shift');
  assert.equal(result.shiftPushed, 3);
  assert.equal(requests.filter((u) => u.includes('/pushSubscriptions')).length, 1);
});
