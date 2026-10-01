import { test } from 'node:test';
import assert from 'node:assert/strict';

import worker, {
  decodeUnverifiedUid,
  hasElevatedRole,
  hasMemberRole,
  resolveMember,
  resolveMemberProfile,
} from './src/index.mjs';

const FIREBASE_PROJECT = 'frcspectrumstrategy';
const ALLOWED_ORIGIN = 'https://frcspectrumstrategy.web.app';
const ENV_BASE = { FIREBASE_PROJECT, ALLOWED_ORIGINS: ALLOWED_ORIGIN };

function tokenFor(sub) {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ sub })).toString('base64url');
  return `${header}.${payload}.signature`;
}

function memberRequest(token) {
  return {
    headers: { get: (name) => (name === 'Authorization' ? `Bearer ${token}` : null) },
  };
}

function profileWithRoles(roles) {
  return {
    fields: {
      roles: { arrayValue: { values: roles.map((role) => ({ stringValue: role })) } },
    },
  };
}

function fakeFirestore(token, roles, { status = 200 } = {}) {
  return async (url, options) => {
    const ok = status === 200 && options.headers.Authorization === `Bearer ${token}`;
    return { ok, status: ok ? 200 : 401, json: async () => profileWithRoles(roles) };
  };
}

function fakeBucket() {
  const objects = new Map();
  return {
    objects,
    async put(key, body, opts) {
      objects.set(key, {
        body,
        size: body.byteLength,
        httpMetadata: opts?.httpMetadata,
        customMetadata: opts?.customMetadata,
      });
    },
    async get(key) {
      const found = objects.get(key);
      return found ? { ...found, body: found.body } : null;
    },
    async head(key) {
      const found = objects.get(key);
      if (!found) return null;
      const { body: _body, ...metadata } = found;
      return metadata;
    },
    async delete(key) {
      objects.delete(key);
    },
  };
}

function request(method, path, { token, type, body, origin, declaredLength } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (type) headers['Content-Type'] = type;
  if (origin) headers.Origin = origin;
  if (declaredLength !== undefined) headers['Content-Length'] = declaredLength;
  return new Request(`https://photos.example${path}`, { method, headers, body });
}

async function withFirestore(token, roles, body) {
  const original = globalThis.fetch;
  globalThis.fetch = fakeFirestore(token, roles);
  try {
    return await body();
  } finally {
    globalThis.fetch = original;
  }
}

test('decodeUnverifiedUid extracts a valid alphanumeric sub', () => {
  assert.equal(decodeUnverifiedUid(tokenFor('AbC123xyZ')), 'AbC123xyZ');
});

test('decodeUnverifiedUid returns null for malformed tokens', () => {
  assert.equal(decodeUnverifiedUid(''), null);
  assert.equal(decodeUnverifiedUid('no-dots'), null);
  assert.equal(decodeUnverifiedUid('a.eyJub3Rqc29uIn0.c'), null);
  assert.equal(decodeUnverifiedUid('a.%%%not-base64.c'), null);
});

test('decodeUnverifiedUid refuses subs that are not alphanumeric', () => {
  assert.equal(decodeUnverifiedUid(tokenFor('has/slash')), null);
  assert.equal(decodeUnverifiedUid(tokenFor('has.dot')), null);
  assert.equal(decodeUnverifiedUid(tokenFor('')), null);
  assert.equal(decodeUnverifiedUid(tokenFor('a'.repeat(129))), null);
});

test('hasMemberRole accepts any member role from the roles array', () => {
  for (const role of ['scouter', 'strategy', 'admin', 'developer']) {
    assert.equal(hasMemberRole(profileWithRoles([role])), true);
  }
});

test('hasMemberRole accepts the legacy singular role string', () => {
  for (const role of ['scouter', 'strategy', 'admin', 'developer']) {
    assert.equal(hasMemberRole({ fields: { role: { stringValue: role } } }), true);
  }
});

test('hasMemberRole refuses viewer and empty profiles', () => {
  assert.equal(hasMemberRole(profileWithRoles(['viewer'])), false);
  assert.equal(hasMemberRole(profileWithRoles([])), false);
  assert.equal(hasMemberRole({ fields: { role: { stringValue: 'viewer' } } }), false);
  assert.equal(hasMemberRole({}), false);
  assert.equal(hasMemberRole(null), false);
});

test('hasElevatedRole accepts strategy, admin, and developer only', () => {
  for (const role of ['strategy', 'admin', 'developer']) {
    assert.equal(hasElevatedRole(profileWithRoles([role])), true, role);
  }
  assert.equal(hasElevatedRole(profileWithRoles(['scouter'])), false);
  assert.equal(hasElevatedRole(profileWithRoles(['viewer'])), false);
});

test('resolveMemberProfile reports elevated for an elevated role and not for scouter', async () => {
  const env = { FIREBASE_PROJECT };
  const scouterToken = tokenFor('scouterUid');
  assert.deepEqual(
    await resolveMemberProfile(
      memberRequest(scouterToken),
      env,
      fakeFirestore(scouterToken, ['scouter']),
    ),
    { uid: 'scouterUid', elevated: false },
  );

  const adminToken = tokenFor('adminUid');
  assert.deepEqual(
    await resolveMemberProfile(memberRequest(adminToken), env, fakeFirestore(adminToken, ['admin'])),
    { uid: 'adminUid', elevated: true },
  );
});

test('resolveMember returns the uid for a member profile', async () => {
  const token = tokenFor('memberUid123');
  const fetchImpl = async (url, options) => {
    assert.equal(
      url,
      `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT}` +
        '/databases/(default)/documents/userProfiles/memberUid123',
    );
    assert.equal(options.headers.Authorization, `Bearer ${token}`);
    return { ok: true, json: async () => profileWithRoles(['scouter']) };
  };
  const env = { FIREBASE_PROJECT };
  assert.equal(await resolveMember(memberRequest(token), env, fetchImpl), 'memberUid123');
});

test('resolveMember returns null when no Bearer token is present', async () => {
  const env = { FIREBASE_PROJECT };
  const noFetch = () => {
    throw new Error('fetch must not be called');
  };
  assert.equal(await resolveMember({ headers: { get: () => null } }, env, noFetch), null);
  assert.equal(await resolveMember({ headers: { get: () => 'Basic abc' } }, env, noFetch), null);
});

test('resolveMember returns null when the token decodes to a non-uid', async () => {
  const env = { FIREBASE_PROJECT };
  const noFetch = () => {
    throw new Error('fetch must not be called');
  };
  assert.equal(await resolveMember(memberRequest(tokenFor('not/a/uid')), env, noFetch), null);
});

test('resolveMember returns null when Firestore rejects the token', async () => {
  const token = tokenFor('memberUid123');
  const fetchImpl = async () => ({ ok: false, status: 401 });
  const env = { FIREBASE_PROJECT };
  assert.equal(await resolveMember(memberRequest(token), env, fetchImpl), null);
});

test('resolveMember returns null for a viewer profile', async () => {
  const token = tokenFor('viewerUid');
  const fetchImpl = async () => ({ ok: true, json: async () => profileWithRoles(['viewer']) });
  const env = { FIREBASE_PROJECT };
  assert.equal(await resolveMember(memberRequest(token), env, fetchImpl), null);
});

test('upload stores the image and returns a key the download route accepts', async () => {
  const token = tokenFor('uid1');
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['scouter'], async () => {
    const res = await worker.fetch(
      request('POST', '/photos', { token, type: 'image/jpeg', body: new Uint8Array([1, 2, 3]) }),
      env,
    );
    assert.equal(res.status, 201);
    const { key } = await res.json();
    assert.match(key, /\.jpg$/);
    assert.equal(env.PHOTOS.objects.get(key).httpMetadata.contentType, 'image/jpeg');

    const got = await worker.fetch(request('GET', `/photos/${key}`, { token }), env);
    assert.equal(got.status, 200);
    assert.equal(got.headers.get('Content-Type'), 'image/jpeg');
    assert.equal(got.headers.get('Cache-Control'), 'no-store');
  });
});

test('upload stores a pdf and serves it back with its own content type', async () => {

  const token = tokenFor('uid1');
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['scouter'], async () => {
    const res = await worker.fetch(
      request('POST', '/photos', {
        token,
        type: 'application/pdf',
        body: new Uint8Array([1, 2, 3]),
      }),
      env,
    );
    assert.equal(res.status, 201);
    const { key } = await res.json();
    assert.match(key, /\.pdf$/);

    const got = await worker.fetch(request('GET', `/photos/${key}`, { token }), env);
    assert.equal(got.status, 200);
    assert.equal(got.headers.get('Content-Type'), 'application/pdf');
  });
});

test('upload refuses a non-image, non-pdf content type', async () => {
  const token = tokenFor('uid1');
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['scouter'], async () => {
    for (const type of ['text/html', 'application/zip']) {
      const res = await worker.fetch(
        request('POST', '/photos', { token, type, body: '<script>' }),
        env,
      );
      assert.equal(res.status, 415);
    }
    assert.equal(env.PHOTOS.objects.size, 0);
  });
});

test('upload refuses a streamed body over the cap with no declared Content-Length', async () => {

  const token = tokenFor('uid1');
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['scouter'], async () => {
    const chunkSize = 64 * 1024;
    const chunks = Math.ceil((2 * 1024 * 1024 + 1) / chunkSize);
    const body = new ReadableStream({
      start(controller) {
        for (let i = 0; i < chunks; i++) controller.enqueue(new Uint8Array(chunkSize));
        controller.close();
      },
    });
    const req = new Request('https://photos.example/photos', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'image/png' },
      body,
      duplex: 'half',
    });
    assert.equal(req.headers.get('Content-Length'), null);
    const res = await worker.fetch(req, env);
    assert.equal(res.status, 413);
    assert.equal(env.PHOTOS.objects.size, 0);
  });
});

test('upload refuses a body over the cap even when Content-Length lies low', async () => {
  const token = tokenFor('uid1');
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['scouter'], async () => {

    const res = await worker.fetch(
      request('POST', '/photos', {
        token,
        type: 'image/png',
        body: new Uint8Array(2 * 1024 * 1024 + 1),
        declaredLength: '10',
      }),
      env,
    );
    assert.equal(res.status, 413);
    assert.equal(env.PHOTOS.objects.size, 0);
  });
});

test('upload refuses a declared oversize before reading the body', async () => {
  const token = tokenFor('uid1');
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['scouter'], async () => {

    const res = await worker.fetch(
      request('POST', '/photos', {
        token,
        type: 'image/png',
        body: new Uint8Array(8),
        declaredLength: String(2 * 1024 * 1024 + 1),
      }),
      env,
    );
    assert.equal(res.status, 413);
    assert.equal(env.PHOTOS.objects.size, 0);
  });
});

test('upload refuses an empty body', async () => {
  const token = tokenFor('uid1');
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['scouter'], async () => {
    const res = await worker.fetch(
      request('POST', '/photos', { token, type: 'image/jpeg', body: new Uint8Array(0) }),
      env,
    );
    assert.equal(res.status, 400);
  });
});

test('every route refuses a viewer', async () => {
  const token = tokenFor('uid1');
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  env.PHOTOS.objects.set('11111111-2222-3333-4444-555555555555.jpg', {
    body: new Uint8Array([1]),
    size: 1,
  });
  await withFirestore(token, ['viewer'], async () => {
    for (const req of [
      request('POST', '/photos', { token, type: 'image/jpeg', body: new Uint8Array([1]) }),
      request('GET', '/photos/11111111-2222-3333-4444-555555555555.jpg', { token }),
      request('DELETE', '/photos/11111111-2222-3333-4444-555555555555.jpg', { token }),
    ]) {
      assert.equal((await worker.fetch(req, env)).status, 403);
    }
    assert.equal(env.PHOTOS.objects.size, 1, 'viewer must not have deleted anything');
  });
});

test('a key the Worker did not mint is refused before touching the bucket', async () => {
  const token = tokenFor('uid1');
  const bucket = fakeBucket();
  bucket.get = async () => assert.fail('should not have read the bucket');
  await withFirestore(token, ['admin'], async () => {
    for (const key of ['../appConfig', 'secret.txt', 'not-a-uuid.jpg']) {
      const res = await worker.fetch(request('GET', `/photos/${key}`, { token }), {
        ...ENV_BASE,
        PHOTOS: bucket,
      });
      assert.equal(res.status, 404, key);
    }
  });
});

test('download 404s for a well-formed key that is not there', async () => {
  const token = tokenFor('uid1');
  await withFirestore(token, ['admin'], async () => {
    const res = await worker.fetch(
      request('GET', '/photos/11111111-2222-3333-4444-555555555555.jpg', { token }),
      { ...ENV_BASE, PHOTOS: fakeBucket() },
    );
    assert.equal(res.status, 404);
  });
});

test('delete removes the object', async () => {
  const token = tokenFor('uid1');
  const key = '11111111-2222-3333-4444-555555555555.jpg';
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };

  env.PHOTOS.objects.set(key, { body: new Uint8Array([1]), size: 1 });
  await withFirestore(token, ['admin'], async () => {
    const res = await worker.fetch(request('DELETE', `/photos/${key}`, { token }), env);
    assert.equal(res.status, 204);
    assert.equal(env.PHOTOS.objects.size, 0);
  });
});

test('upload stamps the caller as uploaderUid', async () => {
  const token = tokenFor('uid1');
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['scouter'], async () => {
    const res = await worker.fetch(
      request('POST', '/photos', { token, type: 'image/jpeg', body: new Uint8Array([1, 2, 3]) }),
      env,
    );
    const { key } = await res.json();
    assert.equal(env.PHOTOS.objects.get(key).customMetadata.uploaderUid, 'uid1');
  });
});

test('the uploader can delete their own photo', async () => {
  const token = tokenFor('uid1');
  const key = '11111111-2222-3333-4444-555555555555.jpg';
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  env.PHOTOS.objects.set(key, {
    body: new Uint8Array([1]),
    size: 1,
    customMetadata: { uploaderUid: 'uid1' },
  });
  await withFirestore(token, ['scouter'], async () => {
    const res = await worker.fetch(request('DELETE', `/photos/${key}`, { token }), env);
    assert.equal(res.status, 204);
    assert.equal(env.PHOTOS.objects.size, 0);
  });
});

test('a different plain member cannot delete someone else\'s photo', async () => {
  const token = tokenFor('uid2');
  const key = '11111111-2222-3333-4444-555555555555.jpg';
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  env.PHOTOS.objects.set(key, {
    body: new Uint8Array([1]),
    size: 1,
    customMetadata: { uploaderUid: 'uid1' },
  });
  await withFirestore(token, ['scouter'], async () => {
    const res = await worker.fetch(request('DELETE', `/photos/${key}`, { token }), env);
    assert.equal(res.status, 403);
    assert.equal(env.PHOTOS.objects.size, 1, 'a non-owner, non-elevated delete must not land');
  });
});

test('an elevated role can delete a photo it did not upload', async () => {
  for (const role of ['strategy', 'admin', 'developer']) {
    const token = tokenFor('uidElevated');
    const key = '11111111-2222-3333-4444-555555555555.jpg';
    const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
    env.PHOTOS.objects.set(key, {
      body: new Uint8Array([1]),
      size: 1,
      customMetadata: { uploaderUid: 'someoneElse' },
    });
    await withFirestore(token, [role], async () => {
      const res = await worker.fetch(request('DELETE', `/photos/${key}`, { token }), env);
      assert.equal(res.status, 204, role);
      assert.equal(env.PHOTOS.objects.size, 0, role);
    });
  }
});

test('a plain member cannot delete a pre-existing object with no recorded uploader', async () => {
  const token = tokenFor('uid1');
  const key = '11111111-2222-3333-4444-555555555555.jpg';
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };

  env.PHOTOS.objects.set(key, { body: new Uint8Array([1]), size: 1 });
  await withFirestore(token, ['scouter'], async () => {
    const res = await worker.fetch(request('DELETE', `/photos/${key}`, { token }), env);
    assert.equal(res.status, 403);
    assert.equal(env.PHOTOS.objects.size, 1);
  });
});

test('deleting a key that is not in the bucket still returns 204', async () => {
  const token = tokenFor('uid1');
  const key = '11111111-2222-3333-4444-555555555555.jpg';
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['scouter'], async () => {
    const res = await worker.fetch(request('DELETE', `/photos/${key}`, { token }), env);
    assert.equal(res.status, 204);
  });
});

test('paths outside /photos are refused without a Firestore call', async () => {
  const never = async () => assert.fail('should not have reached Firestore');
  const original = globalThis.fetch;
  globalThis.fetch = never;
  try {
    const res = await worker.fetch(request('GET', '/'), { ...ENV_BASE, PHOTOS: fakeBucket() });
    assert.equal(res.status, 404);
  } finally {
    globalThis.fetch = original;
  }
});

test('CORS is echoed only for an allowed origin', async () => {
  const allowed = await worker.fetch(request('OPTIONS', '/photos', { origin: ALLOWED_ORIGIN }), ENV_BASE);
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), ALLOWED_ORIGIN);

  const denied = await worker.fetch(
    request('OPTIONS', '/photos', { origin: 'https://evil.example' }),
    ENV_BASE,
  );
  assert.equal(denied.headers.get('Access-Control-Allow-Origin'), null);
});
