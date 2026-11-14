import { listCollectionIds, listCollectionPage, runQuery, whereQuery } from '../firestore.mjs';
import { datesToPrune } from './lib/backup_retention.mjs';

const DEFAULT_SUBREQUEST_BUDGET = 40;
const PAGE_SIZE = 300;

const DEFAULT_MAX_COMBINED_BYTES = 20 * 1024 * 1024;

const RECENT_ACTIVITY_WINDOW_MS = 2 * 60 * 60 * 1000;

const DAILY_SLOT_HOUR_UTC = 8;

const PRUNE_STATE_KEY = 'backups/_prune_state.json';

function dateStamp(nowMs) {
  return new Date(nowMs).toISOString().slice(0, 10);
}

function isDailySlotHour(nowMs) {
  return new Date(nowMs).getUTCHours() === DAILY_SLOT_HOUR_UTC;
}

function hourSlot(nowMs) {
  return `hour-${String(new Date(nowMs).getUTCHours()).padStart(2, '0')}`;
}

function manifestKey(date, slot) {
  return `backups/${date}/${slot}/_manifest.json`;
}

function snapshotKey(date, slot) {
  return `backups/${date}/${slot}/snapshot.json`;
}

function createBudget(limit) {
  let used = 0;
  return {
    remaining: () => limit - used,
    spend: (n = 1) => {
      used += n;
    },
  };
}

function budgetFromEnv(env) {
  const raw = Number(env.BACKUP_SUBREQUEST_BUDGET);
  return Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_SUBREQUEST_BUDGET;
}

function pageSizeFromEnv(env) {
  const raw = Number(env.BACKUP_PAGE_SIZE);
  return Number.isFinite(raw) && raw > 0 ? raw : PAGE_SIZE;
}

function maxCombinedBytesFromEnv(env) {
  const raw = Number(env.BACKUP_MAX_COMBINED_BYTES);
  return Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_MAX_COMBINED_BYTES;
}

async function hasRecentScoutingActivity(project, opts, budget, nowMs) {
  budget.spend();
  const since = new Date(nowMs - RECENT_ACTIVITY_WINDOW_MS);
  const rows = await runQuery(
    project,
    whereQuery(
      'scoutEntries',
      [{ fieldPath: 'updatedAtTs', op: 'GREATER_THAN_OR_EQUAL', value: since }],
      { limit: 1, select: ['updatedAtTs'] },
    ),
    opts,
  );
  return rows.length > 0;
}

function emptyManifest(date, slot) {
  return { date, slot, completed: {}, skipped: [], partial: {}, existed: false };
}

async function readManifest(bucket, date, slot) {
  const object = await bucket.get(manifestKey(date, slot));
  if (!object) return emptyManifest(date, slot);
  try {
    const parsed = JSON.parse(await object.text());
    return {
      ...emptyManifest(date, slot),
      ...parsed,
      completed: parsed.completed || {},
      partial: parsed.partial || {},
      existed: true,
    };
  } catch {
    return emptyManifest(date, slot);
  }
}

async function writeManifest(bucket, date, slot, manifest, budget) {
  budget.spend();
  const { existed, ...toWrite } = manifest;
  await bucket.put(manifestKey(date, slot), JSON.stringify(toWrite), {
    httpMetadata: { contentType: 'application/json' },
  });
}

async function fetchCollection(project, collectionId, opts, budget, partial, pageSize, maxBytes) {

  if (partial && partial.pageToken === null) {
    return { documents: partial.documents, truncated: false, pageToken: null };
  }

  const docs = partial?.documents ? [...partial.documents] : [];
  let sizeSoFar = docs.length ? JSON.stringify(docs).length : 0;
  let pageToken = partial?.pageToken || undefined;
  let exhausted = false;

  while (true) {
    if (budget.remaining() <= 1 || sizeSoFar >= maxBytes) break;
    budget.spend();
    const page = await listCollectionPage(project, collectionId, opts, { pageToken, pageSize });
    docs.push(...page.docs);
    sizeSoFar += JSON.stringify(page.docs).length;
    pageToken = page.nextPageToken;
    if (!pageToken) {
      exhausted = true;
      break;
    }
  }

  if (!exhausted) {
    return { documents: docs, truncated: true, pageToken };
  }
  if (sizeSoFar > maxBytes) {
    return { documents: docs, truncated: true, pageToken: null };
  }
  return { documents: docs, truncated: false, pageToken: null };
}

async function readSnapshotCollections(bucket, date, slot, budget) {
  budget.spend();
  const object = await bucket.get(snapshotKey(date, slot));
  if (!object) return { collections: {}, size: 0 };
  const text = await object.text();
  try {
    const parsed = JSON.parse(text);
    return { collections: parsed.collections || {}, size: text.length };
  } catch {
    return { collections: {}, size: 0 };
  }
}

async function writeSnapshot(bucket, date, slot, collections, nowIso, budget) {
  budget.spend();
  await bucket.put(
    snapshotKey(date, slot),
    JSON.stringify({ date, slot, exportedAt: nowIso, collections }),
    { httpMetadata: { contentType: 'application/json' } },
  );
}

async function listAllKeys(bucket, prefix, budget) {
  const keys = [];
  let cursor;
  do {
    if (budget.remaining() <= 1) break;
    budget.spend();
    const page = await bucket.list({ prefix, cursor });
    for (const object of page.objects || []) keys.push(object.key);
    cursor = page.truncated ? page.cursor : null;
  } while (cursor);
  return keys;
}

async function pruneOldBackups(bucket, today, budget, noteFailure) {
  const keys = await listAllKeys(bucket, 'backups/', budget);
  const dates = new Set();
  for (const key of keys) {
    const match = /^backups\/(\d{4}-\d{2}-\d{2})\//.exec(key);
    if (match) dates.add(match[1]);
  }
  const stale = datesToPrune([...dates], today);
  let pruned = 0;
  for (const date of stale) {
    if (budget.remaining() <= 1) break;
    try {
      const dayKeys = await listAllKeys(bucket, `backups/${date}/`, budget);
      if (dayKeys.length === 0) continue;
      budget.spend();
      await bucket.delete(dayKeys);
      pruned += dayKeys.length;
    } catch (err) {
      noteFailure(`pruning backups/${date}`, err);
    }
  }
  return pruned;
}

async function readPruneState(bucket, budget) {
  budget.spend();
  const object = await bucket.get(PRUNE_STATE_KEY);
  if (!object) return { prunedDate: null };
  try {
    return JSON.parse(await object.text());
  } catch {
    return { prunedDate: null };
  }
}

async function markPruned(bucket, date, budget) {
  budget.spend();
  await bucket.put(PRUNE_STATE_KEY, JSON.stringify({ prunedDate: date }));
}

function isLastOpportunity(live, nowMs) {
  return live || new Date(nowMs).getUTCHours() === 23;
}

async function exportSlot(ctx, bucket, opts, budget, date, slot, live, manifest) {
  const { project } = ctx;
  const pageSize = pageSizeFromEnv(ctx.env);
  const maxCombinedBytes = maxCombinedBytesFromEnv(ctx.env);
  const lastChanceToday = isLastOpportunity(live, ctx.nowMs);

  budget.spend();
  const collectionIds = (await listCollectionIds(project, opts)).sort();

  const pending = collectionIds.filter((id) => !(id in manifest.completed));
  const skipped = [];
  const deferred = [];
  const finished = {};

  for (const collectionId of pending) {
    if (budget.remaining() <= 1) {
      skipped.push(collectionId);
      deferred.push(collectionId);
      continue;
    }
    try {
      const { documents, truncated, pageToken } = await fetchCollection(
        project,
        collectionId,
        opts,
        budget,
        manifest.partial[collectionId],
        pageSize,
        maxCombinedBytes,
      );
      if (truncated) {
        skipped.push(collectionId);
        deferred.push(collectionId);
        manifest.partial[collectionId] = { documents, pageToken };
      } else {
        finished[collectionId] = { count: documents.length, documents };
      }
    } catch (err) {

      ctx.noteFailure(`backing up ${collectionId}`, err);
      skipped.push(collectionId);
    }
  }

  const finishedIds = Object.keys(finished);
  if (finishedIds.length > 0) {
    const existing = await readSnapshotCollections(bucket, date, slot, budget);
    const collections = { ...existing.collections };
    let size = existing.size;
    let changed = false;
    for (const collectionId of finishedIds) {
      const fragment = finished[collectionId];
      const fragmentSize = JSON.stringify(fragment).length;
      if (size + fragmentSize > maxCombinedBytes) {
        skipped.push(collectionId);
        deferred.push(collectionId);
        manifest.partial[collectionId] = { documents: fragment.documents, pageToken: null };
        continue;
      }
      collections[collectionId] = fragment;
      size += fragmentSize;
      changed = true;
      delete manifest.partial[collectionId];
      manifest.completed[collectionId] = fragment.count;
    }
    if (changed) {
      await writeSnapshot(bucket, date, slot, collections, ctx.nowIso(), budget);
    }
  }

  if (deferred.length > 0) {
    if (lastChanceToday) {
      for (const collectionId of deferred) {
        ctx.noteFailure(
          `backing up ${collectionId}`,
          new Error(`deferred with no opportunity left for ${date}/${slot}`),
        );
      }
    } else {
      console.log(`Backup ${date}/${slot}: deferring ${deferred.join(', ')} to a later invocation today.`);
    }
  }

  manifest.skipped = skipped;
  await writeManifest(bucket, date, slot, manifest, budget);
  const partial = skipped.length > 0;

  let pruned = 0;
  if (!partial) {
    const pruneState = await readPruneState(bucket, budget);
    if (pruneState.prunedDate !== date) {
      try {
        pruned = await pruneOldBackups(bucket, date, budget, ctx.noteFailure);
        await markPruned(bucket, date, budget);
      } catch (err) {
        ctx.noteFailure('pruning old backups', err);
      }
    }
  }

  const backedUp = Object.keys(manifest.completed).length;
  console.log(
    `Backup ${date}/${slot}${live ? ' (recent scouting activity)' : ''}: ${backedUp}/` +
      `${collectionIds.length} collection(s) written` +
      (partial ? `, ${skipped.length} deferred` : '') +
      (pruned ? `, pruned ${pruned} stale object(s)` : '') +
      '.',
  );
  return { date, slot, live, collections: backedUp, total: collectionIds.length, partial, skipped, pruned };
}

async function runBackup(ctx) {
  const { project, nowMs } = ctx;
  const opts = await ctx.opts();

  const bucket = ctx.env.PHOTOS;
  if (!bucket) {
    console.log('No photo bucket binding; skipping the Firestore backup.');
    return { skipped: 'no-bucket' };
  }

  const budget = createBudget(budgetFromEnv(ctx.env));
  budget.spend();

  const live = await hasRecentScoutingActivity(project, opts, budget, nowMs);
  const date = dateStamp(nowMs);
  const slot = live ? hourSlot(nowMs) : 'daily';

  budget.spend();
  const manifest = await readManifest(bucket, date, slot);

  if (!live && !manifest.existed && !isDailySlotHour(nowMs)) {

    console.log("No recent scouting activity, today's daily backup has not started, and this is not its hour.");
    return { skipped: 'not-daily-slot', live };
  }

  return exportSlot(ctx, bucket, opts, budget, date, slot, live, manifest);
}

export { runBackup, dateStamp, manifestKey, snapshotKey, isDailySlotHour, hourSlot, isLastOpportunity };
