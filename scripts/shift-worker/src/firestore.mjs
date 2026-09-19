const FIRESTORE_BASE = 'https://firestore.googleapis.com/v1';

function documentsUrl(project) {
  return `${FIRESTORE_BASE}/projects/${project}/databases/(default)/documents`;
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
  const res = await fetchImpl(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  return { status: res.status, ok: res.ok, data };
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

async function listCollection(project, collectionId, opts) {
  const results = [];
  let pageToken;
  do {
    const url = new URL(`${documentsUrl(project)}/${collectionId}`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const { status, ok, data } = await rawRequest(url.toString(), opts);
    throwIfQuotaExceeded(status, data);
    if (!ok) {
      throw new Error(`Firestore list ${collectionId} failed: HTTP ${status} ${JSON.stringify(data)}`);
    }
    for (const doc of data.documents || []) {
      results.push({ id: docIdFromName(doc.name), data: decodeFields(doc.fields || {}) });
    }
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

function whereEqualsQuery(collectionId, fieldPath, value) {
  return {
    from: [{ collectionId }],
    where: {
      fieldFilter: {
        field: { fieldPath },
        op: 'EQUAL',
        value: encodeValue(value),
      },
    },
  };
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

export {
  decodeValue,
  decodeFields,
  encodeValue,
  encodeFields,
  getDocument,
  listCollection,
  runQuery,
  whereEqualsQuery,
  patchDocument,
  isQuotaExceededResponse,
  FirestoreQuotaError,
};
