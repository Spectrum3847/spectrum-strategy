'use strict';

const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const { isFirestoreQuotaExceeded, parseServiceAccount } = require('shared-cron-utils');

const {
  compareEntry,
  buildScouterDmText,
  normalizeEmail,
} = require('./lib/compare');
const { computeWindowStart } = require('./lib/window');

const STATBOTICS_BASE = 'https://api.statbotics.io/v3';
const STATBOTICS_TIMEOUT_MS = 10_000;
const SLACK_TIMEOUT_MS = 5_000;
const WINDOW_MINUTES = Number(process.env.WINDOW_MINUTES) || 20;

const PLATFORM_PROJECT_ID = 'spectrumtasks-81c63';

async function main() {
  const rawCredential = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!rawCredential) {
    console.log(
      'FIREBASE_SERVICE_ACCOUNT is not set; skipping run. ' +
        'See docs/scouting-accuracy-slack-setup.md for setup.',
    );
    return;
  }

  initializeApp({ credential: cert(parseServiceAccount(rawCredential)) });
  const db = getFirestore();

  let dmSenderPromise;
  const dmSender = () =>
    (dmSenderPromise ??= buildScouterDmSender(rawCredential, db));

  const cfgDoc = await db.doc('appConfig/accuracyMapping').get();
  if (!cfgDoc.exists) {
    console.log('No appConfig/accuracyMapping doc; nothing to compare.');
    return;
  }
  const cfg = cfgDoc.data() || {};
  if (!Array.isArray(cfg.mappings) || cfg.mappings.length === 0) {
    console.log('accuracyMapping has no mappings; nothing to compare.');
    return;
  }

  const watermarkRef = db.doc('appConfig/accuracyCron');
  const watermarkDoc = await watermarkRef.get();
  const watermark = watermarkDoc.exists
    ? watermarkDoc.data().lastScanEnd
    : null;
  const scanStart = new Date().toISOString();
  const windowStart = computeWindowStart({
    watermark,
    nowMs: Date.now(),
    fallbackMinutes: WINDOW_MINUTES,
  });
  const snapshot = await db
    .collection('scoutEntries')
    .where('updatedAt', '>=', windowStart)
    .get();
  console.log(
    `${snapshot.size} entries updated since ${windowStart} ` +
      `(watermark: ${watermark || 'none'}).`,
  );

  const matchCache = new Map();
  const stats = { created: 0, refreshed: 0, deleted: 0, skipped: 0, dmed: 0 };

  for (const doc of snapshot.docs) {
    const entryId = doc.id;
    const entry = doc.data();

    if (!entry.tbaMatchKey) {
      stats.deleted += await deleteAlert(db, entryId);
      continue;
    }

    const matchData = await fetchMatchCached(entry.tbaMatchKey, matchCache);
    if (matchData === undefined || matchData === null) {

      stats.skipped++;
      continue;
    }

    const result = compareEntry(entry, matchData, cfg);
    if (result.comparedCount === 0) {

      stats.skipped++;
      continue;
    }

    if (!result.fires) {
      stats.deleted += await deleteAlert(db, entryId);
      continue;
    }

    const alertRef = db.collection('accuracyAlerts').doc(entryId);
    const existing = await alertRef.get();
    const prevAck = existing.exists && existing.data().acknowledged === true;
    const prevCreatedAt = existing.exists
      ? existing.data().createdAt
      : new Date().toISOString();

    const alert = {
      entryId,
      teamNumber: entry.teamNumber || 0,
      tbaMatchKey: entry.tbaMatchKey,
      authorUid: entry.authorUid || '',
      authorDisplayName: entry.authorDisplayName || '',
      flaggedFields: result.flaggedFields,
      comparedCount: result.comparedCount,
      wrongCount: result.wrongCount,
      egregious: result.egregious,
      createdAt: prevCreatedAt,
      updatedAt: new Date().toISOString(),
      acknowledged: prevAck,
    };
    await alertRef.set(alert);

    if (existing.exists) {
      stats.refreshed++;
    } else {
      stats.created++;

      const dmScouter = alert.authorUid ? await dmSender() : null;
      if (dmScouter) {
        try {
          if (await dmScouter(alert)) stats.dmed++;
        } catch (err) {
          console.error(
            `scouter DM failed for ${entryId}:`,
            err && err.message ? err.message : err,
          );
        }
      }
    }
  }

  stats.deleted += await deleteOrphanedAlerts(db);

  await watermarkRef.set({ lastScanEnd: scanStart }, { merge: true });

  console.log(
    `Done: ${stats.created} created, ${stats.refreshed} refreshed, ` +
      `${stats.deleted} deleted, ${stats.skipped} skipped, ` +
      `${stats.dmed} scouter DM(s).`,
  );
}

async function buildScouterDmSender(ourRawCredential, db) {
  const botToken = process.env.SLACK_BOT_TOKEN;
  if (!botToken) return null;
  const platformRaw =
    process.env.SPECTRUM_PLATFORM_SERVICE_ACCOUNT || ourRawCredential;
  let emailToSlackId;
  let uidToEmail;
  try {
    const platformApp = initializeApp(
      {
        credential: cert(parseServiceAccount(platformRaw)),
        projectId: PLATFORM_PROJECT_ID,
      },
      'platform',
    );
    const usersSnap = await getFirestore(platformApp).collection('users').get();
    emailToSlackId = new Map();
    for (const doc of usersSnap.docs) {
      const data = doc.data();
      const email = normalizeEmail(data.email);
      const slackId =
        typeof data.slackId === 'string' ? data.slackId.trim() : '';
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
  return async function dmScouter(alert) {
    const email = uidToEmail.get(alert.authorUid);
    const slackId = email ? emailToSlackId.get(email) : null;
    if (!slackId) return false;
    return postSlackDmSafe(botToken, slackId, buildScouterDmText(alert));
  };
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
      console.error(`scouter DM: Slack returned ${data.error || res.status}`);
      return false;
    }
    return true;
  } catch (err) {
    console.error('scouter DM: fetch error', err && err.message ? err.message : err);
    return false;
  } finally {
    clearTimeout(timer);
  }
}

async function deleteAlert(db, entryId) {
  const ref = db.collection('accuracyAlerts').doc(entryId);
  const doc = await ref.get();
  if (!doc.exists) return 0;
  await ref.delete();
  return 1;
}

async function deleteOrphanedAlerts(db) {
  const alerts = await db.collection('accuracyAlerts').get();
  let deleted = 0;
  for (const alertDoc of alerts.docs) {
    const entry = await db.collection('scoutEntries').doc(alertDoc.id).get();
    if (!entry.exists) {
      await alertDoc.ref.delete();
      deleted++;
    }
  }
  return deleted;
}

async function fetchMatchCached(tbaMatchKey, cache) {
  if (cache.has(tbaMatchKey)) return cache.get(tbaMatchKey);
  let result;
  try {
    result = await fetchJsonWithTimeout(
      `${STATBOTICS_BASE}/match/${encodeURIComponent(tbaMatchKey)}`,
      STATBOTICS_TIMEOUT_MS,
    );
  } catch (err) {
    console.error(
      `Statbotics fetch error for ${tbaMatchKey}:`,
      err.message || err,
    );
    result = undefined;
  }
  cache.set(tbaMatchKey, result);
  return result;
}

async function fetchJsonWithTimeout(url, timeoutMs) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      headers: { Accept: 'application/json' },
      signal: ctl.signal,
    });
    if (res.status === 404) return null;
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

main().catch((err) => {
  if (isFirestoreQuotaExceeded(err)) {
    console.warn(
      'accuracy-cron: Firestore quota exhausted; skipping this run. ' +
        'Nothing to do until the quota resets.',
    );
    return;
  }
  console.error('accuracy-cron failed:', err);
  process.exitCode = 1;
});
