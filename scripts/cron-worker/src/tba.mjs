const TBA_BASE = 'https://www.thebluealliance.com/api/v3';
const TBA_TIMEOUT_MS = 10_000;

async function fetchJsonWithTimeout(fetchImpl, url, headers, timeoutMs = TBA_TIMEOUT_MS) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const res = await fetchImpl(url, { headers, signal: ctl.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

function tbaHeaders(tbaKey) {
  return { Accept: 'application/json', 'X-TBA-Auth-Key': tbaKey };
}

async function fetchEventSimple(fetchImpl, tbaKey, eventKey) {
  try {
    return await fetchJsonWithTimeout(
      fetchImpl,
      `${TBA_BASE}/event/${encodeURIComponent(eventKey)}/simple`,
      tbaHeaders(tbaKey),
    );
  } catch (err) {
    console.error('TBA event fetch error:', err && err.message ? err.message : err);
    return null;
  }
}

async function fetchEventMatchesSimple(fetchImpl, tbaKey, eventKey) {
  try {
    return await fetchJsonWithTimeout(
      fetchImpl,
      `${TBA_BASE}/event/${encodeURIComponent(eventKey)}/matches/simple`,
      tbaHeaders(tbaKey),
    );
  } catch (err) {
    console.error('TBA matches fetch error:', err && err.message ? err.message : err);
    return null;
  }
}

export { fetchEventSimple, fetchEventMatchesSimple, fetchJsonWithTimeout, TBA_BASE };
