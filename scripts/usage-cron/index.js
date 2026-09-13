'use strict';

const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const { buildRollup, windowStart, WINDOW_DAYS } = require('./lib/rollup');
const { isFirestoreQuotaExceeded, parseServiceAccount } = require('shared-cron-utils');

const ROLLUP_DOC = 'telemetryRollup/current';

async function main() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) {
    console.log('FIREBASE_SERVICE_ACCOUNT is not set; nothing to do.');
    return;
  }

  initializeApp({ credential: cert(parseServiceAccount(raw)) });
  const db = getFirestore();

  const now = new Date();
  const since = windowStart(now);

  const snapshot = await db
    .collection('telemetry')
    .where('createdAt', '>=', since)
    .get();

  const events = snapshot.docs.map((doc) => doc.data());
  const rollup = buildRollup(events, now);

  await db.doc(ROLLUP_DOC).set(rollup);

  console.log(
    `Rolled up ${rollup.eventsCounted} events from ${rollup.deviceCount} ` +
      `devices over ${WINDOW_DAYS} days into ${ROLLUP_DOC}.`,
  );
}

main().catch((error) => {

  if (isFirestoreQuotaExceeded(error)) {
    console.warn(
      'usage-cron: Firestore quota exhausted; skipping this run. ' +
        'Nothing to do until the quota resets.',
    );
    return;
  }
  console.error(error);
  process.exitCode = 1;
});
