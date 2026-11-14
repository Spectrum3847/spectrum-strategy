import {
  getDocument,
  batchGetDocuments,
  listCollection,
  runQuery,
  whereQuery,
  patchDocument,
  setDocument,
  deleteDocument,
} from '../firestore.mjs';
import { compareEntry, buildScouterDmText } from './lib/accuracy_compare.mjs';
import { computeWindowStart } from './lib/accuracy_window.mjs';
import { fetchJsonWithTimeout } from '../tba.mjs';

const STATBOTICS_BASE = 'https://api.statbotics.io/v3';
const STATBOTICS_TIMEOUT_MS = 10_000;

const DEFAULT_WINDOW_MINUTES = 20;

const MAX_ENTRIES_PER_RUN = 150;
const MAX_MATCH_FETCHES = 25;
const MAX_ORPHAN_DELETES = 15;

async function fetchMatchCached(fetchImpl, tbaMatchKey, cache, noteFailure) {
  if (cache.has(tbaMatchKey)) return cache.get(tbaMatchKey);
  let result;
  try {
    result = await fetchJsonWithTimeout(
      fetchImpl,
      `${STATBOTICS_BASE}/match/${encodeURIComponent(tbaMatchKey)}`,
      { Accept: 'application/json' },
      STATBOTICS_TIMEOUT_MS,
    );
  } catch (err) {

    noteFailure(`Statbotics fetch for ${tbaMatchKey}`, err);
    result = undefined;
  }
  cache.set(tbaMatchKey, result);
  return result;
}

async function deleteOrphanedAlerts(project, opts) {
  const alerts = await listCollection(project, 'accuracyAlerts', opts);
  if (alerts.length === 0) return 0;
  const entries = await batchGetDocuments(
    project,
    alerts.map((alert) => `scoutEntries/${alert.id}`),
    opts,
  );
  let deleted = 0;
  for (const alert of alerts) {
    if (entries.get(`scoutEntries/${alert.id}`) !== null) continue;
    if (deleted >= MAX_ORPHAN_DELETES) {
      console.log(`Orphan sweep stopped at ${MAX_ORPHAN_DELETES}; the rest go next run.`);
      break;
    }
    if (await deleteDocument(project, `accuracyAlerts/${alert.id}`, opts)) deleted++;
  }
  return deleted;
}

async function runAccuracy(ctx) {
  const { project, fetchImpl, nowMs } = ctx;
  const opts = await ctx.opts();

  const cfg = await getDocument(project, 'appConfig/accuracyMapping', opts);
  if (!cfg) {
    console.log('No appConfig/accuracyMapping doc; nothing to compare.');
    return { skipped: 'no-mapping' };
  }
  if (!Array.isArray(cfg.mappings) || cfg.mappings.length === 0) {
    console.log('accuracyMapping has no mappings; nothing to compare.');
    return { skipped: 'no-mappings' };
  }

  const watermarkDoc = await getDocument(project, 'appConfig/accuracyCron', opts);
  const scanStart = ctx.nowIso();
  const windowStart = computeWindowStart({
    watermark: watermarkDoc?.lastScanEnd ?? null,
    nowMs,
    fallbackMinutes: Number(ctx.env.WINDOW_MINUTES) || DEFAULT_WINDOW_MINUTES,
  });
  const entries = await runQuery(
    project,
    whereQuery(
      'scoutEntries',
      [{ fieldPath: 'updatedAt', op: 'GREATER_THAN_OR_EQUAL', value: windowStart }],
      { orderBy: [{ fieldPath: 'updatedAt' }], limit: MAX_ENTRIES_PER_RUN },
    ),
    opts,
  );
  console.log(
    `${entries.length} entries updated since ${windowStart} ` +
      `(watermark: ${watermarkDoc?.lastScanEnd || 'none'}).`,
  );

  const matchCache = new Map();
  const stats = { created: 0, refreshed: 0, deleted: 0, skipped: 0, dmed: 0 };

  let drained = entries.length < MAX_ENTRIES_PER_RUN;
  let lastHandledUpdatedAt = null;

  for (const { id: entryId, data: entry } of entries) {
    if (
      entry.tbaMatchKey &&
      !matchCache.has(entry.tbaMatchKey) &&
      matchCache.size >= MAX_MATCH_FETCHES
    ) {
      console.log(`Reached ${MAX_MATCH_FETCHES} Statbotics fetches; resuming next run.`);
      drained = false;
      break;
    }
    if (typeof entry.updatedAt === 'string') lastHandledUpdatedAt = entry.updatedAt;

    if (!entry.tbaMatchKey) {
      if (await deleteDocument(project, `accuracyAlerts/${entryId}`, opts)) stats.deleted++;
      continue;
    }

    const matchData = await fetchMatchCached(
      fetchImpl,
      entry.tbaMatchKey,
      matchCache,
      ctx.noteFailure,
    );
    if (matchData === undefined || matchData === null) {
      stats.skipped++;
      continue;
    }

    const result = compareEntry(entry, matchData, cfg);
    if (result.comparedCount === 0) {

      stats.skipped++;
      continue;
    }

    if (!result.fires) {
      if (await deleteDocument(project, `accuracyAlerts/${entryId}`, opts)) stats.deleted++;
      continue;
    }

    const existing = await getDocument(project, `accuracyAlerts/${entryId}`, opts);
    const alert = {
      entryId,
      teamNumber: entry.teamNumber || 0,
      tbaMatchKey: entry.tbaMatchKey,
      authorUid: entry.authorUid || '',
      authorDisplayName: entry.authorDisplayName || '',
      flaggedFields: result.flaggedFields,
      comparedCount: result.comparedCount,
      wrongCount: result.wrongCount,
      egregious: result.egregious,
      createdAt: existing?.createdAt ?? scanStart,
      updatedAt: scanStart,
      acknowledged: existing?.acknowledged === true,
    };
    await setDocument(project, `accuracyAlerts/${entryId}`, alert, opts);

    if (existing) {
      stats.refreshed++;
      continue;
    }
    stats.created++;

    if (!alert.authorUid) continue;
    const sender = await ctx.dmSender();
    if (sender && (await sender(alert.authorUid, buildScouterDmText(alert)))) stats.dmed++;
  }

  if (drained) stats.deleted += await deleteOrphanedAlerts(project, opts);

  const nextWatermark = drained ? scanStart : (lastHandledUpdatedAt ?? windowStart);
  await patchDocument(
    project,
    'appConfig/accuracyCron',
    { lastScanEnd: nextWatermark },
    ['lastScanEnd'],
    opts,
  );

  console.log(
    `Accuracy: ${stats.created} created, ${stats.refreshed} refreshed, ` +
      `${stats.deleted} deleted, ${stats.skipped} skipped, ${stats.dmed} DM(s).`,
  );
  return stats;
}

export { runAccuracy };
