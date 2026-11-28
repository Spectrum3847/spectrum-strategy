import { Link } from "react-router";
import { matchLabel } from "../data/matchKey";
import { formatStat } from "../team/format";
import type { SeriesPoint } from "../team/stats";
import { minTrendPoints } from "../team/TrendChart";
import { useOnline } from "../ui/useOnline";
import { maxCompare } from "./compare";
import type { useTeamData } from "./useTeamData";
import "./teams.css";

export function Missing({ why = "no data" }: { why?: string }) {
  return (
    <>
      <span aria-hidden="true">-</span>
      <span className="sr-only">{why}</span>
    </>
  );
}

const sparkW = 72;
const sparkH = 24;
const sparkPad = 3;

export function Sparkline({ series }: { series: SeriesPoint[] }) {
  if (series.length < minTrendPoints) {
    return <Missing why={`fewer than ${minTrendPoints} scored matches`} />;
  }
  const values = series.map((p) => p.value);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const x = (i: number) =>
    sparkPad + (i * (sparkW - 2 * sparkPad)) / (series.length - 1);
  const y = (v: number) =>
    max === min
      ? sparkH / 2
      : sparkH - sparkPad - ((v - min) / (max - min)) * (sparkH - 2 * sparkPad);
  const points = values
    .map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`)
    .join(" ");
  const description = series
    .map((p) => `${matchLabel(p.key)} ${formatStat(p.value)}`)
    .join(", ");
  return (
    <svg
      className="spark"
      viewBox={`0 0 ${sparkW} ${sparkH}`}
      width={sparkW}
      height={sparkH}
      role="img"
      aria-label={`Match totals: ${description}`}
    >
      <polyline
        points={points}
        fill="none"
        stroke="currentColor"
        strokeWidth={2}
        strokeLinejoin="round"
        strokeLinecap="round"
      />
      <circle
        cx={x(values.length - 1)}
        cy={y(values[values.length - 1] ?? 0)}
        r={2.5}
        fill="currentColor"
      />
    </svg>
  );
}

export function CompareCheck({
  team,
  checked,
  disabled,
  onToggle,
}: {
  team: number;
  checked: boolean;
  disabled: boolean;
  onToggle: (team: number) => void;
}) {
  return (
    <label className="teams-check">
      <input
        type="checkbox"
        checked={checked}
        disabled={disabled && !checked}
        aria-label={`Compare ${team}`}
        onChange={() => onToggle(team)}
      />
    </label>
  );
}

export function DataNotices({
  data,
}: {
  data: ReturnType<typeof useTeamData>;
}) {
  const online = useOnline();
  const { eventKey, eventReady, tba, entries } = data;
  return (
    <>
      {eventKey === "" && eventReady === false && (
        <p className="secondary" role="status">
          Loading the event.
        </p>
      )}
      {eventKey === "" && eventReady !== false && (
        <p className="secondary" role="status">
          No event is set, so there are no event teams.{" "}
          <Link to="/settings?s=event">Pick one in Settings</Link>.
        </p>
      )}
      {!online && (
        <p className="secondary" role="status">
          Offline. This shows what this device last saved.
        </p>
      )}
      {entries.failed && (
        <p className="notice" role="status">
          Could not read the latest scout entries. The stats may be incomplete.
        </p>
      )}
      {entries.correctionsFailed && (
        <p className="notice" role="status">
          Could not read the latest corrections. The stats may show uncorrected
          values.
        </p>
      )}
      {eventKey !== "" && tba.status === "failed" && tba.fetchedAt === null && (
        <p className="secondary" role="status">
          Team names and ranks need a connection the first time.
        </p>
      )}
      {eventKey !== "" && !entries.ready && (
        <p className="secondary" role="status">
          {online
            ? "Loading scouted stats."
            : "Scouted stats load from this device. If none appear, connect once to load them."}
        </p>
      )}
    </>
  );
}

export const compareLimitNote = `Compare takes up to ${maxCompare} teams.`;
