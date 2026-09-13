'use strict';

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

module.exports = { buildShiftStartDmText, buildTradeRequestDmText, matchRangeLabel };
