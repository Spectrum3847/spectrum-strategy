'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  assetName,
  contentTypeForKey,
  issueNumberFromAssetName,
  screenshotKeys,
  screenshotSection,
} = require('../lib/attachments');

const KEY = '0f8fad5b-d9cb-469f-a165-70867728950e.png';
const KEY_TWO = '7c9e6679-7425-40de-944b-e07fc1f90ae7.jpg';

test('keeps only keys the photo Worker could have minted', () => {
  assert.deepEqual(
    screenshotKeys({
      screenshotKeys: [KEY, '../../etc/passwd', 'not-a-uuid.png', 42, KEY_TWO],
    }),
    [KEY, KEY_TWO],
  );
});

test('drops duplicates and caps at three', () => {
  const keys = [
    KEY,
    KEY,
    KEY_TWO,
    '3f2504e0-4f89-11d3-9a0c-0305e82c3301.webp',
    '11111111-2222-3333-4444-555555555555.png',
  ];
  assert.deepEqual(screenshotKeys({ screenshotKeys: keys }), [
    KEY,
    KEY_TWO,
    '3f2504e0-4f89-11d3-9a0c-0305e82c3301.webp',
  ]);
});

test('a report with no screenshots yields none', () => {
  assert.deepEqual(screenshotKeys({}), []);
  assert.deepEqual(screenshotKeys({ screenshotKeys: 'nope' }), []);
});

test('an asset name carries the issue number and round-trips', () => {
  const name = assetName(1662, 0, KEY);
  assert.equal(name, 'issue-1662-1.png');
  assert.equal(issueNumberFromAssetName(name), 1662);
  assert.equal(assetName(1662, 2, KEY_TWO), 'issue-1662-3.jpg');
});

test('an asset this cron did not write has no issue number', () => {
  assert.equal(issueNumberFromAssetName('SpectrumStrategy-linux.AppImage'), null);
  assert.equal(issueNumberFromAssetName('issue-abc-1.png'), null);
  assert.equal(issueNumberFromAssetName('issue-12.png'), null);
});

test('the content type follows the key extension', () => {
  assert.equal(contentTypeForKey(KEY), 'image/png');
  assert.equal(contentTypeForKey(KEY_TWO), 'image/jpeg');
  assert.equal(contentTypeForKey('nonsense'), 'application/octet-stream');
});

test('the screenshot section renders one image per url', () => {
  assert.equal(
    screenshotSection(['https://example.com/a.png', 'https://example.com/b.png']),
    '\n### Screenshots\n\n![Screenshot](https://example.com/a.png)\n\n![Screenshot](https://example.com/b.png)',
  );
  assert.equal(screenshotSection([]), '');
});
