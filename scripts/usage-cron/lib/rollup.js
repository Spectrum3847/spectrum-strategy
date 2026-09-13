'use strict';

const WINDOW_DAYS = 30;

const MAX_DAILY = WINDOW_DAYS;

function windowStart(now, days = WINDOW_DAYS) {
  const start = new Date(now.getTime() - days * 24 * 60 * 60 * 1000);
  return start.toISOString();
}

function bump(counts, key) {
  if (!key) return;
  counts[key] = (counts[key] || 0) + 1;
}

function ranked(counts) {
  return Object.entries(counts)
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
}

function buildRollup(events, now, days = WINDOW_DAYS) {
  const since = windowStart(now, days);
  const tabs = {};
  const platforms = {};
  const appVersions = {};
  const perDay = {};
  const devices = new Set();
  let counted = 0;

  for (const event of events) {
    const createdAt = typeof event.createdAt === 'string' ? event.createdAt : '';
    if (!createdAt || createdAt < since) continue;
    counted += 1;

    if (event.deviceId) devices.add(event.deviceId);
    bump(platforms, event.platform);
    bump(appVersions, event.appVersion);

    bump(perDay, createdAt.slice(0, 10));

    if (event.type === 'tab_open') bump(tabs, event.detail);
  }

  const daily = Object.entries(perDay)
    .map(([date, count]) => ({ date, count }))
    .sort((a, b) => a.date.localeCompare(b.date))
    .slice(-MAX_DAILY);

  return {
    updatedAt: now.toISOString(),
    windowDays: days,
    since,
    eventsCounted: counted,
    deviceCount: devices.size,
    tabs: ranked(tabs),
    platforms: ranked(platforms),
    appVersions: ranked(appVersions),
    daily,
  };
}

module.exports = { buildRollup, windowStart, ranked, WINDOW_DAYS };
