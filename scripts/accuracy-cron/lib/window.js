'use strict';

const DEFAULT_OVERLAP_MINUTES = 5;
const DEFAULT_MAX_LOOKBACK_DAYS = 7;

function computeWindowStart({
  watermark,
  nowMs,
  fallbackMinutes,
  overlapMinutes = DEFAULT_OVERLAP_MINUTES,
  maxLookbackDays = DEFAULT_MAX_LOOKBACK_DAYS,
}) {
  const floorMs = nowMs - maxLookbackDays * 24 * 60 * 60 * 1000;
  const fallbackMs = nowMs - fallbackMinutes * 60 * 1000;

  const watermarkMs =
    typeof watermark === 'string' ? Date.parse(watermark) : NaN;
  if (Number.isNaN(watermarkMs)) {
    return new Date(Math.max(fallbackMs, floorMs)).toISOString();
  }

  const startMs = watermarkMs - overlapMinutes * 60 * 1000;
  return new Date(Math.min(Math.max(startMs, floorMs), nowMs)).toISOString();
}

module.exports = { computeWindowStart };
