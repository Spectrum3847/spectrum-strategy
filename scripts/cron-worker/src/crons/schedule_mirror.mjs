import {
  getDocument,
  listCollection,
  runQuery,
  whereEqualsQuery,
  setDocument,
  deleteDocument,
} from '../firestore.mjs';
import { applyAcceptedTrades } from '../schedule.mjs';
import { fetchEventSimple } from '../tba.mjs';
import {
  matchCompetition,
  buildUidTranslator,
  buildPitMirror,
  buildScoutMirror,
} from './lib/mirror.mjs';
import { fingerprintInputs, hashFingerprint } from './lib/fingerprint.mjs';

const STATE_DOC = 'appConfig/scheduleMirrorState';
const MAX_FINGERPRINT_AGE_MS = 24 * 60 * 60 * 1000;

async function readProfiles(project, opts) {
  const profiles = await listCollection(project, 'userProfiles', opts);
  return profiles.map(({ id, data }) => ({
    uid: id,
    email: data.email,
    linkedEmails: data.linkedEmails,
  }));
}

async function runScheduleMirror(ctx) {
  const { project, pitProject, fetchImpl } = ctx;
  const opts = await ctx.opts();
  const pitOpts = await ctx.pitOpts();

  const activeEvent = await getDocument(project, 'appConfig/activeEvent', opts);
  const eventKey = activeEvent?.eventKey;
  if (!eventKey) {
    console.log('No appConfig/activeEvent.eventKey; nothing to mirror.');
    return { skipped: 'no-active-event' };
  }

  const [mirrorConfig, apiKeys, pitShiftDocs, schedule, tradeDocs, previousState] =
    await Promise.all([
      getDocument(project, 'appConfig/scheduleMirror', opts),
      getDocument(project, 'appConfig/apiKeys', opts),
      listCollection(pitProject, 'pitShifts', pitOpts),
      getDocument(project, `scoutShifts/${eventKey}`, opts),
      runQuery(project, whereEqualsQuery('shiftTrades', 'eventKey', eventKey), opts),
      getDocument(project, STATE_DOC, opts),
    ]);
  const override = mirrorConfig?.pitCompetition ?? null;
  const tbaKey = apiKeys?.tba ?? null;
  const tbaEvent = tbaKey ? await fetchEventSimple(fetchImpl, tbaKey, eventKey) : null;

  const pitShifts = pitShiftDocs.map(({ id, data }) => ({ id, ...data }));
  const competitions = [...new Set(pitShifts.map((s) => s.competition))];
  const competition = matchCompetition({ eventKey, competitions, tbaEvent, override });
  const trades = tradeDocs.map(({ data }) => data);
  const rotations = schedule
    ? applyAcceptedTrades(Array.isArray(schedule.rotations) ? schedule.rotations : [], trades)
    : [];

  const fingerprint = await hashFingerprint(
    fingerprintInputs({ eventKey, override, tbaEvent, pitShiftDocs, schedule, tradeDocs }),
  );
  const ageMs = previousState ? ctx.nowMs - Date.parse(previousState.syncedAt) : Infinity;
  if (previousState?.fingerprint === fingerprint && Number.isFinite(ageMs) && ageMs < MAX_FINGERPRINT_AGE_MS) {
    const fingerprintAgeMinutes = Math.round(ageMs / 60_000);
    console.log(
      `scheduleMirror: unchanged since last run (${fingerprintAgeMinutes}m ago); ` +
        'skipping both userProfiles reads.',
    );
    return { skipped: 'unchanged', fingerprintAgeMinutes };
  }

  const [ourProfiles, pitProfiles] = await Promise.all([
    readProfiles(project, opts),
    readProfiles(pitProject, pitOpts),
  ]);

  const syncedAt = ctx.nowIso();
  const stamp = { syncedAt, updatedAtTs: new Date(ctx.nowMs) };
  const stats = { pitShifts: 0, rotations: 0 };

  if (competition) {
    const pitDoc = buildPitMirror({
      eventKey,
      competition,
      pitShifts: pitShifts.filter((s) => s.competition === competition),
      translateUid: buildUidTranslator(pitProfiles, ourProfiles),
      syncedAt,
    });
    await setDocument(project, `pitShifts/${eventKey}`, { ...pitDoc, ...stamp }, opts);
    stats.pitShifts = pitDoc.shifts.length;
    console.log(
      `Wrote pitShifts/${eventKey}: ${pitDoc.shifts.length} shift(s) from "${competition}".`,
    );
  } else {
    await deleteDocument(project, `pitShifts/${eventKey}`, opts);
    console.log(
      `No pit competition matches ${eventKey} (candidates: ${competitions.join(', ') || 'none'}); ` +
        'cleared pitShifts here.',
    );
  }

  if (!schedule) {
    console.log(`No scoutShifts/${eventKey}; nothing to mirror into the pit app.`);
    await setDocument(project, STATE_DOC, { fingerprint, ...stamp }, opts);
    return { ...stats, skipped: 'no-schedule' };
  }
  const scoutDoc = buildScoutMirror({
    eventKey,
    competition: competition || tbaEvent?.short_name || eventKey,
    matchCount: schedule.matchCount,
    rotations,
    translateUid: buildUidTranslator(ourProfiles, pitProfiles),
    syncedAt,
  });
  await setDocument(pitProject, `scoutShifts/${eventKey}`, { ...scoutDoc, ...stamp }, pitOpts);
  stats.rotations = scoutDoc.rotations.length;
  console.log(
    `Wrote scoutShifts/${eventKey} in ${pitProject}: ${scoutDoc.rotations.length} rotation(s) ` +
      `under "${scoutDoc.competition}".`,
  );
  await setDocument(project, STATE_DOC, { fingerprint, ...stamp }, opts);
  return stats;
}

export { runScheduleMirror };
