'use strict';

const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const { isShiftStartingSoon, nextMatchNumber } = require('./lib/window');
const { applyAcceptedTrades } = require('./lib/schedule');
const { buildShiftStartDmText, buildTradeRequestDmText } = require('./lib/messages');
const { isFirestoreQuotaExceeded, parseServiceAccount } = require('shared-cron-utils');

const TBA_BASE = 'https://www.thebluealliance.com/api/v3';
const TBA_TIMEOUT_MS = 10_000;
const SLACK_TIMEOUT_MS = 5_000;

const PLATFORM_PROJECT_ID = 'spectrumtasks-81c63';

const isDryRun = () =>
  process.env.DRY_RUN === '1' ||
  process.env.DRY_RUN === 'true' ||
  process.argv.includes('--dry-run');

async function main() {
  const dryRun = isDryRun();
  const rawCredential = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!rawCredential) {
    console.log('FIREBASE_SERVICE_ACCOUNT is not set; skipping run.');
    return;
  }

  initializeApp({ credential: cert(parseServiceAccount(rawCredential)) });
  const db = getFirestore();

  try {
    const activeEventDoc = await db.doc('appConfig/activeEvent').get();
    const eventKey = activeEventDoc.exists ? activeEventDoc.data().eventKey : null;
    if (!eventKey) {
      console.log('No appConfig/activeEvent.eventKey; nothing to do.');
      return;
    }

    const scheduleDoc = await db.doc(`scoutShifts/${eventKey}`).get();
    if (!scheduleDoc.exists) {
      console.log(`No scoutShifts/${eventKey}; nothing to do.`);
      return;
    }
    const schedule = scheduleDoc.data();
    const rotations = Array.isArray(schedule.rotations) ? schedule.rotations : [];

    const tradesSnap = await db
      .collection('shiftTrades')
      .where('eventKey', '==', eventKey)
      .get();
    const trades = tradesSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));

    const stateRef = db.doc('appConfig/shiftCronState');
    const stateDoc = await stateRef.get();
    const state = stateDoc.exists ? stateDoc.data() : {};
    const dmedShifts = { ...(state.dmedShifts || {}) };
    const dmedTrades = { ...(state.dmedTrades || {}) };

    let dmSenderPromise;
    const dmSender = () => (dmSenderPromise ??= buildDmSender(rawCredential, db));

    const stats = { shiftDmed: 0, tradeDmed: 0 };

    const currentMatch = await resolveCurrentMatch(db, eventKey);
    if (currentMatch != null) {
      const effective = applyAcceptedTrades(rotations, trades);
      for (const rotation of effective) {
        if (!rotation.uid) continue;
        for (const block of rotation.shifts || []) {
          const key = `${eventKey}:${rotation.uid}:${block.startMatch}`;
          if (dmedShifts[key]) continue;
          if (
            !isShiftStartingSoon({
              currentMatch,
              blockStartMatch: block.startMatch,
            })
          ) {
            continue;
          }
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

    for (const trade of trades) {
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
      await stateRef.set({ dmedShifts, dmedTrades }, { merge: true });
    }

    console.log(
      `Done${dryRun ? ' (dry run)' : ''}: ${stats.shiftDmed} shift-start DM(s), ` +
        `${stats.tradeDmed} trade-request DM(s).`,
    );
  } catch (err) {
    if (isFirestoreQuotaExceeded(err)) {
      console.log(
        'Firestore quota exhausted while sending shift notifications; skipping run ' +
          'and retrying next schedule.',
      );
      return;
    }
    throw err;
  }
}

async function resolveCurrentMatch(db, eventKey) {
  const apiKeysDoc = await db.doc('appConfig/apiKeys').get();
  const tbaKey = apiKeysDoc.exists ? apiKeysDoc.data().tba : null;
  if (!tbaKey) return null;

  try {
    const matches = await fetchJsonWithTimeout(
      `${TBA_BASE}/event/${encodeURIComponent(eventKey)}/matches/simple`,
      TBA_TIMEOUT_MS,
      tbaKey,
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
    console.error('TBA fetch error:', err && err.message ? err.message : err);
    return null;
  }
}

async function buildDmSender(ourRawCredential, db) {
  const botToken = process.env.SLACK_BOT_TOKEN;
  if (!botToken) return null;
  const platformRaw = process.env.SPECTRUM_PLATFORM_SERVICE_ACCOUNT || ourRawCredential;
  let emailToSlackId;
  let uidToEmail;
  try {
    const platformApp = initializeApp(
      { credential: cert(parseServiceAccount(platformRaw)), projectId: PLATFORM_PROJECT_ID },
      'platform',
    );
    const usersSnap = await getFirestore(platformApp).collection('users').get();
    emailToSlackId = new Map();
    for (const doc of usersSnap.docs) {
      const data = doc.data();
      const email = normalizeEmail(data.email);
      const slackId = typeof data.slackId === 'string' ? data.slackId.trim() : '';
      if (email && slackId) emailToSlackId.set(email, slackId);
    }
    const profilesSnap = await db.collection('userProfiles').get();
    uidToEmail = new Map();
    for (const doc of profilesSnap.docs) {
      const email = normalizeEmail(doc.data().email);
      if (email) uidToEmail.set(doc.id, email);
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
    return postSlackDmSafe(botToken, slackId, text);
  };
}

function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

async function postSlackDmSafe(botToken, slackId, text) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), SLACK_TIMEOUT_MS);
  try {
    const res = await fetch('https://slack.com/api/chat.postMessage', {
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

async function fetchJsonWithTimeout(url, timeoutMs, tbaKey) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      headers: { Accept: 'application/json', 'X-TBA-Auth-Key': tbaKey },
      signal: ctl.signal,
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('shift-cron failed:', err);
    process.exitCode = 1;
  });
}

module.exports = { main };
