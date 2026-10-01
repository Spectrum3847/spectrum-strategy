import { runQuery, whereQuery, patchDocument } from '../firestore.mjs';
import {
  buildIssueTitle,
  buildIssueBody,
  issueLabels,
  splitByReporterCap,
} from './lib/report_issue.mjs';
import {
  ATTACHMENTS_RELEASE_BODY,
  ATTACHMENTS_TAG,
  assetName,
  contentTypeForKey,
  issueNumberFromAssetName,
  screenshotKeys,
  screenshotSection,
} from './lib/report_attachments.mjs';

const DEFAULT_REPO = 'Spectrum3847/SpectrumStrategy';

const MAX_REPORTS_PER_RUN = 6;

const REPORTS_PER_REPORTER_LIMIT = 3;

const MAX_PRUNE_CHECKS = 10;

function ghHeaders(token) {
  return {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'User-Agent': 'spectrumstrategy-cron-worker',
  };
}

function createGitHubClient(fetchImpl, env) {
  return {
    repo: env.GITHUB_REPO || DEFAULT_REPO,
    headers: ghHeaders(env.GH_TOKEN),
    fetch: (url, init) => fetchImpl(url, init),
  };
}

async function createIssue(gh, report) {
  const res = await gh.fetch(`https://api.github.com/repos/${gh.repo}/issues`, {
    method: 'POST',
    headers: { ...gh.headers, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      title: buildIssueTitle(report),
      body: buildIssueBody(report),
      labels: issueLabels(report),
    }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`GitHub ${res.status}: ${text.slice(0, 200)}`);
  }
  return res.json();
}

async function readScreenshot(bucket, key) {
  const object = await bucket.get(key);
  if (!object) {
    console.warn(`No object for ${key} in the photo bucket.`);
    return null;
  }
  return object.arrayBuffer();
}

async function findAttachmentsRelease(gh) {
  const existing = await gh.fetch(
    `https://api.github.com/repos/${gh.repo}/releases/tags/${ATTACHMENTS_TAG}`,
    { headers: gh.headers },
  );
  if (!existing.ok) return null;
  return (await existing.json()).id;
}

async function resolveAttachmentsRelease(gh) {
  const found = await findAttachmentsRelease(gh);
  if (found !== null) return found;
  const created = await gh.fetch(`https://api.github.com/repos/${gh.repo}/releases`, {
    method: 'POST',
    headers: { ...gh.headers, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      tag_name: ATTACHMENTS_TAG,
      name: 'Report attachments',
      body: ATTACHMENTS_RELEASE_BODY,
      prerelease: true,
      make_latest: 'false',
    }),
  });
  if (!created.ok) {
    throw new Error(`Could not create the attachments release: ${created.status}`);
  }
  return (await created.json()).id;
}

async function listAssets(gh, releaseId) {
  const assets = [];
  for (let page = 1; ; page++) {
    const res = await gh.fetch(
      `https://api.github.com/repos/${gh.repo}/releases/${releaseId}/assets` +
        `?per_page=100&page=${page}`,
      { headers: gh.headers },
    );
    if (!res.ok) throw new Error(`Could not list assets: ${res.status}`);
    const batch = await res.json();
    assets.push(...batch);
    if (batch.length < 100) return assets;
  }
}

async function deleteAsset(gh, assetId) {
  await gh.fetch(`https://api.github.com/repos/${gh.repo}/releases/assets/${assetId}`, {
    method: 'DELETE',
    headers: gh.headers,
  });
}

async function uploadAsset(gh, releaseId, name, contentType, bytes) {
  const post = () =>
    gh.fetch(
      `https://uploads.github.com/repos/${gh.repo}/releases/${releaseId}/assets` +
        `?name=${encodeURIComponent(name)}`,
      { method: 'POST', headers: { ...gh.headers, 'Content-Type': contentType }, body: bytes },
    );
  let res = await post();
  if (res.status === 422) {
    const match = (await listAssets(gh, releaseId)).find((asset) => asset.name === name);
    if (match) await deleteAsset(gh, match.id);
    res = await post();
  }
  if (!res.ok) throw new Error(`Asset upload failed for ${name}: ${res.status}`);
  return (await res.json()).browser_download_url;
}

async function attachScreenshots(gh, bucket, issue, report, noteFailure) {
  try {
    await attachScreenshotsOrThrow(gh, bucket, issue, report);
  } catch (err) {
    noteFailure(`attaching screenshots to #${issue.number}`, err);
  }
}

async function attachScreenshotsOrThrow(gh, bucket, issue, report) {
  const keys = screenshotKeys(report);
  if (keys.length === 0) return;
  if (!bucket) {
    console.log(`No photo bucket binding; skipping ${keys.length} screenshot(s).`);
    return;
  }

  const releaseId = await resolveAttachmentsRelease(gh);
  const urls = [];
  for (const [index, key] of keys.entries()) {
    try {
      const bytes = await readScreenshot(bucket, key);
      if (!bytes) continue;
      urls.push(
        await uploadAsset(
          gh,
          releaseId,
          assetName(issue.number, index, key),
          contentTypeForKey(key),
          bytes,
        ),
      );
    } catch (err) {

      throw new Error(`screenshot ${key}: ${err && err.message ? err.message : err}`);
    }
  }
  if (urls.length === 0) return;

  const res = await gh.fetch(`https://api.github.com/repos/${gh.repo}/issues/${issue.number}`, {
    method: 'PATCH',
    headers: { ...gh.headers, 'Content-Type': 'application/json' },
    body: JSON.stringify({ body: `${issue.body}\n${screenshotSection(urls)}` }),
  });
  if (!res.ok) {
    throw new Error(`Could not attach screenshots to #${issue.number}: ${res.status}`);
  }
}

async function pruneClosedAttachments(gh) {
  const releaseId = await findAttachmentsRelease(gh);
  if (releaseId === null) return 0;
  const assets = await listAssets(gh, releaseId);
  const states = new Map();
  let pruned = 0;
  for (const asset of assets) {
    const number = issueNumberFromAssetName(asset.name);
    if (number === null) continue;
    if (!states.has(number)) {
      if (states.size >= MAX_PRUNE_CHECKS) break;
      const res = await gh.fetch(`https://api.github.com/repos/${gh.repo}/issues/${number}`, {
        headers: gh.headers,
      });

      states.set(number, res.ok ? (await res.json()).state : res.status === 404 ? 'closed' : null);
    }
    if (states.get(number) !== 'closed') continue;
    await deleteAsset(gh, asset.id);
    pruned++;
  }
  if (pruned > 0) console.log(`Pruned ${pruned} attachment(s) from closed issues.`);
  return pruned;
}

async function runReport(ctx) {
  const { project, env } = ctx;
  if (!env.GH_TOKEN) {
    console.log('GH_TOKEN is not set; skipping report filing.');
    return { skipped: 'no-gh-token' };
  }
  const gh = createGitHubClient(ctx.fetchImpl, env);
  const opts = await ctx.opts();

  const rows = await runQuery(
    project,
    whereQuery('bugReports', [{ fieldPath: 'status', op: 'EQUAL', value: 'new' }], {
      limit: MAX_REPORTS_PER_RUN,
    }),
    opts,
  );
  const entries = rows.map(({ id, data }) => ({ id, data, reporterUid: data.reporterUid }));
  const { allowed, capped } = splitByReporterCap(entries, REPORTS_PER_REPORTER_LIMIT);
  for (const entry of capped) {
    console.log(
      `Skipping ${entry.id}: reporter ${entry.reporterUid || 'unknown'} hit the ` +
        `per-run cap of ${REPORTS_PER_REPORTER_LIMIT}.`,
    );
  }

  let opened = 0;
  for (const entry of allowed) {
    try {
      const issue = await createIssue(gh, entry.data);

      await attachScreenshots(gh, env.PHOTOS, issue, entry.data, ctx.noteFailure);
      await patchDocument(
        project,
        `bugReports/${entry.id}`,
        {
          status: 'opened',
          issueNumber: issue.number,
          issueUrl: issue.html_url,
          openedAt: ctx.nowIso(),
        },
        ['status', 'issueNumber', 'issueUrl', 'openedAt'],
        opts,
      );
      opened++;
    } catch (err) {
      ctx.noteFailure(`opening an issue for ${entry.id}`, err);
    }
  }

  let pruned = 0;
  try {
    pruned = await pruneClosedAttachments(gh);
  } catch (err) {
    ctx.noteFailure('pruning attachments', err);
  }

  console.log(`Reports: opened ${opened} issue(s), capped ${capped.length}, pruned ${pruned}.`);
  return { opened, capped: capped.length, pruned };
}

export { runReport, createGitHubClient };
