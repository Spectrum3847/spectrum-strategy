import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  setDocument,
  deleteDocument,
  batchGetDocuments,
  whereQuery,
  encodeValue,
  encodeFields,
} from '../src/firestore.mjs';

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), { status });
}

test('setDocument commits an update with no mask, which is a full overwrite', async () => {
  let seenUrl;
  let seenMethod;
  let seenBody;
  const fetchImpl = async (url, init) => {
    seenUrl = url;
    seenMethod = init.method;
    seenBody = JSON.parse(init.body);
    return jsonResponse(200, {});
  };
  const docsUrl = 'https://firestore.googleapis.com/v1/projects/proj/databases/(default)/documents';
  await setDocument('proj', 'telemetryRollup/current', { count: 3 }, { token: 't', fetchImpl });
  assert.equal(seenUrl, `${docsUrl}:commit`);
  assert.equal(seenMethod, 'POST');

  assert.deepEqual(seenBody, {
    writes: [
      {
        update: {
          name: 'projects/proj/databases/(default)/documents/telemetryRollup/current',
          fields: encodeFields({ count: 3 }),
        },
      },
    ],
  });
  assert.equal(seenBody.writes[0].update.name.startsWith('https://'), false);

  assert.equal('updateMask' in seenBody.writes[0], false);
});

test('deleteDocument returns true on 200', async () => {
  const fetchImpl = async () => jsonResponse(200, {});
  assert.equal(await deleteDocument('proj', 'accuracyAlerts/a1', { token: 't', fetchImpl }), true);
});

test('deleteDocument returns false on 404', async () => {
  const fetchImpl = async () => jsonResponse(404, { error: { message: 'not found' } });
  assert.equal(await deleteDocument('proj', 'accuracyAlerts/a1', { token: 't', fetchImpl }), false);
});

test('deleteDocument throws on 500', async () => {
  const fetchImpl = async () => jsonResponse(500, { error: { message: 'boom' } });
  await assert.rejects(() => deleteDocument('proj', 'accuracyAlerts/a1', { token: 't', fetchImpl }));
});

test('batchGetDocuments maps found documents to decoded fields and missing ones to null', async () => {
  const fetchImpl = async (url, init) => {
    const body = JSON.parse(init.body);
    assert.equal(body.documents.length, 2);
    return jsonResponse(200, [
      {
        found: {
          name: `${body.documents[0]}`,
          fields: encodeFields({ email: 'a@example.com' }),
        },
      },
      { missing: body.documents[1] },
    ]);
  };
  const result = await batchGetDocuments(
    'proj',
    ['scoutEntries/e1', 'scoutEntries/e2'],
    { token: 't', fetchImpl },
  );
  assert.deepEqual(result.get('scoutEntries/e1'), { email: 'a@example.com' });
  assert.equal(result.get('scoutEntries/e2'), null);
});

test('batchGetDocuments chunks at 300 paths per request', async () => {
  const paths = Array.from({ length: 620 }, (_, i) => `scoutEntries/e${i}`);
  const chunkSizes = [];
  const fetchImpl = async (url, init) => {
    const body = JSON.parse(init.body);
    chunkSizes.push(body.documents.length);
    return jsonResponse(200, []);
  };
  const result = await batchGetDocuments('proj', paths, { token: 't', fetchImpl });
  assert.deepEqual(chunkSizes, [300, 300, 20]);

  assert.equal(result.size, paths.length);
  assert.equal(result.get(paths[0]), null);
});

test('whereQuery with one filter emits a bare fieldFilter', () => {
  const query = whereQuery('shiftTrades', [{ fieldPath: 'eventKey', op: 'EQUAL', value: '2026miket' }]);
  assert.deepEqual(query.where, {
    fieldFilter: {
      field: { fieldPath: 'eventKey' },
      op: 'EQUAL',
      value: encodeValue('2026miket'),
    },
  });
  assert.equal(query.compositeFilter, undefined);
});

test('whereQuery with two filters emits a compositeFilter ANDing them', () => {
  const query = whereQuery('scoutEntries', [
    { fieldPath: 'eventKey', op: 'EQUAL', value: '2026miket' },
    { fieldPath: 'updatedAt', op: 'GREATER_THAN_OR_EQUAL', value: '2026-07-01T00:00:00.000Z' },
  ]);
  assert.equal(query.where.compositeFilter.op, 'AND');
  assert.equal(query.where.compositeFilter.filters.length, 2);
  assert.deepEqual(query.where.compositeFilter.filters[0], {
    fieldFilter: {
      field: { fieldPath: 'eventKey' },
      op: 'EQUAL',
      value: encodeValue('2026miket'),
    },
  });
});

test('whereQuery places limit, orderBy, and select where Firestore expects them', () => {
  const query = whereQuery(
    'scoutEntries',
    [{ fieldPath: 'eventKey', op: 'EQUAL', value: '2026miket' }],
    {
      limit: 150,
      orderBy: [{ fieldPath: 'updatedAt' }],
      select: ['updatedAt', 'tbaMatchKey'],
    },
  );
  assert.equal(query.limit, 150);
  assert.deepEqual(query.orderBy, [{ field: { fieldPath: 'updatedAt' }, direction: 'ASCENDING' }]);
  assert.deepEqual(query.select, {
    fields: [{ fieldPath: 'updatedAt' }, { fieldPath: 'tbaMatchKey' }],
  });
});

test('encodeValue encodes a Date as a Firestore timestampValue', () => {
  const date = new Date('2026-03-14T20:00:00.000Z');
  assert.deepEqual(encodeValue(date), { timestampValue: '2026-03-14T20:00:00.000Z' });
});

test('batchGetDocuments asks for resource names and maps the answers back', async () => {
  let seenBody;
  const root = 'projects/proj/databases/(default)/documents';
  const fetchImpl = async (url, init) => {
    seenBody = JSON.parse(init.body);

    return jsonResponse(200, [
      { found: { name: `${root}/scoutEntries/a`, fields: { x: { stringValue: 'y' } } } },
      { missing: `${root}/scoutEntries/b` },
    ]);
  };
  const out = await batchGetDocuments('proj', ['scoutEntries/a', 'scoutEntries/b'], {
    token: 't',
    fetchImpl,
  });
  assert.deepEqual(seenBody.documents, [`${root}/scoutEntries/a`, `${root}/scoutEntries/b`]);
  assert.equal(seenBody.documents.some((n) => n.startsWith('https://')), false);
  assert.deepEqual(out.get('scoutEntries/a'), { x: 'y' });
  assert.equal(out.get('scoutEntries/b'), null);
});
