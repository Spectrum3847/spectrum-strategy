import { getAccessToken } from './google_auth.mjs';
import { parseServiceAccount } from './service_account.mjs';
import { listCollection } from './firestore.mjs';

const SLACK_TIMEOUT_MS = 5_000;

function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

async function postSlackDmSafe(fetchImpl, botToken, slackId, text, noteFailure) {
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
      noteFailure('slack DM', data.error || res.status);
      return false;
    }
    return true;
  } catch (err) {
    noteFailure('slack DM', err);
    return false;
  } finally {
    clearTimeout(timer);
  }
}

function createContext(env) {

  const fetchImpl = env.fetchImpl ?? fetch.bind(globalThis);

  const failures = [];
  function noteFailure(what, err) {
    const detail = err && err.message ? err.message : String(err);
    failures.push(`${what}: ${detail}`);
    console.error(`${what} failed:`, detail);
  }
  const nowMs = env.nowMs ?? Date.now();
  const dryRun = env.DRY_RUN === '1' || env.DRY_RUN === 'true';

  const optsBySecret = new Map();
  function optsFor(secretName, project) {
    if (!optsBySecret.has(secretName)) {
      const raw = env[secretName];
      if (!raw) throw new Error(`${secretName} is not set`);
      optsBySecret.set(
        secretName,
        (async () => ({
          token: await getAccessToken(parseServiceAccount(raw), { fetchImpl }),
          fetchImpl,
          project,
        }))(),
      );
    }
    return optsBySecret.get(secretName);
  }

  let dmSenderPromise;

  async function buildDmSender() {
    if (!env.SLACK_BOT_TOKEN) {
      console.log('Slack DM disabled: no SLACK_BOT_TOKEN.');
      return null;
    }
    let emailToSlackId;
    let uidToEmail;
    try {
      const platformOpts = await optsFor(
        'SPECTRUM_PLATFORM_SERVICE_ACCOUNT',
        env.PLATFORM_PROJECT,
      );
      const users = await listCollection(env.PLATFORM_PROJECT, 'users', platformOpts);
      emailToSlackId = new Map();
      for (const { data } of users) {
        const email = normalizeEmail(data.email);
        const slackId = typeof data.slackId === 'string' ? data.slackId.trim() : '';
        if (email && slackId) emailToSlackId.set(email, slackId);
      }

      const profiles = await listCollection(env.FIREBASE_PROJECT, 'userProfiles', await ourOpts());
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
    return async function dm(uid, text) {
      const email = uidToEmail.get(uid);
      const slackId = email ? emailToSlackId.get(email) : null;
      if (!slackId) return false;
      return postSlackDmSafe(fetchImpl, env.SLACK_BOT_TOKEN, slackId, text, noteFailure);
    };
  }

  const ourOpts = () => optsFor('FIREBASE_SERVICE_ACCOUNT', env.FIREBASE_PROJECT);

  return {
    env,
    fetchImpl,
    nowMs,
    dryRun,
    nowIso: () => new Date(nowMs).toISOString(),
    project: env.FIREBASE_PROJECT,
    pitProject: env.PIT_PROJECT,
    platformProject: env.PLATFORM_PROJECT,
    opts: ourOpts,
    pitOpts: () => optsFor('PIT_FIREBASE_SERVICE_ACCOUNT', env.PIT_PROJECT),

    dmSender: () => (dmSenderPromise ??= buildDmSender()),

    noteFailure,

    failures: () => [...failures],
  };
}

export { createContext, normalizeEmail, postSlackDmSafe };
