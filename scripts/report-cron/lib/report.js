'use strict';

function clamp(value, max) {
  return String(value == null ? '' : value).slice(0, max);
}

function isFeedback(report) {
  return report.kind === 'feedback';
}

function splitByReporterCap(reports, limit) {
  const seen = new Map();
  const allowed = [];
  const capped = [];
  for (const report of reports) {
    const uid = report.reporterUid || 'unknown';
    const count = seen.get(uid) || 0;
    if (count >= limit) {
      capped.push(report);
      continue;
    }
    seen.set(uid, count + 1);
    allowed.push(report);
  }
  return { allowed, capped };
}

function issueLabels(report) {
  return [isFeedback(report) ? 'enhancement' : 'bug', 'from-app'];
}

function buildIssueTitle(report) {
  const title = clamp(report.title, 120).trim() || 'Report';
  const name = clamp(report.reporterName, 80).trim() || 'unknown';
  const prefix = isFeedback(report) ? '[App feedback]' : '[App bug]';
  return `${prefix} ${title} (from ${name})`;
}

function buildIssueBody(report) {
  const lines = [];
  if (report.area) lines.push(`**Area:** ${clamp(report.area, 64)}`, '');
  if (!isFeedback(report) && report.impact) {
    lines.push(`**Impact:** ${clamp(report.impact, 64)}`, '');
  }
  const body = clamp(report.body, 8000).trim();
  if (body) {
    lines.push(isFeedback(report) ? '**Feedback**' : '**What happened**', body, '');
  }
  lines.push('---', 'Filed from the Spectrum Strategy app.');
  lines.push(
    `Reporter: ${clamp(report.reporterName, 80) || 'unknown'} ` +
      `(uid ${clamp(report.reporterUid, 128) || 'unknown'})`,
  );
  if (report.roles) lines.push(`Roles: ${clamp(report.roles, 128)}`);
  if (report.appVersion) lines.push(`App version: ${clamp(report.appVersion, 64)}`);
  if (report.platform) lines.push(`Platform: ${clamp(report.platform, 64)}`);
  if (report.osVersion) lines.push(`OS: ${clamp(report.osVersion, 128)}`);
  if (report.deviceInfo) lines.push(`Device: ${clamp(report.deviceInfo, 256)}`);
  if (report.createdAt) lines.push(`Reported at: ${clamp(report.createdAt, 64)}`);
  return lines.join('\n');
}

module.exports = { buildIssueTitle, buildIssueBody, issueLabels, splitByReporterCap };
