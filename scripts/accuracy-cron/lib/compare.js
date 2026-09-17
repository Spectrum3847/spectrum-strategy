'use strict';

function numOr(v, def) {
  return typeof v === 'number' && Number.isFinite(v) ? v : def;
}

function toBool(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v !== 0;
  if (typeof v === 'string') {
    const s = v.toLowerCase();
    return s === 'true' || s === '1' || s === 'yes';
  }
  return false;
}

function resolveStatboticsPath(path, alliance) {
  return path
    .replace(/\{alliance\}/g, alliance)
    .replace(/^red_/, `${alliance}_`)
    .replace(/^blue_/, `${alliance}_`);
}

function getNestedValue(obj, path) {
  const parts = path.split('.');
  let current = obj;
  for (const part of parts) {
    if (current === null || current === undefined || typeof current !== 'object') {
      return undefined;
    }
    current = current[part];
  }
  return current;
}

function compareEntry(entry, matchData, cfg) {
  const mappings = Array.isArray(cfg.mappings) ? cfg.mappings : [];

  const perFieldTolerancePct = numOr(cfg.perFieldTolerancePct, 50);
  const perFieldAbsoluteMin = numOr(cfg.perFieldAbsoluteMin, 2);
  const minWrongFields = numOr(cfg.minWrongFields, 3);
  const minWrongFraction = numOr(cfg.minWrongFraction, 0.5);
  const egregiousAbsMin = numOr(cfg.egregiousAbsMin, 5);
  const egregiousPct = numOr(cfg.egregiousPct, 200);

  const alliance = (entry.alliance || 'Red').toLowerCase();
  const fieldValues = entry.fieldValues || {};

  let comparedCount = 0;
  let wrongCount = 0;
  let egregiousFlag = false;
  const flaggedFields = [];

  for (const mapping of mappings) {
    const { scoutFieldCode, statboticsPath, type } = mapping;
    if (!scoutFieldCode || !statboticsPath) continue;

    const resolvedPath = resolveStatboticsPath(statboticsPath, alliance);
    const officialValue = getNestedValue(matchData, resolvedPath);
    if (officialValue === undefined || officialValue === null) continue;

    const scoutedRaw = fieldValues[scoutFieldCode];
    if (scoutedRaw === undefined || scoutedRaw === null) continue;

    comparedCount++;

    let wrong = false;
    let egregious = false;

    if (type === 'boolean') {
      const scoutedBool = toBool(scoutedRaw);
      const officialBool = toBool(officialValue);
      wrong = scoutedBool !== officialBool;
    } else {
      const scoutedNum = Number(scoutedRaw);
      const officialNum = Number(officialValue);
      if (!Number.isFinite(scoutedNum) || !Number.isFinite(officialNum)) continue;

      const diff = Math.abs(scoutedNum - officialNum);
      const tolerancePct = numOr(mapping.tolerancePct, perFieldTolerancePct);
      const absMin = numOr(mapping.absoluteMin, perFieldAbsoluteMin);

      if (diff < absMin) {
        wrong = false;
      } else if (officialNum === 0) {

        wrong = true;
      } else {
        const devPct = (diff / Math.abs(officialNum)) * 100;
        wrong = devPct > tolerancePct;
        if (wrong && diff >= egregiousAbsMin && devPct >= egregiousPct) {
          egregious = true;
        }
      }
    }

    if (wrong) {
      wrongCount++;
      flaggedFields.push({
        fieldCode: scoutFieldCode,
        scoutedValue: scoutedRaw,
        officialValue,
      });
      if (egregious) egregiousFlag = true;
    }
  }

  let fires = false;
  if (comparedCount > 0) {
    const threshold = Math.max(
      minWrongFields,
      Math.ceil(minWrongFraction * comparedCount),
    );
    fires = wrongCount >= threshold || egregiousFlag;
  }

  return {
    comparedCount,
    wrongCount,
    egregious: egregiousFlag,
    flaggedFields,
    fires,
  };
}

function escapeSlack(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function buildScouterDmText(alert) {
  const fieldList = alert.flaggedFields
    .map(
      (f) =>
        `${escapeSlack(f.fieldCode)} (scouted: ${escapeSlack(f.scoutedValue)}, official: ${escapeSlack(f.officialValue)})`,
    )
    .join(', ');
  const severity = alert.egregious ? 'likely has a wrong entry' : 'may be inaccurate';
  return (
    `Heads up from SpectrumStrategy: your scouting for match ` +
    `${escapeSlack(alert.tbaMatchKey)} (team ${escapeSlack(alert.teamNumber)}) ${severity}.\n` +
    `Wrong: ${alert.wrongCount}/${alert.comparedCount} fields\n` +
    `Flagged: ${fieldList}\n\n` +
    `Please review and re-scout this match if the entry is wrong.`
  );
}

function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

module.exports = {
  numOr,
  toBool,
  resolveStatboticsPath,
  getNestedValue,
  compareEntry,
  buildScouterDmText,
  normalizeEmail,
  escapeSlack,
};
