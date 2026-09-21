import { runQuery, whereQuery, setDocument } from '../firestore.mjs';
import { buildRollup, windowStart, WINDOW_DAYS } from './lib/usage_rollup.mjs';

const ROLLUP_DOC = 'telemetryRollup/current';

const ROLLUP_FIELDS = ['createdAt', 'deviceId', 'platform', 'appVersion', 'type', 'detail'];

const MAX_EVENTS = 20_000;

async function runUsage(ctx) {
  const { project } = ctx;
  const opts = await ctx.opts();

  const now = new Date(ctx.nowMs);
  const since = windowStart(now);

  const rows = await runQuery(
    project,
    whereQuery(
      'telemetry',
      [{ fieldPath: 'createdAt', op: 'GREATER_THAN_OR_EQUAL', value: since }],
      { select: ROLLUP_FIELDS, limit: MAX_EVENTS },
    ),
    opts,
  );
  if (rows.length >= MAX_EVENTS) {
    console.warn(
      `Read the ${MAX_EVENTS}-event cap; the rollup covers only part of the ` +
        `${WINDOW_DAYS}-day window.`,
    );
  }

  const rollup = buildRollup(
    rows.map(({ data }) => data),
    now,
  );
  await setDocument(project, ROLLUP_DOC, rollup, opts);

  console.log(
    `Rolled up ${rollup.eventsCounted} events from ${rollup.deviceCount} ` +
      `devices over ${WINDOW_DAYS} days into ${ROLLUP_DOC}.`,
  );
  return { eventsCounted: rollup.eventsCounted, deviceCount: rollup.deviceCount };
}

export { runUsage };
