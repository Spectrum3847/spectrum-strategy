import { matchLabel } from "../data/matchKey";
import { formatStat } from "./format";
import type { SeriesPoint } from "./stats";

export const minTrendPoints = 3;

const slot = 40;
const height = 150;
const top = 22;
const bottom = 26;

export function TrendChart({ series }: { series: SeriesPoint[] }) {
  const width = series.length * slot;
  const max = Math.max(...series.map((p) => p.value), 1);
  const plot = height - top - bottom;
  const description = series
    .map((p) => `${matchLabel(p.key)} ${formatStat(p.value)}`)
    .join(", ");
  return (
    <div className="team-scroll">
      <svg
        className="team-chart"
        viewBox={`0 0 ${width} ${height}`}
        style={{
          width: "100%",
          minWidth: series.length * 30,
          maxWidth: series.length * 48,
        }}
        role="img"
        aria-label={`Match total per match: ${description}`}
      >
        <line
          x1={0}
          x2={width}
          y1={height - bottom}
          y2={height - bottom}
          className="team-chart-base"
        />
        {series.map((p, i) => {
          const barHeight = (p.value / max) * plot;
          const x = i * slot + slot / 2;
          return (
            <g key={p.key}>
              <rect
                x={x - 11}
                y={height - bottom - barHeight}
                width={22}
                height={Math.max(barHeight, 1)}
                rx={2}
                className="team-chart-bar"
              />
              <text
                x={x}
                y={height - bottom - barHeight - 5}
                textAnchor="middle"
                className="team-chart-value"
              >
                {formatStat(p.value)}
              </text>
              <text
                x={x}
                y={height - 8}
                textAnchor="middle"
                className="team-chart-label"
              >
                {matchLabel(p.key)}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}
