'use strict';

const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const { buildIssueTitle, buildIssueBody, issueLabels, splitByReporterCap } = require('./lib/report');
const {
  ATTACHMENTS_RELEASE_BODY,
  ATTACHMENTS_TAG,
  assetName,
  contentTypeForKey,
  issueNumberFromAssetName,
  screenshotKeys,
  screenshotSection,
} = require('./lib/attachments');
const { isFirestoreQuotaExceeded, parseServiceAccount } = require('shared-cron-utils');

const REPO = process.env.GITHUB_REPOSITORY || 'Spectrum3847/SpectrumStrategy';
const GH_TOKEN = process.env.GH_TOKEN;

const CF_TOKEN = process.env.CLOUDFLARE_API_TOKEN;
const CF_ACCOUNT = process.env.CLOUDFLARE_ACCOUNT_ID || 'ffd3e8ee831a6d15ce589f05d1116734';
const CF_BUCKET = process.env.R2_BUCKET || 'spectrumstrategy-photos';

const GH_HEADERS = {
  Authorization: `Bearer ${GH_TOKEN}`,
  Accept: 'application/vnd.github+json',
  'User-Agent': 'spectrumstrategy-report-cron',
};

const REPORTS_PER_REPORTER_LIMIT = 5;

async function createIssue(report) {
  const res = await fetch(`https://api.github.com/repos/${REPO}/issues`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${GH_TOKEN}`,
      Accept: 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'User-Agent': 'spectrumstrategy-report-cron',
    },
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

async function fetchScreenshot(key) {
  const url =
    `https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT}` +
    `/r2/buckets/${CF_BUCKET}/objects/${encodeURIComponent(key)}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${CF_TOKEN}` } });
  if (!res.ok) {
    console.warn(`Could not read ${key} from R2: ${res.status}`);
    return null;
  }
  return Buffer.from(await res.arrayBuffer());
}

let attachmentsReleaseId;
async function findAttachmentsRelease() {
  if (attachmentsReleaseId !== undefined) return attachmentsReleaseId;
  const existing = await fetch(
    `https://api.github.com/repos/${REPO}/releases/tags/${ATTACHMENTS_TAG}`,
    { headers: GH_HEADERS },
  );
  if (!existing.ok) return null;
  attachmentsReleaseId = (await existing.json()).id;
  return attachmentsReleaseId;
}

async function resolveAttachmentsRelease() {
  const found = await findAttachmentsRelease();
  if (found !== null) return found;
  const created = await fetch(`https://api.github.com/repos/${REPO}/releases`, {
    method: 'POST',
    headers: { ...GH_HEADERS, 'Content-Type': 'application/json' },
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
  attachmentsReleaseId = (await created.json()).id;
  return attachmentsReleaseId;
}

async function uploadAsset(releaseId, name, contentType, bytes) {
  const post = () =>
    fetch(
      `https://uploads.github.com/repos/${REPO}/releases/${releaseId}/assets` +
        `?name=${encodeURIComponent(name)}`,
      { method: 'POST', headers: { ...GH_HEADERS, 'Content-Type': contentType }, body: bytes },
    );
  let res = await post();
  if (res.status === 422) {
    await deleteAssetNamed(releaseId, name);
    res = await post();
  }
  if (!res.ok) {
    throw new Error(`Asset upload failed for ${name}: ${res.status}`);
  }
  return (await res.json()).browser_download_url;
}

async function listAssets(releaseId) {
  const assets = [];
  for (let page = 1; ; page++) {
    const res = await fetch(
      `https://api.github.com/repos/${REPO}/releases/${releaseId}/assets` +
        `?per_page=100&page=${page}`,
      { headers: GH_HEADERS },
    );
    if (!res.ok) throw new Error(`Could not list assets: ${res.status}`);
    const batch = await res.json();
    assets.push(...batch);
    if (batch.length < 100) return assets;
  }
}

async function deleteAsset(assetId) {
  await fetch(`https://api.github.com/repos/${REPO}/releases/assets/${assetId}`, {
    method: 'DELETE',
    headers: GH_HEADERS,
  });
}

async function deleteAssetNamed(releaseId, name) {
  const match = (await listAssets(releaseId)).find((asset) => asset.name === name);
  if (match) await deleteAsset(match.id);
}

async function attachScreenshots(issue, report) {
  try {
    await attachScreenshotsOrThrow(issue, report);
  } catch (err) {
    console.error(
      `Attaching screenshots to #${issue.number} failed:`,
      err && err.message ? err.message : err,
    );
  }
}

async function attachScreenshotsOrThrow(issue, report) {
  const keys = screenshotKeys(report);
  if (keys.length === 0 || !CF_TOKEN) {
    if (keys.length > 0) {
      console.log(`CLOUDFLARE_API_TOKEN is not set; skipping ${keys.length} screenshot(s).`);
    }
    return;
  }

  const releaseId = await resolveAttachmentsRelease();
  const urls = [];
  for (const [index, key] of keys.entries()) {
    try {
      const bytes = await fetchScreenshot(key);
      if (!bytes) continue;
      urls.push(
        await uploadAsset(
          releaseId,
          assetName(issue.number, index, key),
          contentTypeForKey(key),
          bytes,
        ),
      );
    } catch (err) {
      console.error(`Screenshot ${key} for #${issue.number}:`, err && err.message ? err.message : err);
    }
  }
  if (urls.length === 0) return;

  const res = await fetch(`https://api.github.com/repos/${REPO}/issues/${issue.number}`, {
    method: 'PATCH',
    headers: { ...GH_HEADERS, 'Content-Type': 'application/json' },
    body: JSON.stringify({ body: `${issue.body}\n${screenshotSection(urls)}` }),
  });
  if (!res.ok) {
    throw new Error(`Could not attach screenshots to #${issue.number}: ${res.status}`);
  }
}

async function pruneClosedAttachments() {
  const releaseId = await findAttachmentsRelease();
  if (releaseId === null) return;
  const assets = await listAssets(releaseId);
  const states = new Map();
  let pruned = 0;
  for (const asset of assets) {
    const number = issueNumberFromAssetName(asset.name);
    if (number === null) continue;
    if (!states.has(number)) {
      const res = await fetch(`https://api.github.com/repos/${REPO}/issues/${number}`, {
        headers: GH_HEADERS,
      });

      states.set(number, res.ok ? (await res.json()).state : res.status === 404 ? 'closed' : null);
    }
    if (states.get(number) !== 'closed') continue;
    await deleteAsset(asset.id);
    pruned++;
  }
  if (pruned > 0) console.log(`Pruned ${pruned} attachment(s) from closed issues.`);
}

async function main() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) {
    console.log('FIREBASE_SERVICE_ACCOUNT is not set; skipping run.');
    return;
  }
  if (!GH_TOKEN) {
    console.log('GH_TOKEN is not set; skipping run.');
    return;
  }

  initializeApp({ credential: cert(parseServiceAccount(raw)) });
  const db = getFirestore();

  const snap = await db
    .collection('bugReports')
    .where('status', '==', 'new')
    .limit(50)
    .get();
  console.log(`${snap.size} new report(s).`);

  const entries = snap.docs.map((doc) => ({
    id: doc.id,
    ref: doc.ref,
    data: doc.data(),
    reporterUid: doc.data().reporterUid,
  }));
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
      const issue = await createIssue(entry.data);

      await attachScreenshots(issue, entry.data);
      await entry.ref.update({
        status: 'opened',
        issueNumber: issue.number,
        issueUrl: issue.html_url,
        openedAt: new Date().toISOString(),
      });
      opened++;
    } catch (err) {
      console.error(
        `Failed to open an issue for ${entry.id}:`,
        err && err.message ? err.message : err,
      );
    }
  }

  console.log(`Done: opened ${opened} issue(s), capped ${capped.length}.`);

  try {
    await pruneClosedAttachments();
  } catch (err) {
    console.error('Pruning attachments failed:', err && err.message ? err.message : err);
  }
}

main().catch((err) => {
  if (isFirestoreQuotaExceeded(err)) {
    console.warn(
      'report-cron: Firestore quota exhausted; skipping this run. ' +
        'Nothing to do until the quota resets.',
    );
    return;
  }
  console.error('report-cron failed:', err);
  process.exitCode = 1;
});
