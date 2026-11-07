const FIRESTORE_BASE = 'https://firestore.googleapis.com/v1';

const REQUEST_TIMEOUT_MS = 10_000;

function documentsUrl(project) {
  return `${FIRESTORE_BASE}/${documentsRoot(project)}`;
}

function documentsRoot(project) {
  return `projects/${project}/databases/(default)/documents`;
}

function documentName(project, path) {
  return `${documentsRoot(project)}/${path}`;
}

function docIdFromName(name) {
  const parts = String(name || '').split('/');
  return parts[parts.length - 1];
}

function decodeValue(value) {
  if (value == null || 'nullValue' in value) return null;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('stringValue' in value) return value.stringValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decodeValue);
  if ('mapValue' in value) return decodeFields(value.mapValue.fields || {});
  if ('referenceValue' in value) return value.referenceValue;
  if ('geoPointValue' in value) return value.geoPointValue;
  if ('bytesValue' in value) return value.bytesValue;
  return null;
}

function decodeFields(fields) {
  const out = {};
  for (const [key, value] of Object.entries(fields || {})) {
    out[key] = decodeValue(value);
  }
  return out;
}

function encodeValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (typeof value === 'string') return { stringValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };

  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === 'object') return { mapValue: { fields: encodeFields(value) } };
  throw new Error(`cannot encode Firestore value of type ${typeof value}`);
}

function encodeFields(obj) {
  const fields = {};
  for (const [key, value] of Object.entries(obj || {})) {
    fields[key] = encodeValue(value);
  }
  return fields;
}

class FirestoreQuotaError extends Error {}

function isQuotaExceededResponse(status, body) {
  if (status === 429) return true;
  const message = JSON.stringify(body || {}).toUpperCase();
  return message.includes('RESOURCE_EXHAUSTED') || message.includes('QUOTA_EXCEEDED') || message.includes('QUOTA EXCEEDED');
}

async function rawRequest(url, { token, method = 'GET', body, fetchImpl = fetch } = {}) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), REQUEST_TIMEOUT_MS);
  try {
    const res = await fetchImpl(url, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: ctl.signal,
    });
    const data = await res.json().catch(() => ({}));
    return { status: res.status, ok: res.ok, data };
  } finally {
    clearTimeout(timer);
  }
}

function throwIfQuotaExceeded(status, data) {
  if (isQuotaExceededResponse(status, data)) {
    throw new FirestoreQuotaError(`Firestore quota exceeded: HTTP ${status}`);
  }
}

async function getDocument(project, path, opts) {
  const url = `${documentsUrl(project)}/${path}`;
  const { status, ok, data } = await rawRequest(url, opts);
  if (status === 404) return null;
  throwIfQuotaExceeded(status, data);
  if (!ok) throw new Error(`Firestore GET ${path} failed: HTTP ${status} ${JSON.stringify(data)}`);
  return decodeFields(data.fields || {});
}

async function listCollectionPage(project, collectionId, opts, { pageToken, pageSize = 300 } = {}) {
  const url = new URL(`${documentsUrl(project)}/${collectionId}`);
  url.searchParams.set('pageSize', String(pageSize));
  if (pageToken) url.searchParams.set('pageToken', pageToken);
  const { status, ok, data } = await rawRequest(url.toString(), opts);
  throwIfQuotaExceeded(status, data);
  if (!ok) {
    throw new Error(`Firestore list ${collectionId} failed: HTTP ${status} ${JSON.stringify(data)}`);
  }
  const docs = (data.documents || []).map((doc) => ({
    id: docIdFromName(doc.name),
    data: decodeFields(doc.fields || {}),
  }));
  return { docs, nextPageToken: data.nextPageToken || null };
}

async function listCollection(project, collectionId, opts) {
  const results = [];
  let pageToken;
  do {
    const { docs, nextPageToken } = await listCollectionPage(project, collectionId, opts, { pageToken });
    results.push(...docs);
    pageToken = nextPageToken;
  } while (pageToken);
  return results;
}

async function listCollectionIds(project, opts) {
  const results = [];
  let pageToken;
  do {
    const body = { pageSize: 300 };
    if (pageToken) body.pageToken = pageToken;
    const { status, ok, data } = await rawRequest(`${documentsUrl(project)}:listCollectionIds`, {
      ...opts,
      method: 'POST',
      body,
    });
    throwIfQuotaExceeded(status, data);
    if (!ok) {
      throw new Error(`Firestore listCollectionIds failed: HTTP ${status} ${JSON.stringify(data)}`);
    }
    results.push(...(data.collectionIds || []));
    pageToken = data.nextPageToken;
  } while (pageToken);
  return results;
}

async function runQuery(project, structuredQuery, opts) {
  const url = `${documentsUrl(project)}:runQuery`;
  const { status, ok, data } = await rawRequest(url, {
    ...opts,
    method: 'POST',
    body: { structuredQuery },
  });
  throwIfQuotaExceeded(status, data);
  if (!ok) throw new Error(`Firestore runQuery failed: HTTP ${status} ${JSON.stringify(data)}`);
  const rows = Array.isArray(data) ? data : [];
  return rows
    .filter((row) => row.document)
    .map((row) => ({ id: docIdFromName(row.document.name), data: decodeFields(row.document.fields || {}) }));
}

function whereQuery(collectionId, filters, { limit, orderBy, select } = {}) {
  const fieldFilters = filters.map(({ fieldPath, op, value }) => ({
    fieldFilter: { field: { fieldPath }, op, value: encodeValue(value) },
  }));
  const query = { from: [{ collectionId }] };
  if (fieldFilters.length === 1) {
    query.where = fieldFilters[0];
  } else if (fieldFilters.length > 1) {
    query.where = { compositeFilter: { op: 'AND', filters: fieldFilters } };
  }
  if (Array.isArray(orderBy) && orderBy.length > 0) {
    query.orderBy = orderBy.map(({ fieldPath, direction = 'ASCENDING' }) => ({
      field: { fieldPath },
      direction,
    }));
  }
  if (Array.isArray(select) && select.length > 0) {
    query.select = { fields: select.map((fieldPath) => ({ fieldPath })) };
  }
  if (Number.isInteger(limit)) query.limit = limit;
  return query;
}

function whereEqualsQuery(collectionId, fieldPath, value) {
  return whereQuery(collectionId, [{ fieldPath, op: 'EQUAL', value }]);
}

async function patchDocument(project, path, fields, updateMaskFieldPaths, opts) {
  const params = updateMaskFieldPaths
    .map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`)
    .join('&');
  const url = `${documentsUrl(project)}/${path}?${params}`;
  const { status, ok, data } = await rawRequest(url, {
    ...opts,
    method: 'PATCH',
    body: { fields: encodeFields(fields) },
  });
  throwIfQuotaExceeded(status, data);
  if (!ok) throw new Error(`Firestore PATCH ${path} failed: HTTP ${status} ${JSON.stringify(data)}`);
  return data;
}

async function setDocument(project, path, fields, opts) {
  const { status, ok, data } = await rawRequest(`${documentsUrl(project)}:commit`, {
    ...opts,
    method: 'POST',
    body: {
      writes: [
        { update: { name: documentName(project, path), fields: encodeFields(fields) } },
      ],
    },
  });
  throwIfQuotaExceeded(status, data);
  if (!ok) throw new Error(`Firestore SET ${path} failed: HTTP ${status} ${JSON.stringify(data)}`);
  return data;
}

async function deleteDocument(project, path, opts) {
  const url = `${documentsUrl(project)}/${path}`;
  const { status, ok, data } = await rawRequest(url, { ...opts, method: 'DELETE' });
  if (status === 404) return false;
  throwIfQuotaExceeded(status, data);
  if (!ok) {
    throw new Error(`Firestore DELETE ${path} failed: HTTP ${status} ${JSON.stringify(data)}`);
  }
  return true;
}

const BATCH_GET_CHUNK = 300;

async function batchGetDocuments(project, paths, opts) {
  const out = new Map();
  for (let i = 0; i < paths.length; i += BATCH_GET_CHUNK) {
    const chunk = paths.slice(i, i + BATCH_GET_CHUNK);
    const byName = new Map(chunk.map((path) => [documentName(project, path), path]));
    const { status, ok, data } = await rawRequest(`${documentsUrl(project)}:batchGet`, {
      ...opts,
      method: 'POST',
      body: { documents: [...byName.keys()] },
    });
    throwIfQuotaExceeded(status, data);
    if (!ok) {
      throw new Error(`Firestore batchGet failed: HTTP ${status} ${JSON.stringify(data)}`);
    }
    for (const row of Array.isArray(data) ? data : []) {
      if (row.found) {
        const path = byName.get(row.found.name);
        if (path) out.set(path, decodeFields(row.found.fields || {}));
      } else if (row.missing) {
        const path = byName.get(row.missing);
        if (path) out.set(path, null);
      }
    }
    for (const path of chunk) if (!out.has(path)) out.set(path, null);
  }
  return out;
}

export {
  documentName,
  decodeValue,
  decodeFields,
  encodeValue,
  encodeFields,
  getDocument,
  batchGetDocuments,
  listCollection,
  listCollectionPage,
  listCollectionIds,
  runQuery,
  whereQuery,
  whereEqualsQuery,
  patchDocument,
  setDocument,
  deleteDocument,
  isQuotaExceededResponse,
  FirestoreQuotaError,
};
