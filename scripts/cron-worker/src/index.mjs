import { createContext } from './context.mjs';
import { FirestoreQuotaError } from './firestore.mjs';
import { runShift } from './crons/shift.mjs';
import { runAccuracy } from './crons/accuracy.mjs';
import { runReport } from './crons/report.mjs';
import { runScheduleMirror } from './crons/schedule_mirror.mjs';
import { runUsage } from './crons/usage.mjs';
import { runBackup } from './crons/backup.mjs';
import { runCanary } from './crons/canary.mjs';

const JOBS = {
  shift: {
    run: runShift,
    requires: ['FIREBASE_SERVICE_ACCOUNT', 'SPECTRUM_PLATFORM_SERVICE_ACCOUNT', 'SLACK_BOT_TOKEN'],
  },
  accuracy: { run: runAccuracy, requires: ['FIREBASE_SERVICE_ACCOUNT'] },
  report: { run: runReport, requires: ['FIREBASE_SERVICE_ACCOUNT', 'GH_TOKEN'] },
  scheduleMirror: {
    run: runScheduleMirror,
    requires: ['FIREBASE_SERVICE_ACCOUNT', 'PIT_FIREBASE_SERVICE_ACCOUNT'],
  },
  usage: { run: runUsage, requires: ['FIREBASE_SERVICE_ACCOUNT'] },
  backup: { run: runBackup, requires: ['FIREBASE_SERVICE_ACCOUNT'] },

  canary: { run: runCanary, requires: ['FIREBASE_SERVICE_ACCOUNT'], critical: true },
};

function missingSecrets(env, name) {
  return JOBS[name].requires.filter((secret) => !env[secret]);
}

async function runJob(env, name) {
  const job = JOBS[name];
  if (!job) throw new Error(`unknown job: ${name}`);
  const missing = missingSecrets(env, name);
  if (missing.length > 0) {
    console.log(`${name}: skipping, ${missing.join(', ')} not set.`);
    const result = { skipped: 'missing-secrets', missing };
    return job.critical
      ? { ...result, failed: 1, failures: [`${name}: missing secret(s): ${missing.join(', ')}`] }
      : result;
  }

  const ctx = createContext(env);
  try {
    const result = await job.run(ctx);
    const withF = withFailures(result, ctx);
    if (job.critical && !withF.failed && withF.ok !== true) {

      return {
        ...withF,
        failed: 1,
        failures: [
          ...(withF.failures || []),
          `${name}: run did not reach a verified success (${JSON.stringify(withF)})`,
        ],
      };
    }
    return withF;
  } catch (err) {
    if (err instanceof FirestoreQuotaError && !job.critical) {
      console.log(`${name}: Firestore quota exhausted; skipping and retrying next run.`);
      return withFailures({ skipped: 'quota' }, ctx);
    }
    throw err;
  }
}

function withFailures(result, ctx) {
  const failures = ctx.failures();
  if (failures.length === 0) return result;
  return { ...result, failed: failures.length, failures };
}

async function runAllJobs(env) {
  const results = {};
  for (const name of Object.keys(JOBS)) {
    try {
      results[name] = await runJob(env, name);
    } catch (err) {
      const message = String(err && err.message ? err.message : err);
      console.error(`${name} failed:`, message);
      results[name] = { error: message };
    }
  }
  return results;
}

async function scheduled(event, env, ctx) {
  await runAllJobs(env);
}

function constantTimeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function isAuthorized(raw, expected) {
  if (typeof raw !== 'string') return false;

  const exact = constantTimeEqual(raw, expected);
  const trimmed = constantTimeEqual(raw.trim(), expected);
  return exact || trimmed;
}

function unauthorizedBody(raw) {
  if (typeof raw !== 'string') {
    return {
      ok: false,
      error: 'Unauthorized: no X-Run-Token header was sent.',
      hint: 'Add a custom request header named X-Run-Token whose value is the RUN_TOKEN secret.',
    };
  }
  const trimmed = raw.trim();
  return {
    ok: false,
    error: 'Unauthorized: the X-Run-Token header did not match RUN_TOKEN.',
    sentCharacters: raw.length,
    sentCharactersTrimmed: trimmed.length,
    hint:
      raw.length === 0
        ? 'The header was sent but empty.'
        : 'Compare sentCharacters against the length of the token you set with `wrangler secret put RUN_TOKEN`. A mismatch means the value is truncated, padded, or a different token.',
  };
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function fetchHandler(request, env, ctx) {
  const url = new URL(request.url);
  if (url.pathname === '/') {
    return json({ ok: true, worker: 'spectrumstrategy-crons', jobs: Object.keys(JOBS) });
  }
  if (!url.pathname.startsWith('/run/')) {
    return new Response('Not found', { status: 404 });
  }
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const expected = env.RUN_TOKEN;
  const raw = request.headers.get('X-Run-Token');
  if (!expected) return new Response('RUN_TOKEN is not set', { status: 503 });
  if (!isAuthorized(raw, expected)) return json(unauthorizedBody(raw), 401);

  const name = url.pathname.slice('/run/'.length);
  if (!JOBS[name]) return json({ ok: false, error: `unknown job: ${name}` }, 404);
  try {
    const result = await runJob(env, name);

    const failed = (result && result.failed) || 0;
    return json({ ok: failed === 0, job: name, result }, failed === 0 ? 200 : 500);
  } catch (err) {
    const message = String(err && err.message ? err.message : err);
    console.error(`${name} failed:`, message);
    return json({ ok: false, job: name, error: message }, 500);
  }
}

export { runJob, runAllJobs, JOBS };
export default { scheduled, fetch: fetchHandler };
