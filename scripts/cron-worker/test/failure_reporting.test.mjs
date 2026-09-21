import { test } from 'node:test';
import assert from 'node:assert/strict';

import { createContext } from '../src/context.mjs';

test('a context with nothing recorded reports no failures', () => {
  const ctx = createContext({});
  assert.deepEqual(ctx.failures(), []);
});

test('a recorded failure is kept with what failed and why', () => {
  const ctx = createContext({});
  ctx.noteFailure('opening an issue for abc', new Error('GitHub 403'));
  ctx.noteFailure('pruning attachments', 'boom');
  const failures = ctx.failures();
  assert.equal(failures.length, 2);
  assert.match(failures[0], /opening an issue for abc/);
  assert.match(failures[0], /GitHub 403/);
  assert.match(failures[1], /pruning attachments/);
});

test('failures() returns a copy, so a caller cannot edit the record', () => {
  const ctx = createContext({});
  ctx.noteFailure('one', 'x');
  ctx.failures().push('invented');
  assert.equal(ctx.failures().length, 1);
});
