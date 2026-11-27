import { encodeFields, encodeValue, decodeFields, decodeValue } from '../../src/firestore.mjs';

function parseRequest(urlStr) {
  const url = new URL(urlStr);
  const parts = url.pathname.split('/');

  const project = parts[3];
  const [, action] = parts[6].split(':');
  const restSegments = parts.slice(7).filter(Boolean);
  return { project, action: action ?? null, restSegments };
}

function resourceNameToPath(name) {

  const marker = '/documents/';
  const idx = name.indexOf(marker);
  const path = name.slice(idx + marker.length);
  const segments = path.split('/');
  return { collection: segments[0], id: segments.slice(1).join('/') };
}

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), { status });
}

function matchesFilter(fields, filter) {
  if (!filter) return true;

  const actual = decodeValue(encodeValue(fields[filter.field.fieldPath]));
  const wanted = decodeValue(filter.value);
  switch (filter.op) {
    case 'EQUAL':
      return actual === wanted;
    case 'NOT_EQUAL':
      return actual !== wanted;
    case 'GREATER_THAN':
      return actual > wanted;
    case 'GREATER_THAN_OR_EQUAL':
      return actual >= wanted;
    case 'LESS_THAN':
      return actual < wanted;
    case 'LESS_THAN_OR_EQUAL':
      return actual <= wanted;
    default:
      return actual === wanted;
  }
}

function createFakeFirestore(seed = {}) {
  const store = {};
  for (const [project, collections] of Object.entries(seed)) {
    store[project] = {};
    for (const [collection, docs] of Object.entries(collections)) {
      store[project][collection] = { ...docs };
    }
  }
  const requests = [];

  function collectionOf(project, collection) {
    store[project] ??= {};
    store[project][collection] ??= {};
    return store[project][collection];
  }

  async function fetchImpl(urlStr, init = {}) {
    const method = init.method ?? 'GET';
    requests.push({ url: urlStr, method });
    const { project, action, restSegments } = parseRequest(urlStr);

    if (action === 'commit') {
      const body = JSON.parse(init.body);
      for (const write of body.writes) {
        const { collection, id } = resourceNameToPath(write.update.name);
        collectionOf(project, collection)[id] = decodeFields(write.update.fields);
      }
      return jsonResponse(200, {});
    }

    if (action === 'listCollectionIds') {
      store[project] ??= {};
      const nonEmpty = Object.entries(store[project])
        .filter(([, docs]) => Object.keys(docs).length > 0)
        .map(([collection]) => collection);
      return jsonResponse(200, { collectionIds: nonEmpty });
    }

    if (action === 'runQuery') {
      const body = JSON.parse(init.body);
      const { from, where, limit } = body.structuredQuery;
      const collection = from[0].collectionId;
      const docs = collectionOf(project, collection);
      const filter = where?.fieldFilter;
      let rows = Object.entries(docs)
        .filter(([, fields]) => matchesFilter(fields, filter))
        .map(([id, fields]) => ({
          document: {
            name: `projects/${project}/databases/(default)/documents/${collection}/${id}`,
            fields: encodeFields(fields),
          },
        }));
      if (Number.isInteger(limit)) rows = rows.slice(0, limit);
      return jsonResponse(200, rows);
    }

    if (method === 'DELETE') {
      const [collection, id] = restSegments;
      const existed = id in collectionOf(project, collection);
      delete collectionOf(project, collection)[id];
      return jsonResponse(existed ? 200 : 404, {});
    }

    if (restSegments.length % 2 === 1) {

      const [collection] = restSegments;
      const docs = collectionOf(project, collection);
      const ids = Object.keys(docs).sort();
      const url = new URL(urlStr);
      const pageSize = Number(url.searchParams.get('pageSize')) || ids.length || 1;
      const offset = Number(url.searchParams.get('pageToken')) || 0;
      const page = ids.slice(offset, offset + pageSize);
      const documents = page.map((id) => ({
        name: `projects/${project}/databases/(default)/documents/${collection}/${id}`,
        fields: encodeFields(docs[id]),
      }));
      const nextOffset = offset + pageSize;
      const body = { documents };
      if (nextOffset < ids.length) body.nextPageToken = String(nextOffset);
      return jsonResponse(200, body);
    }

    const [collection, ...idParts] = restSegments;
    const id = idParts.join('/');
    const docs = collectionOf(project, collection);
    if (!(id in docs)) return jsonResponse(404, { error: { message: 'not found' } });
    return jsonResponse(200, { fields: encodeFields(docs[id]) });
  }

  return { fetchImpl, requests, store };
}

export { createFakeFirestore };
