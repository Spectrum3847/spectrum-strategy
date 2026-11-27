const DAILY_WINDOW_DAYS = 14;
const WEEKLY_WINDOW_WEEKS = 8;
const DAY_MS = 24 * 60 * 60 * 1000;

function daysBefore(dateStr, todayStr) {
  return Math.round(
    (Date.parse(`${todayStr}T00:00:00Z`) - Date.parse(`${dateStr}T00:00:00Z`)) / DAY_MS,
  );
}

function keepDate(dateStr, todayStr) {
  const age = daysBefore(dateStr, todayStr);
  if (age < 0 || age <= DAILY_WINDOW_DAYS) return true;
  const weeksOut = Math.floor((age - DAILY_WINDOW_DAYS - 1) / 7);
  if (weeksOut >= WEEKLY_WINDOW_WEEKS) return false;
  return new Date(`${dateStr}T00:00:00Z`).getUTCDay() === 0;
}

function datesToPrune(existingDates, todayStr) {
  return existingDates.filter((date) => !keepDate(date, todayStr));
}

export { DAILY_WINDOW_DAYS, WEEKLY_WINDOW_WEEKS, keepDate, datesToPrune };
