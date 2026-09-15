'use strict';

const DEFAULT_LOWER_MATCHES = 2;
const DEFAULT_UPPER_MATCHES = 3;

function isShiftStartingSoon({
  currentMatch,
  blockStartMatch,
  lowerMatches = DEFAULT_LOWER_MATCHES,
  upperMatches = DEFAULT_UPPER_MATCHES,
}) {
  if (!Number.isFinite(currentMatch) || !Number.isFinite(blockStartMatch)) {
    return false;
  }
  const away = blockStartMatch - currentMatch;
  return away >= lowerMatches && away <= upperMatches;
}

function nextMatchNumber(playedMatchNumbers) {
  if (!Array.isArray(playedMatchNumbers) || playedMatchNumbers.length === 0) {
    return 1;
  }
  return Math.max(...playedMatchNumbers) + 1;
}

module.exports = { isShiftStartingSoon, nextMatchNumber };
