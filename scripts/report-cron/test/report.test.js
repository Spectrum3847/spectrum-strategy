'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { buildIssueTitle, buildIssueBody, issueLabels, splitByReporterCap } = require('../lib/report');

test('buildIssueTitle marks a bug report from the app and names the reporter', () => {
  const t = buildIssueTitle({ title: 'Board wont save', reporterName: 'JaneD' });
  assert.equal(t, '[App bug] Board wont save (from JaneD)');
});

test('buildIssueTitle marks a feedback report differently', () => {
  const t = buildIssueTitle({
    kind: 'feedback',
    title: 'Add dark mode',
    reporterName: 'JaneD',
  });
  assert.equal(t, '[App feedback] Add dark mode (from JaneD)');
});

test('buildIssueTitle falls back when fields are missing', () => {
  assert.equal(buildIssueTitle({}), '[App bug] Report (from unknown)');
});

test('issueLabels tags a bug report bug + from-app', () => {
  assert.deepEqual(issueLabels({ kind: 'bug' }), ['bug', 'from-app']);
  assert.deepEqual(issueLabels({}), ['bug', 'from-app']);
});

test('issueLabels tags a feedback report enhancement + from-app', () => {
  assert.deepEqual(issueLabels({ kind: 'feedback' }), ['enhancement', 'from-app']);
});

test('buildIssueBody includes area, description and debug metadata', () => {
  const body = buildIssueBody({
    title: 'x',
    area: 'Strategy board',
    impact: 'Blocks work completely',
    body: 'The board did not save my drawing.',
    reporterName: 'JaneD',
    reporterUid: 'uid123',
    roles: 'Strategist, Admin',
    appVersion: '1.0.0+1',
    platform: 'android',
    osVersion: 'Android 15',
    deviceInfo: 'Google Pixel 8 (Android 15, SDK 35)',
    createdAt: '2026-07-05T20:00:00.000Z',
  });
  assert.match(body, /\*\*Area:\*\* Strategy board/);
  assert.match(body, /\*\*Impact:\*\* Blocks work completely/);
  assert.match(body, /\*\*What happened\*\*/);
  assert.match(body, /The board did not save my drawing\./);
  assert.match(body, /Filed from the Spectrum Strategy app\./);
  assert.match(body, /Reporter: JaneD \(uid uid123\)/);
  assert.match(body, /Roles: Strategist, Admin/);
  assert.match(body, /App version: 1\.0\.0\+1/);
  assert.match(body, /Platform: android/);
  assert.match(body, /OS: Android 15/);
  assert.match(body, /Device: Google Pixel 8 \(Android 15, SDK 35\)/);
  assert.match(body, /Reported at: 2026-07-05T20:00:00\.000Z/);
});

test('buildIssueBody labels a feedback report body differently and skips impact', () => {
  const body = buildIssueBody({
    kind: 'feedback',
    impact: 'Blocks work completely',
    body: 'Please add dark mode.',
    reporterName: 'A',
    reporterUid: 'u',
  });
  assert.match(body, /\*\*Feedback\*\*/);
  assert.equal(body.includes('**What happened**'), false);
  assert.equal(body.includes('**Impact:**'), false);
});

test('splitByReporterCap allows up to the limit per reporterUid', () => {
  const reports = [
    { reporterUid: 'a' },
    { reporterUid: 'a' },
    { reporterUid: 'b' },
    { reporterUid: 'a' },
  ];
  const { allowed, capped } = splitByReporterCap(reports, 2);
  assert.equal(allowed.length, 3);
  assert.equal(capped.length, 1);
  assert.equal(capped[0], reports[3]);
});

test('splitByReporterCap treats a missing reporterUid as one shared bucket', () => {
  const reports = [{}, {}, {}];
  const { allowed, capped } = splitByReporterCap(reports, 2);
  assert.equal(allowed.length, 2);
  assert.equal(capped.length, 1);
});

test('splitByReporterCap does not cap when every reporter is under the limit', () => {
  const reports = [{ reporterUid: 'a' }, { reporterUid: 'b' }];
  const { allowed, capped } = splitByReporterCap(reports, 5);
  assert.equal(allowed.length, 2);
  assert.equal(capped.length, 0);
});

test('buildIssueBody omits missing optional metadata lines', () => {
  const body = buildIssueBody({ body: 'hi', reporterName: 'A', reporterUid: 'u' });
  assert.equal(body.includes('App version:'), false);
  assert.equal(body.includes('Platform:'), false);
  assert.equal(body.includes('Device:'), false);
  assert.equal(body.includes('Roles:'), false);
  assert.equal(body.includes('**Area:**'), false);
  assert.match(body, /Reporter: A \(uid u\)/);
});

test('buildIssueBody passes through an area value that no longer appears in the dropdown', () => {

  const body = buildIssueBody({
    area: 'Retired category from an old build',
    body: 'Still happens.',
    reporterName: 'JaneD',
    reporterUid: 'uid123',
  });
  assert.match(body, /\*\*Area:\*\* Retired category from an old build/);
});
