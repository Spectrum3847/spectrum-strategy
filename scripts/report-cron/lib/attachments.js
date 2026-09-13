'use strict';

const KEY_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.([a-z]{3,4})$/;

const MAX_SCREENSHOTS = 3;

const CONTENT_TYPE_BY_EXTENSION = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  heic: 'image/heic',
};

const ATTACHMENTS_TAG = 'report-attachments';

const ATTACHMENTS_RELEASE_BODY =
  'Screenshots attached to reports filed from the app, re-hosted here so ' +
  'GitHub can render them in the issue they belong to. Not a build. Assets ' +
  'are named after their issue and are deleted once that issue closes.';

function screenshotKeys(report) {
  const raw = Array.isArray(report.screenshotKeys) ? report.screenshotKeys : [];
  const seen = new Set();
  const keys = [];
  for (const key of raw) {
    if (typeof key !== 'string' || !KEY_PATTERN.test(key)) continue;
    if (seen.has(key)) continue;
    seen.add(key);
    keys.push(key);
    if (keys.length >= MAX_SCREENSHOTS) break;
  }
  return keys;
}

function assetName(issueNumber, index, key) {
  const extension = KEY_PATTERN.exec(key)?.[1] ?? 'png';
  return `issue-${issueNumber}-${index + 1}.${extension}`;
}

function issueNumberFromAssetName(name) {
  const match = /^issue-(\d+)-\d+\.[a-z]{3,4}$/.exec(name);
  return match ? Number(match[1]) : null;
}

function contentTypeForKey(key) {
  const extension = KEY_PATTERN.exec(key)?.[1];
  return CONTENT_TYPE_BY_EXTENSION[extension] ?? 'application/octet-stream';
}

function screenshotSection(urls) {
  if (urls.length === 0) return '';
  const lines = ['', '### Screenshots', ''];
  for (const url of urls) lines.push(`![Screenshot](${url})`, '');
  return lines.join('\n').trimEnd();
}

module.exports = {
  ATTACHMENTS_TAG,
  ATTACHMENTS_RELEASE_BODY,
  MAX_SCREENSHOTS,
  assetName,
  contentTypeForKey,
  issueNumberFromAssetName,
  screenshotKeys,
  screenshotSection,
};
