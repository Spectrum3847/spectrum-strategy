import { createContext } from './context.mjs';
import { corsHeaders, reply } from './cors.mjs';
import { bearerToken, claimedUid } from './id_token.mjs';
import { buildTestPushPayload } from './messages.mjs';
import { createPusher } from './push.mjs';

const PROFILE_TIMEOUT_MS = 5_000;
const TEST_TTL_SECONDS = 120;

async function signedInUid(request, ctx) {
  const token = bearerToken(request.headers.get('Authorization'));
  const uid = token ? claimedUid(token) : null;
  if (!uid) return null;

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), PROFILE_TIMEOUT_MS);
  try {
    const res = await ctx.fetchImpl(
      `https://firestore.googleapis.com/v1/projects/${ctx.project}` +
        `/databases/(default)/documents/userProfiles/${encodeURIComponent(uid)}`,
      { headers: { Authorization: `Bearer ${token}` }, signal: ctl.signal },
    );
    return res.ok ? uid : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function handlePushTest(request, env) {
  const cors = corsHeaders(request, env);
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') return reply({ ok: false, error: 'method-not-allowed' }, 405, cors);

  if (!env.FIREBASE_SERVICE_ACCOUNT) return reply({ ok: false, error: 'not-configured' }, 503, cors);
  const ctx = createContext(env);
  const pusher = createPusher(ctx);
  if (!pusher) return reply({ ok: false, error: 'not-configured' }, 503, cors);

  const uid = await signedInUid(request, ctx);
  if (!uid) return reply({ ok: false, error: 'unauthorized' }, 401, cors);

  try {
    const subscriptions = await pusher.subscriptionsFor(uid);
    if (subscriptions.length === 0) {
      return reply({ ok: false, error: 'no-subscription' }, 404, cors);
    }
    const result = await pusher.sendToSubscriptions(subscriptions, buildTestPushPayload(ctx.nowMs), {
      ttl: TEST_TTL_SECONDS,
    });
    return reply(
      {
        ok: result.sent > 0,
        sent: result.sent,
        gone: result.gone,
        failed: result.retry + result.rejected,
      },
      200,
      cors,
    );
  } catch (err) {
    console.error('push test failed:', err && err.message ? err.message : err);
    return reply({ ok: false, error: 'failed' }, 502, cors);
  }
}

export { handlePushTest };
