import { getAccessToken } from './google_auth.mjs';
import { parseServiceAccount } from './service_account.mjs';
import {
  getDocument,
  listCollection,
  runQuery,
  whereEqualsQuery,
  patchDocument,
  FirestoreQuotaError,
} from './firestore.mjs';
import { isShiftStartingSoon, nextMatchNumber } from './window.mjs';
import { applyAcceptedTrades } from './schedule.mjs';
import { buildShiftStartDmText, buildTradeRequestDmText } from './messages.mjs';

const TBA_BASE = 'https://www.thebluealliance.com/api/v3';
const TBA_TIMEOUT_MS = 10_000;
const SLACK_TIMEOUT_MS = 5_000;

const EVENT_WINDOW_PADDING_DAYS = 1;

function isDryRun(env) {
  return env.DRY_RUN === '1' || env.DRY_RUN === 'true';
}

async function fetchJsonWithTimeout(fetchImpl, url, headers, timeoutMs) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const res = await fetchImpl(url, { headers, signal: ctl.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

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
  try {
    const matches = await fetchJsonWithTimeout(
      fetchImpl,
      `${TBA_BASE}/event/${encodeURIComponent(eventKey)}/matches/simple`,
      { Accept: 'application/json', 'X-TBA-Auth-Key': tbaKey },
      TBA_TIMEOUT_MS,
    );
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
  } catch (err) {
    console.error('TBA matches fetch error:', err && err.message ? err.message : err);
    return null;
  }
}

async function fetchTbaEventSimple(fetchImpl, tbaKey, eventKey) {
  try {
    return await fetchJsonWithTimeout(
      fetchImpl,
      `${TBA_BASE}/event/${encodeURIComponent(eventKey)}/simple`,
      { Accept: 'application/json', 'X-TBA-Auth-Key': tbaKey },
      TBA_TIMEOUT_MS,
    );
  } catch (err) {
    console.error('TBA event fetch error:', err && err.message ? err.message : err);
    return null;
  }
}

function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

async function postSlackDmSafe(fetchImpl, botToken, slackId, text) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), SLACK_TIMEOUT_MS);
  try {
    const res = await fetchImpl('https://slack.com/api/chat.postMessage', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        Authorization: `Bearer ${botToken}`,
      },
      body: JSON.stringify({ channel: slackId, text }),
      signal: ctl.signal,
    });
    const data = await res.json().catch(() => ({}));
    if (!data.ok) {
      console.error(`shift DM: Slack returned ${data.error || res.status}`);
      return false;
    }
    return true;
  } catch (err) {
    console.error('shift DM: fetch error', err && err.message ? err.message : err);
    return false;
  } finally {
    clearTimeout(timer);
  }
}

async function buildDmSender({
  slackToken,
  platformProject,
  platformAccount,
  firebaseProject,
  firestoreOpts,
  fetchImpl,
}) {
  let emailToSlackId;
  let uidToEmail;
  try {
    const platformToken = await getAccessToken(platformAccount, { fetchImpl });
    const platformOpts = { token: platformToken, fetchImpl };
    const users = await listCollection(platformProject, 'users', platformOpts);
    emailToSlackId = new Map();
    for (const { data } of users) {
      const email = normalizeEmail(data.email);
      const slackId = typeof data.slackId === 'string' ? data.slackId.trim() : '';
      if (email && slackId) emailToSlackId.set(email, slackId);
    }

    const profiles = await listCollection(firebaseProject, 'userProfiles', firestoreOpts);
    uidToEmail = new Map();
    for (const { id, data } of profiles) {
      const email = normalizeEmail(data.email);
      if (email) uidToEmail.set(id, email);
    }
  } catch (err) {
    console.log(
      'Slack DM disabled: cannot read platform users or profiles (' +
        (err && err.message ? err.message : err) +
        ').',
    );
    return null;
  }
  return async function dmUid(uid, text) {
    const email = uidToEmail.get(uid);
    const slackId = email ? emailToSlackId.get(email) : null;
    if (!slackId) return false;
    return postSlackDmSafe(fetchImpl, slackToken, slackId, text);
  };
}

async function run(env) {
  const fetchImpl = env.fetchImpl ?? fetch;
  const nowMs = env.nowMs ?? Date.now();
  const dryRun = isDryRun(env);

  const rawFirebase = env.FIREBASE_SERVICE_ACCOUNT;
  const rawPlatform = env.SPECTRUM_PLATFORM_SERVICE_ACCOUNT;
  const slackToken = env.SLACK_BOT_TOKEN;
  if (!rawFirebase || !rawPlatform || !slackToken) {
    console.log(
      'Missing FIREBASE_SERVICE_ACCOUNT, SPECTRUM_PLATFORM_SERVICE_ACCOUNT or ' +
        'SLACK_BOT_TOKEN; skipping run.',
    );
    return { skipped: 'missing-secrets' };
  }

  const firebaseProject = env.FIREBASE_PROJECT;
  const platformProject = env.PLATFORM_PROJECT;
  const firebaseAccount = parseServiceAccount(rawFirebase);
  const platformAccount = parseServiceAccount(rawPlatform);

  try {
    const token = await getAccessToken(firebaseAccount, { fetchImpl });
    const firestoreOpts = { token, fetchImpl };

    const activeEvent = await getDocument(firebaseProject, 'appConfig/activeEvent', firestoreOpts);
    const eventKey = activeEvent?.eventKey;
    if (!eventKey) {
      console.log('No appConfig/activeEvent.eventKey; nothing to do.');
      return { skipped: 'no-active-event' };
    }

    const schedule = await getDocument(firebaseProject, `scoutShifts/${eventKey}`, firestoreOpts);
    if (!schedule) {
      console.log(`No scoutShifts/${eventKey}; nothing to do.`);
      return { skipped: 'no-schedule' };
    }
    const rotations = Array.isArray(schedule.rotations) ? schedule.rotations : [];

    const apiKeys = await getDocument(firebaseProject, 'appConfig/apiKeys', firestoreOpts);
    const tbaKey = apiKeys?.tba ?? null;

    if (tbaKey) {
      const tbaEvent = await fetchTbaEventSimple(fetchImpl, tbaKey, eventKey);
      if (tbaEvent && !withinEventWindow(nowMs, tbaEvent.start_date, tbaEvent.end_date)) {
        console.log(`Outside ${eventKey}'s event window; skipping run.`);
        return { skipped: 'outside-window' };
      }
    }

    const trades = await runQuery(
      firebaseProject,
      whereEqualsQuery('shiftTrades', 'eventKey', eventKey),
      firestoreOpts,
    );
    const tradesList = trades.map(({ id, data }) => ({ id, ...data }));

    const state = (await getDocument(firebaseProject, 'appConfig/shiftCronState', firestoreOpts)) || {};
    const dmedShifts = { ...(state.dmedShifts || {}) };
    const dmedTrades = { ...(state.dmedTrades || {}) };

    const stats = { shiftDmed: 0, tradeDmed: 0 };
    let dmSenderPromise;
    const dmSender = () =>
      (dmSenderPromise ??= buildDmSender({
        slackToken,
        platformProject,
        platformAccount,
        firebaseProject,
        firestoreOpts,
        fetchImpl,
      }));

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
          const sender = await dmSender();
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
      const sender = await dmSender();
      if (sender && (await sender(trade.targetUid, text))) {
        dmedTrades[trade.id] = true;
        stats.tradeDmed++;
      }
    }

    if (!dryRun) {
      await patchDocument(
        firebaseProject,
        'appConfig/shiftCronState',
        { dmedShifts, dmedTrades },
        ['dmedShifts', 'dmedTrades'],
        firestoreOpts,
      );
    }

    console.log(
      `Done${dryRun ? ' (dry run)' : ''}: ${stats.shiftDmed} shift-start DM(s), ` +
        `${stats.tradeDmed} trade-request DM(s).`,
    );
    return stats;
  } catch (err) {
    if (err instanceof FirestoreQuotaError) {
      console.log(
        'Firestore quota exhausted while sending shift notifications; skipping run ' +
          'and retrying next schedule.',
      );
      return { skipped: 'quota' };
    }
    throw err;
  }
}

async function scheduled(event, env, ctx) {
  await run(env);
}

function constantTimeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function fetchHandler(request, env, ctx) {
  const url = new URL(request.url);
  if (url.pathname === '/') {
    return new Response(
      JSON.stringify({ ok: true, worker: 'spectrumstrategy-shift-reminders' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }
  if (url.pathname === '/run') {
    if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
    const expected = env.RUN_TOKEN;
    const given = request.headers.get('X-Run-Token') ?? '';
    if (!expected) return new Response('RUN_TOKEN is not set', { status: 503 });
    if (!constantTimeEqual(given, expected)) return new Response('Unauthorized', { status: 401 });
    const result = await run(env);
    return new Response(JSON.stringify({ ok: true, result }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  return new Response('Not found', { status: 404 });
}

export { run, withinEventWindow };
export default { scheduled, fetch: fetchHandler };
