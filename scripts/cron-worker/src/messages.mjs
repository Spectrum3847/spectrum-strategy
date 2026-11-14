function matchRangeLabel(startMatch, endMatch) {
  return startMatch === endMatch
    ? `match ${startMatch}`
    : `matches ${startMatch}-${endMatch}`;
}

function buildShiftStartDmText({ startMatch, endMatch }) {
  return (
    `Heads up: your scouting shift starts at ${matchRangeLabel(startMatch, endMatch)} soon. ` +
    'Check the Scout shifts screen in the app.'
  );
}

function buildTradeRequestDmText({ requesterDisplayName, startMatch, endMatch }) {
  const who = requesterDisplayName || 'A teammate';
  return (
    `${who} asked you to cover their scouting shift at ` +
    `${matchRangeLabel(startMatch, endMatch)}. Open the Scout shifts screen ` +
    'in the app to accept or decline.'
  );
}

function buildShiftPushPayload({ eventKey, startMatch, endMatch, station, away }) {
  const when = away <= 0 ? 'is next' : `starts in ${away} match${away === 1 ? '' : 'es'}`;
  const where = station ? ` at ${station}` : '';
  return {
    title: `Your scouting shift ${when}`,
    body: `Scout ${matchRangeLabel(startMatch, endMatch)}${where}. Head to the stands.`,
    tag: `shift-${eventKey}-${startMatch}`,
    url: '/scout',
  };
}

function buildTestPushPayload(nowMs) {
  return {
    title: 'Shift reminders are on',
    body: 'This is a test. Your real reminders come 3 matches before each shift.',
    tag: `test-${nowMs}`,
    url: '/settings?s=device',
  };
}

export {
  buildShiftPushPayload,
  buildShiftStartDmText,
  buildTestPushPayload,
  buildTradeRequestDmText,
  matchRangeLabel,
};
