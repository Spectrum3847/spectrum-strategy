import { decodeFields } from './firestore.mjs';
import { bearerToken, claimedUid } from './id_token.mjs';

const READ_TIMEOUT_MS = 5_000;

const LEAD_ROLES = ['strategy', 'admin', 'developer'];

async function readAs(token, path, ctx) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), READ_TIMEOUT_MS);
  try {
    const res = await ctx.fetchImpl(
      `https://firestore.googleapis.com/v1/projects/${ctx.project}/databases/(default)/documents/${path}`,
      { headers: { Authorization: `Bearer ${token}` }, signal: ctl.signal },
    );
    if (!res.ok) return null;
    const doc = await res.json();
    return decodeFields(doc.fields);
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function hasLeadRole(profile) {
  const roles = Array.isArray(profile.roles) ? profile.roles : [];
  return (
    roles.some((role) => LEAD_ROLES.includes(role)) ||
    (typeof profile.role === 'string' && LEAD_ROLES.includes(profile.role))
  );
}

async function authorizeLead(request, ctx) {
  const token = bearerToken(request.headers.get('Authorization'));
  const uid = token ? claimedUid(token) : null;
  if (!uid) return null;
  const profile = await readAs(token, `userProfiles/${encodeURIComponent(uid)}`, ctx);
  return profile && hasLeadRole(profile) ? uid : null;
}

async function authorizeRelay(token, ctx) {
  const uid = token ? claimedUid(token) : null;
  if (!uid) return null;
  const config = await readAs(token, 'appConfig/relay', ctx);
  return config && Array.isArray(config.uids) && config.uids.includes(uid) ? uid : null;
}

export { authorizeLead, authorizeRelay, hasLeadRole };
