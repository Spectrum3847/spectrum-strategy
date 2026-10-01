import {
  getDocument,
  setDocument as adminSetDocument,
  deleteDocument as adminDeleteDocument,
  documentName,
  encodeFields,
} from '../firestore.mjs';
import { parseServiceAccount } from '../service_account.mjs';
import { mintCustomToken } from '../google_auth.mjs';
import { signInWithCustomToken } from '../identity_toolkit.mjs';
import { postSlackDmSafe } from '../context.mjs';

const CANARY_WEB_API_KEY = 'AIzaSyCgatjO0H0C7pl3Lh0_tfcbFbDV-Xru7yg';

const CANARY_UID = 'spectrumstrategy-canary';
const CANARY_DISPLAY_NAME = 'Scouting canary';

const CANARY_ENTRY_ID = 'canary-probe';
const CANARY_ENTRY_PATH = `scoutEntries/${CANARY_ENTRY_ID}`;

const CANARY_TIMESTAMP_ISO = '2020-01-02T00:00:00.000Z';

const FIRESTORE_BASE = 'https://firestore.googleapis.com/v1';
const REQUEST_TIMEOUT_MS = 10_000;

function commitUrl(project) {
  return `${FIRESTORE_BASE}/projects/${project}/databases/(default)/documents:commit`;
}

function docUrl(project, path) {
  return `${FIRESTORE_BASE}/projects/${project}/databases/(default)/documents/${path}`;
}

async function requestAsUser(fetchImpl, idToken, url, { method = 'GET', body } = {}) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), REQUEST_TIMEOUT_MS);
  try {
    const res = await fetchImpl(url, {
      method,
      headers: {
        Authorization: `Bearer ${idToken}`,
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: ctl.signal,
    });
    const data = await res.json().catch(() => ({}));
    return { status: res.status, ok: res.ok, data };
  } catch (err) {

    return { status: 0, ok: false, data: { error: { message: err.message } } };
  } finally {
    clearTimeout(timer);
  }
}

async function writeAsUser(fetchImpl, idToken, project, path, fields) {
  return requestAsUser(fetchImpl, idToken, commitUrl(project), {
    method: 'POST',
    body: {
      writes: [
        {
          update: { name: documentName(project, path), fields: encodeFields(fields) },

          currentDocument: { exists: false },
        },
      ],
    },
  });
}

async function deleteAsUser(fetchImpl, idToken, project, path) {
  return requestAsUser(fetchImpl, idToken, docUrl(project, path), { method: 'DELETE' });
}

function classify(status, data) {
  const code = data?.error?.status;
  if (status === 403 || code === 'PERMISSION_DENIED') return 'refused';
  if (status === 0 || status === 429 || status >= 500) return 'transient';
  return 'broken';
}

function buildCanaryEntry() {
  const canaryPhase = { score: 0, penalties: 0, notes: 'canary', counters: { canary: 1 } };
  return {
    id: CANARY_ENTRY_ID,
    matchId: 'canary-probe',
    teamNumber: 99999,
    alliance: 'Red',
    notes:
      'Automated canary write. Proves scout entries still reach the database; ' +
      'deleted immediately after this check.',
    authorUid: CANARY_UID,
    authorDisplayName: CANARY_DISPLAY_NAME,
    updatedAt: CANARY_TIMESTAMP_ISO,
    createdAt: CANARY_TIMESTAMP_ISO,
    updatedAtTs: new Date(CANARY_TIMESTAMP_ISO),
    byPhase: { auton: canaryPhase, teleop: canaryPhase, endgame: canaryPhase },
    fieldValues: { canaryField: 'canary' },
    tbaMatchKey: 'canary_probe',
    strokesByPhase: { auton: [] },
    addedManually: true,
  };
}

async function ensureCanaryProfile(ctx, project, opts) {
  const existing = await getDocument(project, `userProfiles/${CANARY_UID}`, opts);
  if (!existing) {
    await adminSetDocument(
      project,
      `userProfiles/${CANARY_UID}`,
      {
        uid: CANARY_UID,
        displayName: CANARY_DISPLAY_NAME,
        roles: ['scouter'],
        createdAt: ctx.nowIso(),
      },
      opts,
    );
    return 'created';
  }
  const roles = Array.isArray(existing.roles) ? existing.roles : [];
  if (!roles.includes('scouter')) {
    await adminSetDocument(
      project,
      `userProfiles/${CANARY_UID}`,
      { ...existing, roles: [...roles, 'scouter'] },
      opts,
    );
    return 'repaired';
  }
  return null;
}

async function alertRefusal(ctx, detail) {
  ctx.noteFailure('canary write', new Error(detail));
  const token = ctx.env.SLACK_BOT_TOKEN;
  const channel = ctx.env.SLACK_STRATEGY_CHANNEL_ID;
  if (!token || !channel) {
    console.log(
      'Canary refusal Slack alert skipped: SLACK_BOT_TOKEN or SLACK_STRATEGY_CHANNEL_ID not set.',
    );
    return;
  }
  const text =
    'Scout entry writes are being refused by Firestore rules ' +
    `(the canary write failed: ${detail}). Check firestore.rules against what ` +
    'the app actually writes before assuming this is only bad wifi.';
  await postSlackDmSafe(ctx.fetchImpl, token, channel, text, ctx.noteFailure);
}

async function alertBroken(ctx, stage, detail) {
  ctx.noteFailure(`canary ${stage}`, new Error(detail));
  const token = ctx.env.SLACK_BOT_TOKEN;
  const channel = ctx.env.SLACK_STRATEGY_CHANNEL_ID;
  if (!token || !channel) {
    console.log(
      `Canary ${stage} Slack alert skipped: SLACK_BOT_TOKEN or SLACK_STRATEGY_CHANNEL_ID not set.`,
    );
    return;
  }
  const text =
    `The scout entry canary is broken at ${stage} (${detail}) and is not ` +
    'currently proving anything about scout entry writes. This is not a ' +
    "rules refusal -- fix the canary's own setup before trusting its silence.";
  await postSlackDmSafe(ctx.fetchImpl, token, channel, text, ctx.noteFailure);
}

function decodeJwtPayload(token) {
  const segment = String(token).split('.')[1];
  if (!segment) return null;
  const padded = segment.replace(/-/g, '+').replace(/_/g, '/');
  const withPadding = padded + '='.repeat((4 - (padded.length % 4)) % 4);
  try {
    return JSON.parse(atob(withPadding));
  } catch {
    return null;
  }
}

async function runCanary(ctx) {
  const { project, fetchImpl, dryRun } = ctx;
  const opts = await ctx.opts();

  const profileAction = await ensureCanaryProfile(ctx, project, opts);
  if (profileAction === 'created') {
    console.log(`Bootstrapped userProfiles/${CANARY_UID} with the scouter role.`);
  } else if (profileAction === 'repaired') {
    console.log(`Repaired userProfiles/${CANARY_UID}: the scouter role had been removed.`);
  }

  const serviceAccount = parseServiceAccount(ctx.env.FIREBASE_SERVICE_ACCOUNT);
  const customToken = await mintCustomToken(serviceAccount, CANARY_UID, {
    nowSeconds: Math.floor(ctx.nowMs / 1000),
  });

  let idToken;
  try {
    ({ idToken } = await signInWithCustomToken(fetchImpl, CANARY_WEB_API_KEY, customToken));
  } catch (err) {

    if (typeof err.status === 'number' && err.status >= 400 && err.status < 500) {
      await alertBroken(ctx, 'token-exchange', err.message);
      return { broken: true, stage: 'token-exchange' };
    }
    console.log(`Canary token exchange failed transiently: ${err.message}`);
    return { skipped: 'transient', stage: 'token-exchange' };
  }
  if (!idToken) {
    await alertBroken(ctx, 'token-exchange', 'token exchange succeeded but returned no idToken');
    return { broken: true, stage: 'token-exchange' };
  }

  const tokenPayload = decodeJwtPayload(idToken);
  if (!tokenPayload || tokenPayload.aud !== project) {
    await alertBroken(
      ctx,
      'token-exchange',
      `ID token audience "${tokenPayload?.aud ?? 'unknown'}" does not match ` +
        `FIREBASE_PROJECT "${project}"`,
    );
    return { broken: true, stage: 'token-exchange' };
  }

  if (dryRun) {
    console.log(`[dry run] would write and delete ${CANARY_ENTRY_PATH} as ${CANARY_UID}.`);
    return { dryRun: true };
  }

  await adminDeleteDocument(project, CANARY_ENTRY_PATH, opts);

  const entry = buildCanaryEntry();
  const writeResult = await writeAsUser(fetchImpl, idToken, project, CANARY_ENTRY_PATH, entry);
  if (!writeResult.ok) {
    const detail = `HTTP ${writeResult.status} ${JSON.stringify(writeResult.data)}`;
    const kind = classify(writeResult.status, writeResult.data);
    if (kind === 'refused') {
      await alertRefusal(ctx, detail);
      return { refused: true, detail };
    }
    if (kind === 'broken') {
      await alertBroken(ctx, 'write', detail);
      return { broken: true, stage: 'write', detail };
    }
    console.log(`Canary write failed transiently: ${detail}`);
    return { skipped: 'transient', stage: 'write', detail };
  }

  const deleteResult = await deleteAsUser(fetchImpl, idToken, project, CANARY_ENTRY_PATH);
  if (!deleteResult.ok && deleteResult.status !== 404) {
    if (deleteResult.status === 0 || deleteResult.status >= 500) {

      console.log(
        `Canary cleanup failed transiently: HTTP ${deleteResult.status} ` +
          `${JSON.stringify(deleteResult.data)}`,
      );
    } else {

      ctx.noteFailure(
        'canary cleanup',
        new Error(`HTTP ${deleteResult.status} ${JSON.stringify(deleteResult.data)}`),
      );
    }
  }

  console.log('Canary write and delete both succeeded.');
  return { ok: true };
}

export {
  runCanary,
  buildCanaryEntry,
  ensureCanaryProfile,
  classify,
  CANARY_UID,
  CANARY_ENTRY_ID,
  CANARY_ENTRY_PATH,
};
