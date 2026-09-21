function normalizeName(value) {
  return typeof value === 'string' ? value.toLowerCase().replace(/[^a-z0-9]/g, '') : '';
}

function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function matchCompetition({ eventKey, competitions, tbaEvent, override }) {
  const list = (competitions || []).filter((c) => typeof c === 'string' && c.trim());
  if (override && list.includes(override)) return override;
  const key = normalizeName(eventKey);
  const names = [tbaEvent?.short_name, tbaEvent?.name].map(normalizeName).filter(Boolean);
  for (const competition of list) {
    const c = normalizeName(competition);
    if (!c) continue;
    if (c === key) return competition;
    if (names.some((n) => n === c || n.includes(c))) return competition;
  }
  return null;
}

function buildUidTranslator(fromProfiles, toProfiles) {
  const emailToUid = new Map();
  for (const profile of toProfiles) {
    for (const email of emailsOf(profile)) {
      if (!emailToUid.has(email)) emailToUid.set(email, profile.uid);
    }
  }
  const uidToEmails = new Map(fromProfiles.map((p) => [p.uid, emailsOf(p)]));
  return (uid) => {
    for (const email of uidToEmails.get(uid) || []) {
      const match = emailToUid.get(email);
      if (match) return match;
    }
    return null;
  };
}

function emailsOf(profile) {
  const emails = [profile.email, ...(Array.isArray(profile.linkedEmails) ? profile.linkedEmails : [])];
  return emails.map(normalizeEmail).filter(Boolean);
}

function buildPitMirror({ eventKey, competition, pitShifts, translateUid, syncedAt }) {
  const shifts = pitShifts
    .map((shift) => {
      const uids = Array.isArray(shift.assignedUids) ? shift.assignedUids : [];
      const names = Array.isArray(shift.assignedNames) ? shift.assignedNames : [];
      const assignees = uids.map((uid, i) => {
        const assignee = { name: typeof names[i] === 'string' ? names[i] : '' };
        const mapped = translateUid(uid);
        if (mapped) assignee.uid = mapped;
        return assignee;
      });
      const out = {
        id: shift.id,
        label: typeof shift.label === 'string' ? shift.label : '',
        kind: typeof shift.kind === 'string' ? shift.kind : '',
        assignees,
      };
      for (const field of ['startMatch', 'endMatch']) {
        if (Number.isInteger(shift[field])) out[field] = shift[field];
      }
      for (const field of ['startsAt', 'endsAt', 'notes']) {
        if (typeof shift[field] === 'string' && shift[field]) out[field] = shift[field];
      }
      return out;
    })
    .sort(byId);
  return { eventKey, competition, shifts, syncedAt };
}

function buildScoutMirror({ eventKey, competition, matchCount, rotations, translateUid, syncedAt }) {
  const mirrored = (rotations || []).map((rotation) => {
    const out = {
      name: typeof rotation.name === 'string' ? rotation.name : '',
      shifts: (rotation.shifts || [])
        .filter((s) => Number.isInteger(s.startMatch) && Number.isInteger(s.endMatch))
        .map((s) => ({ startMatch: s.startMatch, endMatch: s.endMatch }))
        .sort((a, b) => a.startMatch - b.startMatch),
    };
    const mapped = rotation.uid ? translateUid(rotation.uid) : null;
    if (mapped) out.uid = mapped;
    return out;
  });
  return {
    eventKey,
    competition,
    matchCount: Number.isInteger(matchCount) ? matchCount : 0,
    rotations: mirrored,
    syncedAt,
  };
}

function byId(a, b) {
  return String(a.id).localeCompare(String(b.id));
}

export {
  matchCompetition,
  buildUidTranslator,
  buildPitMirror,
  buildScoutMirror,
  normalizeName,
};
