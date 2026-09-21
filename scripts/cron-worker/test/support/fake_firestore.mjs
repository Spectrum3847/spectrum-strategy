import { encodeFields, decodeFields, decodeValue } from '../../src/firestore.mjs';

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

    if (action === 'runQuery') {
      const body = JSON.parse(init.body);
      const { from, where } = body.structuredQuery;
      const collection = from[0].collectionId;
      const docs = collectionOf(project, collection);
      const filter = where?.fieldFilter;
      const rows = Object.entries(docs)
        .filter(([, fields]) => {
          if (!filter) return true;
          const wanted = decodeValue(filter.value);
          return fields[filter.field.fieldPath] === wanted;
        })
        .map(([id, fields]) => ({
          document: {
            name: `projects/${project}/databases/(default)/documents/${collection}/${id}`,
            fields: encodeFields(fields),
          },
        }));
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
      const documents = Object.entries(docs).map(([id, fields]) => ({
        name: `projects/${project}/databases/(default)/documents/${collection}/${id}`,
        fields: encodeFields(fields),
      }));
      return jsonResponse(200, { documents });
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
