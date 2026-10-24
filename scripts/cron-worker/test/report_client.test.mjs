import { test } from 'node:test';
import assert from 'node:assert/strict';

import { createGitHubClient } from '../src/crons/report.mjs';

function strictFetch(url, init) {
  if (this !== undefined && this !== globalThis) {
    throw new TypeError(
      'Illegal invocation: function called with incorrect `this` reference.',
    );
  }
  strictFetch.calls.push({ url, init });
  return new Response('{}', { status: 200 });
}

test('the client calls fetch without handing it the client as `this`', async () => {
  strictFetch.calls = [];
  const gh = createGitHubClient(strictFetch, { GH_TOKEN: 'token' });
  await gh.fetch('https://api.github.com/repos/o/r/issues', { method: 'POST' });
  assert.equal(strictFetch.calls.length, 1);
  assert.equal(strictFetch.calls[0].init.method, 'POST');
});

test('the client carries the repo and the auth headers', () => {
  const gh = createGitHubClient(() => {}, { GH_TOKEN: 'token' });
  assert.equal(gh.repo, 'Spectrum3847/SpectrumStrategy');
  assert.equal(gh.headers.Authorization, 'Bearer token');

  const override = createGitHubClient(() => {}, { GH_TOKEN: 't', GITHUB_REPO: 'o/r' });
  assert.equal(override.repo, 'o/r');
});
