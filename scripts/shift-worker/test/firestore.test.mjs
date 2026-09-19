import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  decodeFields,
  encodeFields,
  getDocument,
  listCollection,
  runQuery,
  whereEqualsQuery,
  patchDocument,
  FirestoreQuotaError,
} from '../src/firestore.mjs';

test('encodeFields/decodeFields round-trips plain values', () => {
  const original = {
    name: 'Alex',
    startMatch: 7,
    ratio: 1.5,
    active: true,
    missing: null,
    shifts: [
      { startMatch: 1, endMatch: 6 },
      { startMatch: 7, endMatch: 12 },
    ],
  };
  assert.deepEqual(decodeFields(encodeFields(original)), original);
});

test('encodeFields encodes integers as integerValue and floats as doubleValue', () => {
  const fields = encodeFields({ a: 3, b: 3.5 });
  assert.deepEqual(fields.a, { integerValue: '3' });
  assert.deepEqual(fields.b, { doubleValue: 3.5 });
});

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), { status });
}

test('getDocument returns null on 404 without throwing', async () => {
  const fetchImpl = async () => jsonResponse(404, { error: { message: 'not found' } });
  const result = await getDocument('proj', 'appConfig/activeEvent', { token: 't', fetchImpl });
  assert.equal(result, null);
});

test('getDocument decodes the fields map', async () => {
  const fetchImpl = async () => jsonResponse(200, { fields: encodeFields({ eventKey: '2026miket' }) });
  const result = await getDocument('proj', 'appConfig/activeEvent', { token: 't', fetchImpl });
  assert.deepEqual(result, { eventKey: '2026miket' });
});

test('getDocument throws FirestoreQuotaError on 429', async () => {
  const fetchImpl = async () => jsonResponse(429, { error: { status: 'RESOURCE_EXHAUSTED' } });
  await assert.rejects(
    () => getDocument('proj', 'appConfig/activeEvent', { token: 't', fetchImpl }),
    FirestoreQuotaError,
  );
});

test('listCollection pages through nextPageToken', async () => {
  const pages = [
    {
      documents: [
        {
          name: 'projects/p/databases/(default)/documents/users/u1',
          fields: encodeFields({ email: 'a@example.com' }),
        },
      ],
      nextPageToken: 'p2',
    },
    {
      documents: [
        {
          name: 'projects/p/databases/(default)/documents/users/u2',
          fields: encodeFields({ email: 'b@example.com' }),
        },
      ],
    },
  ];
  let call = 0;
  const fetchImpl = async () => jsonResponse(200, pages[call++]);
  const result = await listCollection('proj', 'users', { token: 't', fetchImpl });
  assert.deepEqual(result.map((r) => r.id), ['u1', 'u2']);
  assert.equal(call, 2);
});

test('runQuery decodes matching documents', async () => {
  const rows = [
    {
      document: {
        name: 'projects/p/databases/(default)/documents/shiftTrades/t1',
        fields: encodeFields({ eventKey: '2026miket', status: 'pending' }),
      },
    },
  ];
  const fetchImpl = async () => jsonResponse(200, rows);
  const result = await runQuery(
    'proj',
    whereEqualsQuery('shiftTrades', 'eventKey', '2026miket'),
    { token: 't', fetchImpl },
  );
  assert.deepEqual(result, [{ id: 't1', data: { eventKey: '2026miket', status: 'pending' } }]);
});

test('patchDocument sends only the requested fields and updateMask', async () => {
  let seenUrl;
  let seenBody;
  const fetchImpl = async (url, init) => {
    seenUrl = url;
    seenBody = JSON.parse(init.body);
    return jsonResponse(200, {});
  };
  await patchDocument(
    'proj',
    'appConfig/shiftCronState',
    { dmedShifts: { a: true } },
    ['dmedShifts', 'dmedTrades'],
    { token: 't', fetchImpl },
  );
  assert.match(seenUrl, /updateMask\.fieldPaths=dmedShifts/);
  assert.match(seenUrl, /updateMask\.fieldPaths=dmedTrades/);
  assert.deepEqual(seenBody.fields.dmedShifts, { mapValue: { fields: encodeFields({ a: true }) } });
});
