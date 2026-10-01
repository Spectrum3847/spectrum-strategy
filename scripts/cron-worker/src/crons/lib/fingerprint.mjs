function sortByDocId(docs) {
  return [...docs].sort((a, b) => String(a.id).localeCompare(String(b.id)));
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = canonicalize(value[key]);
    return out;
  }
  return value;
}

function fingerprintInputs({ eventKey, override, tbaEvent, pitShiftDocs, schedule, tradeDocs }) {
  return canonicalize({
    eventKey,
    override: override ?? null,
    tbaShortName: tbaEvent?.short_name ?? null,
    tbaName: tbaEvent?.name ?? null,
    pitShifts: sortByDocId(pitShiftDocs).map(({ id, data }) => ({ id, ...data })),
    scoutShifts: schedule ?? null,
    shiftTrades: sortByDocId(tradeDocs).map(({ id, data }) => ({ id, ...data })),
  });
}

async function hashFingerprint(inputs) {
  const bytes = new TextEncoder().encode(JSON.stringify(inputs));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export { canonicalize, sortByDocId, fingerprintInputs, hashFingerprint };
