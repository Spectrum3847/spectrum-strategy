import { deleteDocument, listCollection, runQuery, whereQuery } from './firestore.mjs';
import { createVapid, sendWebPush } from './webpush.mjs';

const COLLECTION = 'pushSubscriptions';

const MAX_TEST_SUBSCRIPTIONS = 10;

function pushConfigured(env) {
  return Boolean(env.VAPID_PRIVATE_KEY && env.VAPID_PUBLIC_KEY && env.VAPID_SUBJECT);
}

function toSubscription({ id, data }) {
  return { id, uid: data.uid, endpoint: data.endpoint, p256dh: data.p256dh, auth: data.auth };
}

function createPusher(ctx) {
  const { env, fetchImpl, nowMs } = ctx;
  if (!pushConfigured(env)) return null;
  const vapid = createVapid({
    publicKey: env.VAPID_PUBLIC_KEY,
    privateKey: env.VAPID_PRIVATE_KEY,
    subject: env.VAPID_SUBJECT,
  });

  let byUid;
  async function subscriptionsByUid() {
    if (!byUid) {
      byUid = new Map();
      const docs = await listCollection(ctx.project, COLLECTION, await ctx.opts());
      for (const doc of docs) {
        const sub = toSubscription(doc);
        if (typeof sub.uid !== 'string') continue;
        byUid.set(sub.uid, [...(byUid.get(sub.uid) ?? []), sub]);
      }
    }
    return byUid;
  }

  async function subscriptionsFor(uid) {
    const rows = await runQuery(
      ctx.project,
      whereQuery(COLLECTION, [{ fieldPath: 'uid', op: 'EQUAL', value: uid }], {
        limit: MAX_TEST_SUBSCRIPTIONS,
      }),
      await ctx.opts(),
    );
    return rows.map(toSubscription);
  }

  async function sendTo(subscriptions, payload, { ttl } = {}) {
    const counts = { sent: 0, gone: 0, retry: 0, rejected: 0 };
    for (const subscription of subscriptions) {
      const { outcome, status } = await sendWebPush({
        fetchImpl,
        vapid,
        subscription,
        payload,
        nowMs,
        ttl,
      });
      counts[outcome]++;
      if (outcome === 'gone') {
        try {
          await deleteDocument(ctx.project, `${COLLECTION}/${subscription.id}`, await ctx.opts());
        } catch (err) {
          ctx.noteFailure('push subscription cleanup', err);
        }
      } else if (outcome !== 'sent') {
        ctx.noteFailure('web push', `${outcome} (HTTP ${status})`);
      }
    }
    return { ...counts, settled: counts.retry === 0 && counts.sent + counts.rejected > 0 };
  }

  return {
    sendToUid: async (uid, payload, options) => {
      const subscriptions = (await subscriptionsByUid()).get(uid) ?? [];
      return sendTo(subscriptions, payload, options);
    },
    sendToSubscriptions: sendTo,
    subscriptionsFor,
  };
}

export { createPusher, pushConfigured };
