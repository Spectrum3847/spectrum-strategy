import { test } from 'node:test';
import assert from 'node:assert/strict';

import { authorizeLead, authorizeRelay, hasLeadRole } from '../src/chat_auth.mjs';
import { createContext } from '../src/context.mjs';
import { buildChatEnv, idToken } from './support/chat_env.mjs';

const leadRequest = (token) =>
  new Request('https://worker.test/chat/relays', {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });

test('strategy, admin and developer roles are leads, in the list or the legacy string', () => {
  for (const role of ['strategy', 'admin', 'developer']) {
    assert.equal(hasLeadRole({ roles: ['scouter', role] }), true, role);
    assert.equal(hasLeadRole({ role }), true, `legacy ${role}`);
  }
  assert.equal(hasLeadRole({ roles: ['scouter'] }), false);
  assert.equal(hasLeadRole({ role: 'scouter' }), false);
  assert.equal(hasLeadRole({ roles: 'strategy' }), false);
  assert.equal(hasLeadRole({}), false);
});

test('a lead is the signed-in uid, proven by reading their own profile with their token', async () => {
  const { env, calls } = buildChatEnv({ users: { lead1: { roles: ['strategy'] } } });
  const token = idToken('lead1');
  assert.equal(await authorizeLead(leadRequest(token), createContext(env)), 'lead1');
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /\/documents\/userProfiles\/lead1$/);
  assert.equal(calls[0].init.headers.Authorization, `Bearer ${token}`);
});

test('a member without a lead role, a revoked token and a missing profile are refused', async () => {
  const { env, revoked } = buildChatEnv({
    users: { scout1: { roles: ['scouter'] }, lead1: { roles: ['admin'] }, nobody: null },
  });
  const ctx = createContext(env);
  assert.equal(await authorizeLead(leadRequest(idToken('scout1')), ctx), null);
  assert.equal(await authorizeLead(leadRequest(idToken('nobody')), ctx), null);
  assert.equal(await authorizeLead(leadRequest(idToken('stranger')), ctx), null);
  revoked.add(idToken('lead1'));
  assert.equal(await authorizeLead(leadRequest(idToken('lead1')), ctx), null);
});

test('no header or a malformed token is refused without asking Firestore', async () => {
  const { env, calls } = buildChatEnv({ users: { lead1: { roles: ['admin'] } } });
  const ctx = createContext(env);
  assert.equal(await authorizeLead(leadRequest(null), ctx), null);
  assert.equal(await authorizeLead(leadRequest('not-a-token'), ctx), null);
  const basic = new Request('https://worker.test/chat/relays', {
    headers: { Authorization: 'Basic abc' },
  });
  assert.equal(await authorizeLead(basic, ctx), null);
  assert.equal(calls.length, 0);
});

test('a Firestore failure refuses the lead', async () => {
  const { env } = buildChatEnv({ users: { lead1: { roles: ['admin'] } } });
  env.fetchImpl = async () => {
    throw new Error('network down');
  };
  assert.equal(await authorizeLead(leadRequest(idToken('lead1')), createContext(env)), null);
});

test('a relay is an account listed in appConfig/relay.uids', async () => {
  const { env, calls } = buildChatEnv({
    users: { relay1: { roles: ['scouter'] }, other: { roles: ['scouter'] } },
    relayUids: ['relay1'],
  });
  const ctx = createContext(env);
  assert.equal(await authorizeRelay(idToken('relay1'), ctx), 'relay1');
  assert.match(calls[0].url, /\/documents\/appConfig\/relay$/);
  assert.equal(await authorizeRelay(idToken('other'), ctx), null);
  assert.equal(await authorizeRelay(idToken('stranger'), ctx), null);
  assert.equal(await authorizeRelay(null, ctx), null);
  assert.equal(await authorizeRelay('junk', ctx), null);
});
