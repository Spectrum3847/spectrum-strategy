import {
  getDocument,
  runQuery,
  whereEqualsQuery,
  patchDocument,
} from '../firestore.mjs';
import { isShiftStartingSoon, nextMatchNumber } from '../window.mjs';
import { applyAcceptedTrades } from '../schedule.mjs';
import { buildShiftStartDmText, buildTradeRequestDmText } from '../messages.mjs';
import { fetchEventSimple, fetchEventMatchesSimple } from '../tba.mjs';

const EVENT_WINDOW_PADDING_DAYS = 1;

function withinEventWindow(nowMs, startDate, endDate, paddingDays = EVENT_WINDOW_PADDING_DAYS) {
  if (!startDate && !endDate) return true;
  const padMs = paddingDays * 24 * 60 * 60 * 1000;
  const start = startDate ? Date.parse(`${startDate}T00:00:00Z`) : undefined;
  const end = endDate ? Date.parse(`${endDate}T23:59:59Z`) : undefined;
  if (Number.isFinite(start) && nowMs < start - padMs) return false;
  if (Number.isFinite(end) && nowMs > end + padMs) return false;
  return true;
}

async function resolveCurrentMatch(fetchImpl, tbaKey, eventKey) {
  const matches = await fetchEventMatchesSimple(fetchImpl, tbaKey, eventKey);
  if (!Array.isArray(matches)) return null;
  const played = matches
    .filter(
      (m) =>
        m.comp_level === 'qm' &&
        m.winning_alliance !== undefined &&
        m.winning_alliance !== null &&
        m.winning_alliance !== '',
    )
    .map((m) => m.match_number)
    .filter((n) => Number.isFinite(n));
  return nextMatchNumber(played);
}

async function runShift(ctx) {
  const { project, fetchImpl, nowMs, dryRun } = ctx;
  const opts = await ctx.opts();

  const activeEvent = await getDocument(project, 'appConfig/activeEvent', opts);
  const eventKey = activeEvent?.eventKey;
  if (!eventKey) {
    console.log('No appConfig/activeEvent.eventKey; nothing to do.');
    return { skipped: 'no-active-event' };
  }

  const schedule = await getDocument(project, `scoutShifts/${eventKey}`, opts);
  if (!schedule) {
    console.log(`No scoutShifts/${eventKey}; nothing to do.`);
    return { skipped: 'no-schedule' };
  }
  const rotations = Array.isArray(schedule.rotations) ? schedule.rotations : [];

  const apiKeys = await getDocument(project, 'appConfig/apiKeys', opts);
  const tbaKey = apiKeys?.tba ?? null;

  if (tbaKey) {
    const tbaEvent = await fetchEventSimple(fetchImpl, tbaKey, eventKey);
    if (tbaEvent && !withinEventWindow(nowMs, tbaEvent.start_date, tbaEvent.end_date)) {
      console.log(`Outside ${eventKey}'s event window; skipping shift DMs.`);
      return { skipped: 'outside-window' };
    }
  }

  const trades = await runQuery(
    project,
    whereEqualsQuery('shiftTrades', 'eventKey', eventKey),
    opts,
  );
  const tradesList = trades.map(({ id, data }) => ({ id, ...data }));

  const state = (await getDocument(project, 'appConfig/shiftCronState', opts)) || {};
  const dmedShifts = { ...(state.dmedShifts || {}) };
  const dmedTrades = { ...(state.dmedTrades || {}) };

  const stats = { shiftDmed: 0, tradeDmed: 0 };

  const currentMatch = tbaKey ? await resolveCurrentMatch(fetchImpl, tbaKey, eventKey) : null;
  if (currentMatch != null) {
    const effective = applyAcceptedTrades(rotations, tradesList);
    for (const rotation of effective) {
      if (!rotation.uid) continue;
      for (const block of rotation.shifts || []) {
        const key = `${eventKey}:${rotation.uid}:${block.startMatch}`;
        if (dmedShifts[key]) continue;
        if (!isShiftStartingSoon({ currentMatch, blockStartMatch: block.startMatch })) continue;
        const text = buildShiftStartDmText(block);
        if (dryRun) {
          console.log(`[dry run] would DM ${rotation.uid}: ${text}`);
          continue;
        }
        const sender = await ctx.dmSender();
        if (sender && (await sender(rotation.uid, text))) {
          dmedShifts[key] = true;
          stats.shiftDmed++;
        }
      }
    }
  } else {
    console.log('No current match from TBA; skipping shift-start DMs.');
  }

  for (const trade of tradesList) {
    if (trade.status !== 'pending' || dmedTrades[trade.id]) continue;
    const text = buildTradeRequestDmText({
      requesterDisplayName: trade.requesterDisplayName,
      startMatch: trade.requesterBlock?.startMatch,
      endMatch: trade.requesterBlock?.endMatch,
    });
    if (dryRun) {
      console.log(`[dry run] would DM ${trade.targetUid}: ${text}`);
      continue;
    }
    const sender = await ctx.dmSender();
    if (sender && (await sender(trade.targetUid, text))) {
      dmedTrades[trade.id] = true;
      stats.tradeDmed++;
    }
  }

  if (!dryRun) {
    await patchDocument(
      project,
      'appConfig/shiftCronState',
      { dmedShifts, dmedTrades },
      ['dmedShifts', 'dmedTrades'],
      opts,
    );
  }

  console.log(
    `Shift DMs${dryRun ? ' (dry run)' : ''}: ${stats.shiftDmed} shift-start, ` +
      `${stats.tradeDmed} trade-request.`,
  );
  return stats;
}

export { runShift, withinEventWindow };
